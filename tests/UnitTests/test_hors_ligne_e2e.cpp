// Essai de bout en bout « poste hors ligne » : trois instances completes
// d'Application (serveur S + clients A et B) sur le meme port d'election,
// comme test_bascule_e2e. Verifie :
//   1. un message envoye a B eteint est conserve par le serveur (meme entre
//      deux clients) et accuse a l'expediteur ;
//   2. B le recoit a son retour, y compris quand la synchronisation de
//      connexion a lieu avant le login (nouvelle synchronisation au login) ;
//   3. apres une coupure de la connexion, les clients se reconnectent seuls ;
//   4. un message ecrit sans connexion part a la reconnexion (file d'envoi).
#include <QtTest>
#include <QHostAddress>
#include <QRandomGenerator>
#include <QSignalSpy>
#include <QSqlQuery>
#include <QTemporaryDir>

#include "Application.h"
#include "DatabaseManager.h"
#include "MessagingManager.h"
#include "PermissionManager.h"
#include "UserManager.h"
#include "Election/ElectionService.h"
#include "Messaging/MessagingServer.h"
#include "Messaging/MessagingService.h"
#include "Security/SecurityService.h"
#include "models/Message.h"

class TestHorsLigneE2E : public QObject
{
    Q_OBJECT

    struct Poste {
        std::unique_ptr<Application> app;
        QString name;
        QString role;
        quint16 port = 0;
        int priority = -1;
        QString fingerprint;
        bool connectedTo(quint16 serverPort) const
        {
            return app->messagingService()->isConnected() && app->messagingService()->peerPort() == serverPort;
        }
    };

    QTemporaryDir m_dir;
    quint16 m_base = 0;
    quint16 m_electionPort = 0;

    void boot(Poste &p)
    {
        p.app = std::make_unique<Application>();
        p.app->setDiscoveryPort(static_cast<quint16>(p.port + 5));
        p.app->initialize(p.port, m_dir.filePath(p.name + QStringLiteral(".db")), p.role, p.priority, m_electionPort);
        p.app->electionService()->setHeartbeatIntervalMs(300);
        p.app->electionService()->setHeartbeatTimeoutMs(2000);
        p.app->electionService()->setElectionWindowMs(400);
        p.fingerprint = p.app->securityService()->identity().fingerprintSha256.toLower();
    }

    static int userId(Application &app, const QString &name)
    {
        for (const auto &u : app.userManager()->allUsers())
            if (u.name() == name) return u.id();
        return -1;
    }

    // Etat d'envoi du message (vide s'il est absent de la base).
    static QString status(Application &app, const QString &content)
    {
        QSqlQuery q(app.databaseManager()->database());
        q.prepare(QStringLiteral("SELECT delivery_status FROM Messages WHERE content = :c"));
        q.bindValue(QStringLiteral(":c"), content);
        return q.exec() && q.next() ? q.value(0).toString() : QString();
    }

    static bool hasMessage(Application &app, const QString &content) { return !status(app, content).isEmpty(); }

    static bool journaled(Application &app, const QString &content)
    {
        QSqlQuery q(app.databaseManager()->database());
        q.prepare(QStringLiteral("SELECT 1 FROM SyncLog WHERE table_name = 'Messages' AND payload_json LIKE :c"));
        q.bindValue(QStringLiteral(":c"), QStringLiteral("%") + content + QStringLiteral("%"));
        return q.exec() && q.next();
    }

    static bool send(Application &app, const QString &from, const QString &to, const QString &content)
    {
        const int a = userId(app, from), b = userId(app, to);
        const auto conv = app.messagingManager()->getOrCreateConversation(a, b);
        return conv && app.messagingManager()->sendMessage(conv->id(), a, content).has_value();
    }

private slots:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        m_base = static_cast<quint16>(36000 + QRandomGenerator::global()->bounded(1500) * 10);
        m_electionPort = static_cast<quint16>(m_base + 9);
    }

    void horsLigneEtReconnexion()
    {
        Poste s{nullptr, QStringLiteral("serveur"), QStringLiteral("SERVER"), m_base, -1, {}};
        Poste a{nullptr, QStringLiteral("client-a"), QStringLiteral("CLIENT"), static_cast<quint16>(m_base + 10), 10, {}};
        Poste b{nullptr, QStringLiteral("client-b"), QStringLiteral("CLIENT"), static_cast<quint16>(m_base + 20), 20, {}};
        boot(s);
        const auto admin = s.app->userManager()->createUser(QStringLiteral("admin"), QStringLiteral("motdepasse"));
        QVERIFY(admin.has_value());
        QVERIFY(s.app->userManager()->createUser(QStringLiteral("alice"), QStringLiteral("motdepasse")).has_value());
        QVERIFY(s.app->userManager()->createUser(QStringLiteral("bob"), QStringLiteral("motdepasse")).has_value());
        QVERIFY(s.app->userManager()->login(QStringLiteral("admin"), QStringLiteral("motdepasse")));

        boot(a);
        boot(b);
        for (Poste *c : {&a, &b}) {
            QVERIFY(s.app->permissionManager()->authorizeMachineByCertificate(
                c->fingerprint, c->name, c->name.toUpper(), QStringLiteral("127.0.0.1"), admin->id(), QStringLiteral("essai")));
            QVERIFY(c->app->permissionManager()->approveServerCertificate(s.fingerprint, QStringLiteral("127.0.0.1")));
        }
        QTRY_VERIFY_WITH_TIMEOUT(a.connectedTo(s.port) && b.connectedTo(s.port), 20000);
        QTRY_VERIFY_WITH_TIMEOUT(userId(*a.app, QStringLiteral("bob")) > 0 && userId(*b.app, QStringLiteral("alice")) > 0
                                 && userId(*b.app, QStringLiteral("admin")) > 0, 10000);
        QVERIFY(a.app->userManager()->login(QStringLiteral("alice"), QStringLiteral("motdepasse")));
        QVERIFY(b.app->userManager()->login(QStringLiteral("bob"), QStringLiteral("motdepasse")));
        QTest::qWait(1000);

        // Temoin : les deux en ligne ; l'expediteur recoit l'accuse du serveur.
        QVERIFY(send(*a.app, QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("en ligne A->B")));
        QTRY_VERIFY_WITH_TIMEOUT(hasMessage(*b.app, QStringLiteral("en ligne A->B")), 10000);
        QTRY_COMPARE_WITH_TIMEOUT(status(*a.app, QStringLiteral("en ligne A->B")), models::Message::Sent, 10000);

        // 1. B est eteint ; A et S lui ecrivent.
        b.app.reset();
        QTest::qWait(500);
        QSignalSpy failedS(s.app->messagingManager(), &core::MessagingManager::messageSendFailed);
        QVERIFY(send(*a.app, QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("absent A->B")));
        QVERIFY(send(*s.app, QStringLiteral("admin"), QStringLiteral("bob"), QStringLiteral("absent S->B")));
        // Le serveur conserve le message entre deux clients (journal), sans
        // l'afficher a son utilisateur, et l'accuse a l'expediteur.
        QTRY_VERIFY_WITH_TIMEOUT(journaled(*s.app, QStringLiteral("absent A->B")), 10000);
        QVERIFY(!hasMessage(*s.app, QStringLiteral("absent A->B")));
        QTRY_COMPARE_WITH_TIMEOUT(status(*a.app, QStringLiteral("absent A->B")), models::Message::Sent, 10000);
        // Le serveur ne signale plus d'echec : le message est conserve chez lui.
        QCOMPARE(failedS.count(), 0);

        // 2. B redemarre : synchronisation a la connexion (avant login), puis au login.
        boot(b);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(s.port), 20000);
        QTest::qWait(2000);
        QVERIFY(!hasMessage(*b.app, QStringLiteral("absent A->B"))); // personne de connecte : comptes seulement
        QVERIFY(b.app->userManager()->login(QStringLiteral("bob"), QStringLiteral("motdepasse")));
        QTRY_VERIFY_WITH_TIMEOUT(hasMessage(*b.app, QStringLiteral("absent A->B")), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(hasMessage(*b.app, QStringLiteral("absent S->B")), 10000);

        // 3. Coupure courte de la connexion (le serveur relance son ecoute, sans
        //    election) : les clients se reconnectent seuls.
        s.app->messagingServer()->stop();
        QTest::qWait(300);
        QVERIFY(s.app->messagingServer()->start(s.port));
        QTRY_VERIFY_WITH_TIMEOUT(a.connectedTo(s.port) && b.connectedTo(s.port), 20000);

        // 4. Expediteur sans connexion : bob ecrit pendant que le serveur n'ecoute
        //    plus ; le message part a la reconnexion et A le recoit.
        s.app->messagingServer()->stop();
        QTRY_VERIFY_WITH_TIMEOUT(!b.connectedTo(s.port), 5000);
        QVERIFY(send(*b.app, QStringLiteral("bob"), QStringLiteral("alice"), QStringLiteral("coupure B->A")));
        QCOMPARE(status(*b.app, QStringLiteral("coupure B->A")), models::Message::Pending);
        QVERIFY(s.app->messagingServer()->start(s.port));
        QTRY_VERIFY_WITH_TIMEOUT(hasMessage(*a.app, QStringLiteral("coupure B->A")), 30000);
        QTRY_COMPARE_WITH_TIMEOUT(status(*b.app, QStringLiteral("coupure B->A")), models::Message::Sent, 10000);
        // Un seul exemplaire chez le destinataire (renvoi dedoublonne).
        QSqlQuery count(a.app->databaseManager()->database());
        QVERIFY(count.exec(QStringLiteral("SELECT COUNT(*) FROM Messages WHERE content = 'coupure B->A'")) && count.next());
        QCOMPARE(count.value(0).toInt(), 1);
    }
};

QTEST_MAIN(TestHorsLigneE2E)
#include "test_hors_ligne_e2e.moc"
