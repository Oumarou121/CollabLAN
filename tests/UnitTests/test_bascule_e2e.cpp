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
    }

private slots:
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
