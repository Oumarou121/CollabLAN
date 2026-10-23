// Essai de bout en bout des fonctions de messagerie qui traversent le serveur
// et son journal, avec des instances completes d'Application sur le meme port
// d'election (comme test_bascule_e2e) :
//   1. accuses « remis » et « lu », en ligne puis pour un destinataire absent ;
//   2. modification et suppression d'un message, y compris pour un absent ;
//   3. groupe renomme puis supprime par son proprietaire ; un autre membre ne
//      peut pas en changer la composition (refus du serveur) ;
//   4. panne : un message entre deux clients relaye par le serveur de secours
//      est recupere par le serveur officiel a son retour, et remis ensuite au
//      destinataire qui etait absent ;
//   5. changements faits hors connexion, transmis a la reconnexion (file d'attente) ;
//   6. changement de groupe pendant une panne : attend le serveur officiel ;
//   7. accuse « lu » envoye au serveur de secours : parvient a l'expediteur ;
//   8. evenement d'audit enregistre hors connexion : parvient au serveur ;
//   9. dossiers partages : partage cible, partage et retrait rattrapes au retour.
#include <QtTest>
#include <QDir>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QSqlQuery>
#include <QTemporaryDir>

#include "Application.h"
#include "DatabaseManager.h"
#include "GroupManager.h"
#include "SharedFolderManager.h"
#include "MessagingManager.h"
#include "MessagingContext.h"
#include "PermissionManager.h"
#include "UserManager.h"
#include "Election/ElectionService.h"
#include "Messaging/MessagingServer.h"
#include "Messaging/MessagingService.h"
#include "Security/SecurityService.h"
#include "models/Message.h"
#include "models/ServerElection.h"

class TestMessagesE2E : public QObject
{
    Q_OBJECT

    struct Poste {
        std::unique_ptr<Application> app;
        QString name;
        QString role;
        quint16 port = 0;
        int priority = -1;
        QString fingerprint;
        network::ElectionService *election() const { return app->electionService(); }
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
    static QString userUuid(Application &app, const QString &name)
    {
        for (const auto &u : app.userManager()->allUsers())
            if (u.name() == name) return u.uuid();
        return {};
    }
    static QString scalar(Application &app, const QString &sql)
    {
        QSqlQuery q(app.databaseManager()->database());
        return q.exec(sql) && q.next() ? q.value(0).toString() : QString();
    }
    static QString status(Application &app, const QString &content)
    {
        return scalar(app, QStringLiteral("SELECT delivery_status FROM Messages WHERE content = '%1'").arg(content));
    }
    static bool hasMessage(Application &app, const QString &content)
    {
        return !scalar(app, QStringLiteral("SELECT 1 FROM Messages WHERE content = '%1'").arg(content)).isEmpty();
    }
    static std::optional<models::Message> send(Application &app, const QString &from, const QString &to, const QString &content)
    {
        const int a = userId(app, from), b = userId(app, to);
        const auto conv = app.messagingManager()->getOrCreateConversation(a, b);
        return conv ? app.messagingManager()->sendMessage(conv->id(), a, content) : std::nullopt;
    }

    // Serveur S (admin + comptes), clients autorises et approuves, connectes.
    void startNetwork(Poste &s, QList<Poste *> clients, const QStringList &accounts)
    {
        boot(s);
        const auto admin = s.app->userManager()->createUser(QStringLiteral("admin"), QStringLiteral("motdepasse"));
        QVERIFY(admin.has_value());
        for (const QString &name : accounts)
            QVERIFY(s.app->userManager()->createUser(name, QStringLiteral("motdepasse")).has_value());
        for (Poste *c : clients) {
            boot(*c);
            QVERIFY(s.app->permissionManager()->authorizeMachineByCertificate(
                c->fingerprint, c->name, c->name.toUpper(), QStringLiteral("127.0.0.1"), admin->id(), QStringLiteral("essai")));
            QVERIFY(c->app->permissionManager()->approveServerCertificate(s.fingerprint, QStringLiteral("127.0.0.1")));
        }
        for (Poste *c : clients) {
            QTRY_VERIFY_WITH_TIMEOUT(c->connectedTo(s.port), 20000);
            QTRY_VERIFY_WITH_TIMEOUT(userId(*c->app, accounts.last()) > 0, 10000);
        }
    }

    static void login(Poste &p, const QString &name)
    {
        QVERIFY(p.app->userManager()->login(name, QStringLiteral("motdepasse")));
    }

    Poste poste(const QString &name, const QString &role, int offset, int priority)
    {
        return Poste{nullptr, name, role, static_cast<quint16>(m_base + offset), priority, {}};
    }

private slots:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        m_base = static_cast<quint16>(40000 + QRandomGenerator::global()->bounded(1000) * 10);
    }

    void receiptsDeliveredAndRead()
    {
        m_electionPort = static_cast<quint16>(m_base + 9);
        Poste s = poste(QStringLiteral("r-serveur"), QStringLiteral("SERVER"), 0, -1);
        Poste a = poste(QStringLiteral("r-a"), QStringLiteral("CLIENT"), 10, 10);
        Poste b = poste(QStringLiteral("r-b"), QStringLiteral("CLIENT"), 20, 20);
        startNetwork(s, {&a, &b}, {QStringLiteral("alice"), QStringLiteral("bob")});
        login(a, QStringLiteral("alice"));
        login(b, QStringLiteral("bob"));
        QTest::qWait(800);

        // En ligne : remis des que B l'a recu, lu quand bob ouvre la conversation.
        const auto first = send(*a.app, QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("accuse en ligne"));
        QVERIFY(first.has_value());
        QTRY_COMPARE_WITH_TIMEOUT(status(*a.app, QStringLiteral("accuse en ligne")), models::Message::Delivered, 10000);
        const qint64 convB = scalar(*b.app, QStringLiteral("SELECT conversationId FROM Messages WHERE content = 'accuse en ligne'")).toLongLong();
        QVERIFY(b.app->messagingManager()->markConversationAsRead(convB, userId(*b.app, QStringLiteral("bob"))));
        QTRY_COMPARE_WITH_TIMEOUT(status(*a.app, QStringLiteral("accuse en ligne")), models::Message::Read, 10000);

        // B absent : seulement « envoye » ; « remis » quand bob revient et se connecte.
        b.app.reset();
        QTest::qWait(500);
        QVERIFY(send(*a.app, QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("accuse absent")).has_value());
        QTRY_COMPARE_WITH_TIMEOUT(status(*a.app, QStringLiteral("accuse absent")), models::Message::Sent, 10000);
        QTest::qWait(1000);
        QCOMPARE(status(*a.app, QStringLiteral("accuse absent")), models::Message::Sent);
        boot(b);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(s.port), 20000);
        login(b, QStringLiteral("bob"));
        QTRY_VERIFY_WITH_TIMEOUT(hasMessage(*b.app, QStringLiteral("accuse absent")), 10000);
        QTRY_COMPARE_WITH_TIMEOUT(status(*a.app, QStringLiteral("accuse absent")), models::Message::Delivered, 10000);
    }

    // Liste des discussions (ecran Discussions) : discussion ouverte des deux
    // cotes, chaque message envoye ou recu doit devenir l'apercu. Bug signale :
    // l'apercu restait sur l'avant-dernier message tant qu'on ne recliquait
    // pas sur la discussion.
    void conversationPreviewFollowsLiveMessages()
    {
        m_electionPort = static_cast<quint16>(m_base + 909);
        Poste s = poste(QStringLiteral("l-serveur"), QStringLiteral("SERVER"), 900, -1);
        Poste a = poste(QStringLiteral("l-a"), QStringLiteral("CLIENT"), 910, 10);
        Poste b = poste(QStringLiteral("l-b"), QStringLiteral("CLIENT"), 920, 20);
        startNetwork(s, {&a, &b}, {QStringLiteral("alice"), QStringLiteral("bob")});
        login(a, QStringLiteral("alice"));
        login(b, QStringLiteral("bob"));
        QTest::qWait(800);

        // Comme main.cpp : un contexte par poste, discussion ouverte.
        const auto contextFor = [](Application &app) {
            auto ctx = std::make_unique<core::MessagingContext>();
            ctx->setMessagingManager(app.messagingManager());
            ctx->setGroupManager(app.groupManager());
            ctx->setUserManager(app.userManager());
            return ctx;
        };
        auto ctxA = contextFor(*a.app);
        auto ctxB = contextFor(*b.app);
        const qint64 convA = ctxA->startConversationWith(userId(*a.app, QStringLiteral("bob")));
        QVERIFY(convA > 0);
        const auto previewOf = [](core::MessagingContext &ctx) {
            QStringList all;
            for (const QVariant &v : ctx.conversationsList())
                all << v.toMap().value(QStringLiteral("lastMessage")).toString();
            return all.join(QStringLiteral(" | "));
        };
        previewOf(*ctxA);
        previewOf(*ctxB);

        ctxA->sendMessage(QStringLiteral("bonjour bob"));
        QCOMPARE(previewOf(*ctxA), QStringLiteral("Moi : bonjour bob"));
        QTRY_COMPARE_WITH_TIMEOUT(previewOf(*ctxB), QStringLiteral("Lui : bonjour bob"), 10000);

        // Bob ouvre la discussion, puis repond : chacun voit le dernier message.
        const qint64 convB = scalar(*b.app, QStringLiteral("SELECT conversationId FROM Messages WHERE content = 'bonjour bob'")).toLongLong();
        ctxB->setConversation(convB);
        for (int i = 1; i <= 3; ++i) {
            const QString fromBob = QStringLiteral("reponse %1").arg(i);
            ctxB->sendMessage(fromBob);
            QCOMPARE(previewOf(*ctxB), QStringLiteral("Moi : ") + fromBob);
            QTRY_COMPARE_WITH_TIMEOUT(previewOf(*ctxA), QStringLiteral("Lui : ") + fromBob, 10000);
            const QString fromAlice = QStringLiteral("suite %1").arg(i);
            ctxA->sendMessage(fromAlice);
            QCOMPARE(previewOf(*ctxA), QStringLiteral("Moi : ") + fromAlice);
            QTRY_COMPARE_WITH_TIMEOUT(previewOf(*ctxB), QStringLiteral("Lui : ") + fromAlice, 10000);
        }
    }

    void editAndDeleteReachAbsentRecipient()
    {
        m_electionPort = static_cast<quint16>(m_base + 109);
        Poste s = poste(QStringLiteral("e-serveur"), QStringLiteral("SERVER"), 100, -1);
        Poste a = poste(QStringLiteral("e-a"), QStringLiteral("CLIENT"), 110, 10);
        Poste b = poste(QStringLiteral("e-b"), QStringLiteral("CLIENT"), 120, 20);
        startNetwork(s, {&a, &b}, {QStringLiteral("alice"), QStringLiteral("bob")});
        login(a, QStringLiteral("alice"));
        login(b, QStringLiteral("bob"));
        QTest::qWait(800);

        const auto m1 = send(*a.app, QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("brouillon"));
        const auto m2 = send(*a.app, QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("a effacer"));
        QVERIFY(m1 && m2);
        QTRY_VERIFY_WITH_TIMEOUT(hasMessage(*b.app, QStringLiteral("a effacer")), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(status(*a.app, QStringLiteral("a effacer")) != models::Message::Pending, 10000);

        // En ligne : la modification arrive chez B.
        const int alice = userId(*a.app, QStringLiteral("alice"));
        QVERIFY(a.app->messagingManager()->editMessage(m1->uuid(), QStringLiteral("version finale"), alice));
        QTRY_VERIFY_WITH_TIMEOUT(hasMessage(*b.app, QStringLiteral("version finale")), 10000);
        QVERIFY(!scalar(*b.app, QStringLiteral("SELECT edited_at FROM Messages WHERE uuid = '%1'").arg(m1->uuid())).isEmpty());
        // Bob ne peut pas modifier le message d'alice (refus local).
        QVERIFY(!b.app->messagingManager()->editMessage(m1->uuid(), QStringLiteral("pirate"), userId(*b.app, QStringLiteral("bob"))));

        // B absent : la suppression lui parvient a son retour.
        b.app.reset();
        QTest::qWait(500);
        QVERIFY(a.app->messagingManager()->deleteMessage(m2->uuid(), alice));
        QVERIFY(scalar(*a.app, QStringLiteral("SELECT content FROM Messages WHERE uuid = '%1'").arg(m2->uuid())).isEmpty());
        boot(b);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(s.port), 20000);
        login(b, QStringLiteral("bob"));
        QTRY_VERIFY_WITH_TIMEOUT(!scalar(*b.app, QStringLiteral("SELECT deleted_at FROM Messages WHERE uuid = '%1'").arg(m2->uuid())).isEmpty(), 10000);
        QVERIFY(!hasMessage(*b.app, QStringLiteral("a effacer")));
    }

    void groupRenameDeleteAndOwnerCheck()
    {
        m_electionPort = static_cast<quint16>(m_base + 209);
        Poste s = poste(QStringLiteral("g-serveur"), QStringLiteral("SERVER"), 200, -1);
        Poste a = poste(QStringLiteral("g-a"), QStringLiteral("CLIENT"), 210, 10);
        Poste b = poste(QStringLiteral("g-b"), QStringLiteral("CLIENT"), 220, 20);
        startNetwork(s, {&a, &b}, {QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("chloe")});
        login(a, QStringLiteral("alice"));
        login(b, QStringLiteral("bob"));
        QTest::qWait(800);

        const int alice = userId(*a.app, QStringLiteral("alice"));
        const auto group = a.app->groupManager()->createGroup(QStringLiteral("Equipe"), alice, {userId(*a.app, QStringLiteral("bob"))});
        QVERIFY(group.has_value());
        QTRY_VERIFY_WITH_TIMEOUT(!scalar(*b.app, QStringLiteral("SELECT 1 FROM Groups WHERE uuid = '%1'").arg(group->uuid())).isEmpty(), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(!scalar(*s.app, QStringLiteral("SELECT 1 FROM Groups WHERE uuid = '%1'").arg(group->uuid())).isEmpty(), 10000);

        // Bob (simple membre) tente d'ajouter chloe : le serveur refuse.
        const QJsonObject forged{{QStringLiteral("type"), QStringLiteral("member_added")},
                                 {QStringLiteral("groupUuid"), group->uuid()},
                                 {QStringLiteral("memberUuid"), userUuid(*b.app, QStringLiteral("chloe"))}};
        QVERIFY(b.app->messagingService()->sendMessage(QString::fromUtf8(QJsonDocument(forged).toJson(QJsonDocument::Compact))));
        QTest::qWait(1500);
        const QString countSql = QStringLiteral(
            "SELECT COUNT(*) FROM GroupMembers gm JOIN Groups g ON g.id = gm.group_id WHERE g.uuid = '%1'").arg(group->uuid());
        const int membersOnServer = scalar(*s.app, countSql).toInt();
        QVERIFY(scalar(*s.app, QStringLiteral(
            "SELECT 1 FROM GroupMembers gm JOIN Groups g ON g.id = gm.group_id JOIN Users u ON u.id = gm.user_id "
            "WHERE g.uuid = '%1' AND u.name = 'chloe'").arg(group->uuid())).isEmpty());
        QVERIFY(membersOnServer >= 1);

        // Renommage par la proprietaire : visible chez bob.
        QVERIFY(a.app->groupManager()->renameGroup(group->id(), QStringLiteral("Equipe projet"), alice));
        QTRY_COMPARE_WITH_TIMEOUT(scalar(*b.app, QStringLiteral("SELECT name FROM Groups WHERE uuid = '%1'").arg(group->uuid())),
                                  QStringLiteral("Equipe projet"), 10000);
        // Bob ne peut ni renommer ni supprimer (refus local).
        const qint64 bobGroupId = scalar(*b.app, QStringLiteral("SELECT id FROM Groups WHERE uuid = '%1'").arg(group->uuid())).toLongLong();
        QVERIFY(!b.app->groupManager()->deleteGroup(bobGroupId, userId(*b.app, QStringLiteral("bob"))));

        // Bob absent ; la proprietaire supprime le groupe ; il disparait chez bob a son retour.
        b.app.reset();
        QTest::qWait(500);
        QVERIFY(a.app->groupManager()->deleteGroup(group->id(), alice));
        QVERIFY(scalar(*a.app, QStringLiteral("SELECT 1 FROM Groups WHERE uuid = '%1'").arg(group->uuid())).isEmpty());
        boot(b);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(s.port), 20000);
        login(b, QStringLiteral("bob"));
        QTRY_VERIFY_WITH_TIMEOUT(scalar(*b.app, QStringLiteral("SELECT 1 FROM Groups WHERE uuid = '%1'").arg(group->uuid())).isEmpty(), 10000);
    }

    void messageDuringOutageReachesAbsentRecipient()
    {
        m_electionPort = static_cast<quint16>(m_base + 309);
        Poste s = poste(QStringLiteral("p-serveur"), QStringLiteral("SERVER"), 300, -1);
        Poste a = poste(QStringLiteral("p-a"), QStringLiteral("CLIENT"), 310, 10);   // elu secours
        Poste b = poste(QStringLiteral("p-b"), QStringLiteral("CLIENT"), 320, 20);
        Poste c = poste(QStringLiteral("p-c"), QStringLiteral("CLIENT"), 330, 30);
        startNetwork(s, {&a, &b, &c}, {QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("chloe")});
        login(a, QStringLiteral("alice"));
        login(b, QStringLiteral("bob"));
        login(c, QStringLiteral("chloe"));
        QTest::qWait(800);

        // Panne : A devient serveur de secours, B et C le rejoignent.
        s.app.reset();
        QTRY_COMPARE_WITH_TIMEOUT(a.election()->role(), models::ServerRole::TempServer, 20000);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(a.port) && c.connectedTo(a.port), 30000);
        QTest::qWait(500);

        // C s'eteint ; bob lui ecrit : le message ne transite que par le secours.
        c.app.reset();
        QTest::qWait(500);
        QVERIFY(send(*b.app, QStringLiteral("bob"), QStringLiteral("chloe"), QStringLiteral("pendant la panne")).has_value());
        QTRY_COMPARE_WITH_TIMEOUT(status(*b.app, QStringLiteral("pendant la panne")), models::Message::Sent, 10000);
        QVERIFY(!hasMessage(*a.app, QStringLiteral("pendant la panne"))); // garde au journal, pas affiche

        // Retour du serveur officiel : reconciliation, puis il reprend la main.
        boot(s);
        QTRY_COMPARE_WITH_TIMEOUT(a.election()->role(), models::ServerRole::Client, 30000);
        QTRY_VERIFY_WITH_TIMEOUT(!scalar(*s.app, QStringLiteral(
            "SELECT 1 FROM SyncLog WHERE table_name = 'Messages' AND payload_json LIKE '%pendant la panne%'")).isEmpty(), 20000);

        // C revient : il le recoit du serveur officiel.
        boot(c);
        QTRY_VERIFY_WITH_TIMEOUT(c.connectedTo(s.port), 30000);
        login(c, QStringLiteral("chloe"));
        QTRY_VERIFY_WITH_TIMEOUT(hasMessage(*c.app, QStringLiteral("pendant la panne")), 15000);
    }

    // Hors connexion : modification de message, renommage et ajout de membre
    // sont appliques tout de suite, gardes en file d'attente, puis transmis a la
    // reconnexion ; la file se vide sur accuse du serveur.
    void offlineChangesSentOnReconnect()
    {
        m_electionPort = static_cast<quint16>(m_base + 409);
        Poste s = poste(QStringLiteral("o-serveur"), QStringLiteral("SERVER"), 400, -1);
        Poste a = poste(QStringLiteral("o-a"), QStringLiteral("CLIENT"), 410, 10);
        Poste b = poste(QStringLiteral("o-b"), QStringLiteral("CLIENT"), 420, 20);
        startNetwork(s, {&a, &b}, {QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("chloe")});
        login(a, QStringLiteral("alice"));
        login(b, QStringLiteral("bob"));
        QTest::qWait(800);

        const int alice = userId(*a.app, QStringLiteral("alice"));
        const auto msg = send(*a.app, QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("texte initial"));
        QVERIFY(msg.has_value());
        const auto group = a.app->groupManager()->createGroup(QStringLiteral("Atelier"), alice, {userId(*a.app, QStringLiteral("bob"))});
        QVERIFY(group.has_value());
        QTRY_VERIFY_WITH_TIMEOUT(hasMessage(*b.app, QStringLiteral("texte initial")), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(!scalar(*b.app, QStringLiteral("SELECT 1 FROM Groups WHERE uuid = '%1'").arg(group->uuid())).isEmpty(), 10000);
        QTRY_COMPARE_WITH_TIMEOUT(scalar(*a.app, QStringLiteral("SELECT COUNT(*) FROM Outbox")), QStringLiteral("0"), 10000);

        // Le serveur n'ecoute plus : alice change tout hors connexion.
        s.app->messagingServer()->stop();
        QTRY_VERIFY_WITH_TIMEOUT(!a.connectedTo(s.port), 5000);
        QVERIFY(a.app->messagingManager()->editMessage(msg->uuid(), QStringLiteral("texte corrige hors ligne"), alice));
        QVERIFY(a.app->groupManager()->renameGroup(group->id(), QStringLiteral("Atelier renomme"), alice));
        QVERIFY(a.app->groupManager()->addMember(group->id(), userId(*a.app, QStringLiteral("chloe")), alice));
        QCOMPARE(scalar(*a.app, QStringLiteral("SELECT COUNT(*) FROM Outbox")), QStringLiteral("3"));

        // Retour : reconnexion automatique, transmission, accuses.
        QVERIFY(s.app->messagingServer()->start(s.port));
        QTRY_VERIFY_WITH_TIMEOUT(hasMessage(*b.app, QStringLiteral("texte corrige hors ligne")), 30000);
        QTRY_COMPARE_WITH_TIMEOUT(scalar(*b.app, QStringLiteral("SELECT name FROM Groups WHERE uuid = '%1'").arg(group->uuid())),
                                  QStringLiteral("Atelier renomme"), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(!scalar(*s.app, QStringLiteral(
            "SELECT 1 FROM GroupMembers gm JOIN Groups g ON g.id = gm.group_id JOIN Users u ON u.id = gm.user_id "
            "WHERE g.uuid = '%1' AND u.name = 'chloe'").arg(group->uuid())).isEmpty(), 10000);
        QTRY_COMPARE_WITH_TIMEOUT(scalar(*a.app, QStringLiteral("SELECT COUNT(*) FROM Outbox")), QStringLiteral("0"), 10000);
    }

    // Pendant une panne : un changement de groupe attend le serveur officiel
    // (le secours ne connait pas forcement le groupe), puis est applique a son
    // retour et parvient aux membres.
    void groupChangeDuringOutageWaitsForOfficial()
    {
        m_electionPort = static_cast<quint16>(m_base + 509);
        Poste s = poste(QStringLiteral("w-serveur"), QStringLiteral("SERVER"), 500, -1);
        Poste a = poste(QStringLiteral("w-a"), QStringLiteral("CLIENT"), 510, 10);   // elu secours
        Poste b = poste(QStringLiteral("w-b"), QStringLiteral("CLIENT"), 520, 20);   // proprietaire
        Poste c = poste(QStringLiteral("w-c"), QStringLiteral("CLIENT"), 530, 30);   // membre
        startNetwork(s, {&a, &b, &c}, {QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("chloe")});
        login(a, QStringLiteral("alice"));
        login(b, QStringLiteral("bob"));
        login(c, QStringLiteral("chloe"));
        QTest::qWait(800);

        const int bob = userId(*b.app, QStringLiteral("bob"));
        const auto group = b.app->groupManager()->createGroup(QStringLiteral("Logistique"), bob, {userId(*b.app, QStringLiteral("chloe"))});
        QVERIFY(group.has_value());
        QTRY_VERIFY_WITH_TIMEOUT(!scalar(*c.app, QStringLiteral("SELECT 1 FROM Groups WHERE uuid = '%1'").arg(group->uuid())).isEmpty(), 10000);

        s.app.reset();
        QTRY_COMPARE_WITH_TIMEOUT(a.election()->role(), models::ServerRole::TempServer, 20000);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(a.port) && c.connectedTo(a.port), 30000);

        QVERIFY(b.app->groupManager()->renameGroup(group->id(), QStringLiteral("Logistique et stocks"), bob));
        QTest::qWait(1500);
        // Garde : ni transmis au secours, ni recu par chloe.
        QCOMPARE(scalar(*b.app, QStringLiteral("SELECT COUNT(*) FROM Outbox")), QStringLiteral("1"));
        QCOMPARE(scalar(*c.app, QStringLiteral("SELECT name FROM Groups WHERE uuid = '%1'").arg(group->uuid())), QStringLiteral("Logistique"));

        boot(s);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(s.port) && c.connectedTo(s.port), 30000);
        QTRY_COMPARE_WITH_TIMEOUT(scalar(*c.app, QStringLiteral("SELECT name FROM Groups WHERE uuid = '%1'").arg(group->uuid())),
                                  QStringLiteral("Logistique et stocks"), 15000);
        QTRY_COMPARE_WITH_TIMEOUT(scalar(*b.app, QStringLiteral("SELECT COUNT(*) FROM Outbox")), QStringLiteral("0"), 10000);
    }

    // Pendant une panne, bob lit un message recu avant : son accuse « lu » va au
    // serveur de secours, qui ne connait pas ce message. Il ne doit pas etre perdu :
    // l'expediteur le recoit une fois le serveur officiel revenu.
    void readReceiptDuringOutageReachesSender()
    {
        m_electionPort = static_cast<quint16>(m_base + 609);
        Poste s = poste(QStringLiteral("x-serveur"), QStringLiteral("SERVER"), 600, -1);
        Poste t = poste(QStringLiteral("x-t"), QStringLiteral("CLIENT"), 610, 10);   // elu secours
        Poste a = poste(QStringLiteral("x-a"), QStringLiteral("CLIENT"), 620, 20);
        Poste b = poste(QStringLiteral("x-b"), QStringLiteral("CLIENT"), 630, 30);
        startNetwork(s, {&t, &a, &b}, {QStringLiteral("alice"), QStringLiteral("bob")});
        login(a, QStringLiteral("alice"));
        login(b, QStringLiteral("bob"));
        QTest::qWait(800);

        QVERIFY(send(*a.app, QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("a lire plus tard")).has_value());
        QTRY_COMPARE_WITH_TIMEOUT(status(*a.app, QStringLiteral("a lire plus tard")), models::Message::Delivered, 10000);

        s.app.reset();
        QTRY_COMPARE_WITH_TIMEOUT(t.election()->role(), models::ServerRole::TempServer, 20000);
        QTRY_VERIFY_WITH_TIMEOUT(a.connectedTo(t.port) && b.connectedTo(t.port), 30000);
        QTest::qWait(500);

        const qint64 convB = scalar(*b.app, QStringLiteral("SELECT conversationId FROM Messages WHERE content = 'a lire plus tard'")).toLongLong();
        QVERIFY(b.app->messagingManager()->markConversationAsRead(convB, userId(*b.app, QStringLiteral("bob"))));
        QTest::qWait(1500);

        boot(s);
        QTRY_VERIFY_WITH_TIMEOUT(a.connectedTo(s.port) && b.connectedTo(s.port), 30000);
        QTRY_COMPARE_WITH_TIMEOUT(status(*a.app, QStringLiteral("a lire plus tard")), models::Message::Read, 20000);
    }

    // Un evenement d'audit enregistre hors connexion (connexion de bob pendant
    // que le serveur n'ecoute pas) parvient au journal du serveur a la reconnexion.
    void auditEventRecordedOfflineReachesServer()
    {
        m_electionPort = static_cast<quint16>(m_base + 709);
        Poste s = poste(QStringLiteral("y-serveur"), QStringLiteral("SERVER"), 700, -1);
        Poste b = poste(QStringLiteral("y-b"), QStringLiteral("CLIENT"), 720, 20);
        startNetwork(s, {&b}, {QStringLiteral("bob")});

        s.app->messagingServer()->stop();
        QTRY_VERIFY_WITH_TIMEOUT(!b.connectedTo(s.port), 5000);
        login(b, QStringLiteral("bob"));
        const QString eventUuid = scalar(*b.app, QStringLiteral(
            "SELECT event_uuid FROM AuditLogs WHERE description LIKE '%authentifie : bob%' ORDER BY id DESC LIMIT 1"));
        QVERIFY(!eventUuid.isEmpty());

        QVERIFY(s.app->messagingServer()->start(s.port));
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(s.port), 30000);
        QTRY_VERIFY_WITH_TIMEOUT(!scalar(*s.app, QStringLiteral("SELECT 1 FROM AuditLogs WHERE event_uuid = '%1'").arg(eventUuid)).isEmpty(), 15000);
    }

    // Dossiers partages : un partage ne parvient qu'a la personne concernee ; un
    // partage puis un retrait faits pendant son absence sont rattrapes a son retour.
    void sharedFolderGrantAndRevokeCatchup()
    {
        m_electionPort = static_cast<quint16>(m_base + 809);
        Poste s = poste(QStringLiteral("f-serveur"), QStringLiteral("SERVER"), 800, -1);
        Poste a = poste(QStringLiteral("f-a"), QStringLiteral("CLIENT"), 810, 10);   // alice, proprietaire
        Poste b = poste(QStringLiteral("f-b"), QStringLiteral("CLIENT"), 820, 20);   // bob
        Poste c = poste(QStringLiteral("f-c"), QStringLiteral("CLIENT"), 830, 30);   // chloe, non concernee
        startNetwork(s, {&a, &b, &c}, {QStringLiteral("alice"), QStringLiteral("bob"), QStringLiteral("chloe")});
        login(a, QStringLiteral("alice"));
        login(b, QStringLiteral("bob"));
        login(c, QStringLiteral("chloe"));
        QTest::qWait(800);

        const QString dir1 = m_dir.filePath(QStringLiteral("partage-1"));
        const QString dir2 = m_dir.filePath(QStringLiteral("partage-2"));
        QVERIFY(QDir().mkpath(dir1) && QDir().mkpath(dir2));
        const int alice = userId(*a.app, QStringLiteral("alice"));
        const auto f1 = a.app->sharedFolderManager()->createFolder(QStringLiteral("Budget"), dir1, alice);
        const auto f2 = a.app->sharedFolderManager()->createFolder(QStringLiteral("Archives"), dir2, alice);
        QVERIFY(f1 && f2);
        const auto known = [](Poste &p, const QString &uuid) {
            return p.app->sharedFolderManager()->getFolderByUuid(uuid).has_value();
        };

        // En ligne : bob recoit le partage, chloe non.
        QVERIFY(a.app->sharedFolderManager()->grantAccess(f1->id(), userId(*a.app, QStringLiteral("bob")), alice));
        QTRY_VERIFY_WITH_TIMEOUT(known(b, f1->uuid()), 10000);
        QTest::qWait(1000);
        QVERIFY(!known(c, f1->uuid()));

        // Bob absent : alice lui retire « Budget » et lui partage « Archives ».
        b.app.reset();
        QTest::qWait(500);
        QVERIFY(a.app->sharedFolderManager()->revokeAccess(f1->id(), userId(*a.app, QStringLiteral("bob"))));
        QVERIFY(a.app->sharedFolderManager()->grantAccess(f2->id(), userId(*a.app, QStringLiteral("bob")), alice));
        QTest::qWait(1000);
        QVERIFY(!known(c, f2->uuid()));

        boot(b);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(s.port), 20000);
        login(b, QStringLiteral("bob"));
        QTRY_VERIFY_WITH_TIMEOUT(known(b, f2->uuid()), 15000);   // partage rattrape
        QTRY_VERIFY_WITH_TIMEOUT(!known(b, f1->uuid()), 15000);  // retrait rattrape
        // Chloe, reconnectee aussi, ne recoit toujours rien.
        c.app.reset();
        boot(c);
        QTRY_VERIFY_WITH_TIMEOUT(c.connectedTo(s.port), 20000);
        login(c, QStringLiteral("chloe"));
        QTest::qWait(2000);
        QVERIFY(!known(c, f1->uuid()) && !known(c, f2->uuid()));
    }
};

QTEST_MAIN(TestMessagesE2E)
#include "test_messages_e2e.moc"
