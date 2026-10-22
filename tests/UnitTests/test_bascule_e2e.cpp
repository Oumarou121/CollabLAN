// Essai de bout en bout de la bascule serveur, avec trois instances completes
// d'Application dans le meme processus (un serveur officiel, deux clients),
// toutes sur le meme port d'election :
//   1. les deux clients trouvent le serveur (battements) et s'y connectent ;
//   2. le serveur s'arrete : le client A (priorite la plus forte) est elu
//      serveur de secours, et le client B se connecte a lui ;
//   3. le serveur officiel redemarre (meme base, meme identite) : il se
//      reconcilie avec A puis reprend la main, et A comme B se reconnectent a
//      lui directement, sans aucune approbation manuelle.
// Seule preparation « administrateur » : le serveur a autorise A et B, et
// chaque client a approuve le certificat du serveur officiel.
// Deux essais de plus pour un poste neuf qui arrive pendant la panne : sans
// autorisation, il attend le retour du serveur officiel pour l'appairage ;
// autorise sur le serveur de secours, il rejoint le serveur officiel a son
// retour sans rien refaire (autorisation reprise a la reconciliation).
#include <QtTest>
#include <QHostAddress>
#include <QRandomGenerator>
#include <QTemporaryDir>

#include "Application.h"
#include "PermissionManager.h"
#include "UserManager.h"
#include "Election/ElectionService.h"
#include "Messaging/MessagingServer.h"
#include "Messaging/MessagingService.h"
#include "Security/SecurityService.h"
#include "models/ServerElection.h"

class TestBasculeE2E : public QObject
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
        // Cycle accelere : battement toutes les 300 ms, panne constatee apres 2 s.
        p.election()->setHeartbeatIntervalMs(300);
        p.election()->setHeartbeatTimeoutMs(2000);
        p.election()->setElectionWindowMs(400);
        p.fingerprint = p.app->securityService()->identity().fingerprintSha256.toLower();
        // Trace par poste (toutes les instances ecrivent dans le meme journal).
        const QString name = p.name;
        network::ElectionService *election = p.election();
        connect(election, &network::ElectionService::roleChanged, election,
                [name, election](models::ServerRole role, models::ServerRole) {
                    qInfo().noquote() << "[" + name + "]" << election->localMachineUuid().left(8)
                                      << "role" << static_cast<int>(role) << "epoch" << election->epoch();
                });
    }

    static int userId(Application &app, const QString &name)
    {
        for (const auto &u : app.userManager()->allUsers())
            if (u.name() == name) return u.id();
        return -1;
    }

    // Poste neuf N qui arrive pendant une panne : S (officiel) et A (client autorise,
    // elu secours) ; N n'a jamais vu S. authorizeOnTemp : A autorise N pendant la panne.
    void newPostDuringOutage(const QString &prefix, quint16 base, bool authorizeOnTemp)
    {
        m_electionPort = static_cast<quint16>(base + 9);
        Poste server{nullptr, prefix + QStringLiteral("-serveur"), QStringLiteral("SERVER"), base, -1, {}};
        Poste a{nullptr, prefix + QStringLiteral("-client-a"), QStringLiteral("CLIENT"), static_cast<quint16>(base + 10), 10, {}};
        Poste n{nullptr, prefix + QStringLiteral("-neuf"), QStringLiteral("CLIENT"), static_cast<quint16>(base + 30), 900, {}};
        boot(server);
        const auto admin = server.app->userManager()->createUser(QStringLiteral("admin"), QStringLiteral("motdepasse"));
        QVERIFY(admin.has_value());
        boot(a);
        QVERIFY(server.app->permissionManager()->authorizeMachineByCertificate(
            a.fingerprint, a.name, a.name.toUpper(), QStringLiteral("127.0.0.1"), admin->id(), QStringLiteral("essai")));
        QVERIFY(a.app->permissionManager()->approveServerCertificate(server.fingerprint, QStringLiteral("127.0.0.1"),
                                                                     QStringLiteral("SERVEUR")));
        QTRY_VERIFY_WITH_TIMEOUT(a.connectedTo(server.port), 20000);
        QTRY_VERIFY_WITH_TIMEOUT(userId(*a.app, QStringLiteral("admin")) > 0, 10000); // comptes recus du serveur

        // Panne : A devient serveur de secours.
        server.app.reset();
        QTRY_COMPARE_WITH_TIMEOUT(a.election()->role(), models::ServerRole::TempServer, 20000);

        // Le poste neuf arrive : il voit le serveur de secours mais ne le connait pas.
        boot(n);
        // Le poste neuf ne doit jamais se promouvoir, a aucun moment de l'essai.
        bool nPromoted = false;
        connect(n.election(), &network::ElectionService::roleChanged, n.election(),
                [&nPromoted](models::ServerRole role, models::ServerRole) {
                    if (role != models::ServerRole::Client) nPromoted = true;
                });
        QTRY_COMPARE_WITH_TIMEOUT(n.app->pendingServerFingerprint().toLower(), a.fingerprint, 20000);
        QVERIFY(!n.connectedTo(a.port));
        // A le note en attente ; les deux affichent le meme code d'appairage.
        QTRY_VERIFY_WITH_TIMEOUT(a.app->permissionManager()->findMachineByCertificateFingerprint(n.fingerprint).has_value(), 10000);
        QCOMPARE(n.app->pendingServerPairingCode(), a.app->pairingCodeWith(n.fingerprint));
        // Le poste isole ne perturbe pas le reseau : A reste le seul serveur de secours.
        QTest::qWait(3000);
        QCOMPARE(a.election()->role(), models::ServerRole::TempServer);
        QVERIFY(a.app->messagingServer()->isRunning());

        if (authorizeOnTemp) {
            // Autorisation donnee sur le serveur de secours (un administrateur s'y connecte).
            QVERIFY(a.app->permissionManager()->authorizeExistingMachineByCertificate(
                n.fingerprint, userId(*a.app, QStringLiteral("admin")), QStringLiteral("pendant la panne")));
            QVERIFY(n.app->approvePendingServerCertificate());
            QTRY_VERIFY_WITH_TIMEOUT(n.connectedTo(a.port), 20000);
        }

        // Retour du serveur officiel : il reprend la main, A se reconnecte a lui.
        boot(server);
        QTRY_COMPARE_WITH_TIMEOUT(a.election()->role(), models::ServerRole::Client, 30000);
        QTRY_VERIFY_WITH_TIMEOUT(a.connectedTo(server.port), 20000);

        if (authorizeOnTemp) {
            // L'autorisation donnee sur le secours est reprise par S pendant la
            // reconciliation, et A a designe S a N : N rejoint S sans rien refaire.
            QTRY_VERIFY_WITH_TIMEOUT(n.connectedTo(server.port), 30000);
            const auto onServer = server.app->permissionManager()->findMachineByCertificateFingerprint(n.fingerprint);
            QVERIFY(onServer.has_value());
            QCOMPARE(onServer->status(), models::MachineStatus::Authorized);
            QVERIFY(onServer->reason().contains(QStringLiteral("serveur de secours")));
            QVERIFY(onServer->reason().contains(QStringLiteral("admin")));
            QVERIFY(n.app->permissionManager()->isTrustedServer(server.fingerprint)); // epingle
            QVERIFY(n.app->pendingServerFingerprint().isEmpty());
            QCOMPARE(n.election()->role(), models::ServerRole::Client);
            QVERIFY(!n.app->messagingServer()->isRunning());
            QVERIFY(!nPromoted);
            return;
        }

        // Le poste neuf, qui n'a jamais vu le serveur officiel, doit encore faire
        // l'appairage avec lui (S ne le connait pas, et il ne connait pas S).
        QTRY_COMPARE_WITH_TIMEOUT(n.app->pendingServerFingerprint().toLower(), server.fingerprint, 30000);
        QVERIFY(!n.connectedTo(server.port));
        QTRY_VERIFY_WITH_TIMEOUT(server.app->permissionManager()->findMachineByCertificateFingerprint(n.fingerprint).has_value(), 10000);
        QCOMPARE(n.app->pendingServerPairingCode(), server.app->pairingCodeWith(n.fingerprint));

        // Appairage : l'administrateur autorise, l'utilisateur approuve -> N rejoint S.
        QVERIFY(server.app->permissionManager()->authorizeExistingMachineByCertificate(
            n.fingerprint, admin->id(), QStringLiteral("codes identiques")));
        QVERIFY(n.app->approvePendingServerCertificate());
        QTRY_VERIFY_WITH_TIMEOUT(n.connectedTo(server.port), 20000);
        QVERIFY(!n.app->messagingServer()->isRunning());
        QVERIFY(!nPromoted);
    }

private slots:
    void newPostDuringOutageJoinsAfterServerReturns()
    {
        newPostDuringOutage(QStringLiteral("a"), static_cast<quint16>(m_base + 100), false);
    }

    void newPostAuthorizedOnTempServerDuringOutage()
    {
        newPostDuringOutage(QStringLiteral("b"), static_cast<quint16>(m_base + 200), true);
    }

    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        m_base = static_cast<quint16>(32000 + QRandomGenerator::global()->bounded(2000) * 10);
        m_electionPort = static_cast<quint16>(m_base + 9);
    }

    void serverDownThenBack()
    {
        Poste server{nullptr, QStringLiteral("serveur"), QStringLiteral("SERVER"), m_base, -1, {}};
        Poste a{nullptr, QStringLiteral("client-a"), QStringLiteral("CLIENT"), static_cast<quint16>(m_base + 10), 10, {}};
        Poste b{nullptr, QStringLiteral("client-b"), QStringLiteral("CLIENT"), static_cast<quint16>(m_base + 20), 500, {}};
        boot(server);

        // Preparation « administrateur ».
        const auto admin = server.app->userManager()->createUser(QStringLiteral("admin"), QStringLiteral("motdepasse"));
        QVERIFY(admin.has_value());
        boot(a);
        boot(b);
        for (Poste *c : {&a, &b}) {
            QVERIFY(server.app->permissionManager()->authorizeMachineByCertificate(
                c->fingerprint, c->name, c->name.toUpper(), QStringLiteral("127.0.0.1"), admin->id(), QStringLiteral("essai")));
            QVERIFY(c->app->permissionManager()->approveServerCertificate(server.fingerprint, QStringLiteral("127.0.0.1"),
                                                                          QStringLiteral("SERVEUR")));
        }

        // 1. Les deux clients se connectent au serveur officiel.
        QTRY_VERIFY_WITH_TIMEOUT(a.connectedTo(server.port), 20000);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(server.port), 20000);
        QTRY_VERIFY_WITH_TIMEOUT(b.app->permissionManager()->isAuthorizedByServer(a.fingerprint), 10000);
        const int epochBefore = server.election()->epoch();

        // 2. Le serveur s'arrete : A est elu serveur de secours, B s'y connecte.
        server.app.reset();
        QTRY_COMPARE_WITH_TIMEOUT(a.election()->role(), models::ServerRole::TempServer, 20000);
        QVERIFY(a.app->messagingServer()->isRunning());
        QTRY_COMPARE_WITH_TIMEOUT(b.election()->role(), models::ServerRole::Client, 20000);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(a.port), 20000);
        QVERIFY(a.election()->epoch() > epochBefore);
        // Un seul serveur de secours : B ne s'est pas promu a son tour.
        QVERIFY(!b.app->messagingServer()->isRunning());
        QCOMPARE(b.election()->activeServerUuid(), a.election()->localMachineUuid());

        // 3. Le serveur officiel revient : reconciliation, reprise de la main,
        //    et retour direct de A et B vers lui.
        boot(server);
        QTRY_COMPARE_WITH_TIMEOUT(a.election()->role(), models::ServerRole::Client, 30000);
        QCOMPARE(server.election()->role(), models::ServerRole::Server);
        QTRY_VERIFY_WITH_TIMEOUT(!a.app->messagingServer()->isRunning(), 10000);
        QTRY_VERIFY_WITH_TIMEOUT(a.connectedTo(server.port), 20000);
        QTRY_VERIFY_WITH_TIMEOUT(b.connectedTo(server.port), 20000);
        QVERIFY(!b.app->messagingServer()->isRunning());
        QCOMPARE(a.election()->activeServerUuid(), server.election()->localMachineUuid());
        QCOMPARE(b.election()->activeServerUuid(), server.election()->localMachineUuid());
    }
};

QTEST_MAIN(TestBasculeE2E)
#include "test_bascule_e2e.moc"
