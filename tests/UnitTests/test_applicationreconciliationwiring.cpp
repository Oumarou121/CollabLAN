#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>
#include <QSignalSpy>

#include "Application.h"
#include "Election/ElectionService.h"
#include "Messaging/MessagingServer.h"
#include "Sync/SyncService.h"
#include "models/ServerElection.h"
#include "PermissionManager.h"
#include "UserManager.h"
#include "Security/SecurityService.h"

/*
 * Verifie le cablage reel entre ElectionService::reconciliationRequired et
 * SyncService::requestReconciliation au sein d'Application::initialize()
 * (issue #4, HYBRID_SERVER_FAILOVER.md section 9, etape 4) : le protocole de
 * fusion lui-meme est deja couvert bout-en-bout par
 * test_syncserviceintegration.cpp ; ce qui manquait encore, c'est la preuve
 * qu'Application declenche bien ce protocole au bon moment, avec les bons
 * parametres (adresse + PORT du TEMP_SERVER), sans intervention manuelle.
 *
 * Sert aussi de garde non-regression pour le bug de port decouvert en
 * ecrivant ce test : le paquet heartbeat/server_promoted ne transmettait pas
 * le port TCP reellement ecoute par le pair, et Application supposait a tort
 * que le pair actif ecoutait sur SON PROPRE messagingServerPort. Les deux
 * Application ci-dessous utilisent donc volontairement des ports de
 * messagerie DIFFERENTS : sans le correctif (ElectionService::messagingPort()/
 * activeServerPort()), la reconnexion vers le TEMP_SERVER se ferait sur le
 * mauvais port et ce test timeout.
 */
class TestApplicationReconciliationWiring : public QObject
{
    Q_OBJECT

private:
    // Depuis la validation TLS des annonces d'election (a0bcd9d), une annonce
    // n'est adoptee qu'apres une connexion TLS reussie : comme sur un vrai
    // reseau, le serveur officiel a autorise le pair, et le pair a approuve le
    // certificat du serveur. Sans cette preparation, le serveur rejetait
    // l'annonce du TEMP_SERVER et la reconciliation n'etait jamais demandee.
    static void trustEachOther(Application &server, Application &peer)
    {
        const auto admin = server.userManager()->createUser(QStringLiteral("admin"), QStringLiteral("motdepasse"));
        QVERIFY(admin.has_value());
        const QString peerFp = peer.securityService()->identity().fingerprintSha256.toLower();
        const QString serverFp = server.securityService()->identity().fingerprintSha256.toLower();
        QVERIFY(server.permissionManager()->authorizeMachineByCertificate(
            peerFp, QStringLiteral("pair"), QStringLiteral("PAIR"), QStringLiteral("127.0.0.1"), admin->id(), QStringLiteral("test")));
        QVERIFY(peer.permissionManager()->approveServerCertificate(serverFp, QStringLiteral("127.0.0.1"), QStringLiteral("SERVEUR")));
    }

    quint16 nextPort()
    {
        return static_cast<quint16>(20000 + (QRandomGenerator::global()->bounded(20000)));
    }

private slots:
    void serverReconnectsToTempServerOnDifferentPortAndReconciles()
    {
        const quint16 electionPort = nextPort();
        const quint16 serverMessagingPort = nextPort();
        const quint16 peerMessagingPort = nextPort(); // volontairement != serverMessagingPort

        QTemporaryDir serverDir;
        QTemporaryDir peerDir;
        QVERIFY(serverDir.isValid());
        QVERIFY(peerDir.isValid());

        // --- Poste "officiel" : demarre Server, epoch 1. ---------------
        Application server;
        // Jamais le port de decouverte reel (45454) : les vrais postes du reseau
        // verraient sinon un poste fantome a chaque essai.
        server.setDiscoveryPort(nextPort());
        server.initialize(serverMessagingPort, serverDir.filePath(QStringLiteral("server.db")),
                           QStringLiteral("SERVER"), -1, electionPort);
        QVERIFY(server.messagingServer()->isRunning());
        QCOMPARE(server.electionService()->role(), models::ServerRole::Server);

        // Le serveur officiel n'emet plus de heartbeat pendant le test : on
        // simule une "absence" (panne reseau ponctuelle, section 7.1) sans
        // pour autant changer son role, afin que le pair ci-dessous parte en
        // election puis se promeuve TEMP_SERVER pendant que le poste
        // officiel croit toujours l'etre.
        server.electionService()->setHeartbeatIntervalMs(3600000);

        // --- Poste "pair" : Client, timeout tres court -> election quasi
        // immediate faute de heartbeat recu du serveur officiel. -----------
        Application peer;
        // Jamais le port de decouverte reel (45454) : les vrais postes du reseau
        // verraient sinon un poste fantome a chaque essai.
        peer.setDiscoveryPort(nextPort());
        peer.initialize(peerMessagingPort, peerDir.filePath(QStringLiteral("peer.db")),
                         QStringLiteral("CLIENT"), -1, electionPort);
        trustEachOther(server, peer);
        peer.electionService()->setHeartbeatTimeoutMs(300);
        peer.electionService()->setElectionWindowMs(150);

        QTRY_VERIFY_WITH_TIMEOUT(peer.messagingServer()->isRunning(), 5000);
        QCOMPARE(peer.electionService()->role(), models::ServerRole::TempServer);

        // Le pair emet vite son propre heartbeat (TEMP_SERVER) : le poste
        // officiel, toujours role Server, va le recevoir et constater qu'un
        // autre serveur emet en son nom -> reconciliationRequired.
        QSignalSpy reconciliationRequiredSpy(server.electionService(),
                                              &network::ElectionService::reconciliationRequired);
        QVERIFY(reconciliationRequiredSpy.wait(5000));

        // Preuve du fix de port : l'adresse/port memorises cote serveur
        // officiel pour le pair actif correspondent bien au port du PAIR,
        // pas au sien.
        QCOMPARE(server.electionService()->activeServerPort(), peerMessagingPort);
        QVERIFY(server.electionService()->activeServerPort() != serverMessagingPort);

        // --- Assertion finale : Application a bien enchaine tout seul ---
        // connexion -> requestReconciliation -> reconciliationCompleted,
        // sans aucune intervention manuelle du test au-dela du signal
        // reconciliationRequired ci-dessus.
        QSignalSpy reconciliationCompletedSpy(server.syncService(),
                                               &network::SyncService::reconciliationCompleted);
        QVERIFY(reconciliationCompletedSpy.wait(5000));

        // Une fois la reconciliation confirmee, le serveur officiel reprend
        // la main (epoch+1, server_promoted non-temporaire, section 7.3) et
        // le pair redevient Client.
        QTRY_COMPARE_WITH_TIMEOUT(server.electionService()->role(), models::ServerRole::Server, 5000);
        QTRY_COMPARE_WITH_TIMEOUT(peer.electionService()->role(), models::ServerRole::Client, 5000);
        QTRY_VERIFY_WITH_TIMEOUT(!peer.messagingServer()->isRunning(), 5000);
    }

    void officialServerReclaimsFromOlderTempServerEpoch()
    {
        const quint16 electionPort = nextPort();
        const quint16 serverMessagingPort = nextPort();
        const quint16 peerMessagingPort = nextPort();

        QTemporaryDir serverDir;
        QTemporaryDir peerDir;
        QVERIFY(serverDir.isValid());
        QVERIFY(peerDir.isValid());

        // Simule le redemarrage d'un serveur officiel dont l'epoch persiste
        // est deja plus eleve que celui du client qui sera promu temporaire.
        // C'est le cas qui etait bloque par le filtrage remoteEpoch < m_epoch.
        Application server;
        // Jamais le port de decouverte reel (45454) : les vrais postes du reseau
        // verraient sinon un poste fantome a chaque essai.
        server.setDiscoveryPort(nextPort());
        server.initialize(serverMessagingPort, serverDir.filePath(QStringLiteral("server.db")),
                          QStringLiteral("SERVER"), -1, electionPort);
        server.electionService()->setInitialState(models::ServerRole::Server, 10);
        server.electionService()->setHeartbeatIntervalMs(3600000);

        QSignalSpy reconciliationRequiredSpy(server.electionService(),
                                              &network::ElectionService::reconciliationRequired);
        QSignalSpy reconciliationCompletedSpy(server.syncService(),
                                               &network::SyncService::reconciliationCompleted);

        Application peer;
        // Jamais le port de decouverte reel (45454) : les vrais postes du reseau
        // verraient sinon un poste fantome a chaque essai.
        peer.setDiscoveryPort(nextPort());
        peer.initialize(peerMessagingPort, peerDir.filePath(QStringLiteral("peer.db")),
                        QStringLiteral("CLIENT"), -1, electionPort);
        trustEachOther(server, peer);
        peer.electionService()->setHeartbeatTimeoutMs(300);
        peer.electionService()->setElectionWindowMs(150);

        QTRY_COMPARE_WITH_TIMEOUT(peer.electionService()->role(), models::ServerRole::TempServer, 5000);
        QCOMPARE(peer.electionService()->epoch(), 1);

        if (reconciliationRequiredSpy.isEmpty())
            QVERIFY(reconciliationRequiredSpy.wait(5000));
        if (reconciliationCompletedSpy.isEmpty())
            QVERIFY(reconciliationCompletedSpy.wait(5000));

        // Le reclaim doit prendre un epoch strictement superieur aux deux
        // valeurs, et forcer le TEMP_SERVER a revenir Client.
        QTRY_VERIFY_WITH_TIMEOUT(server.electionService()->epoch() > 10, 5000);
        QTRY_COMPARE_WITH_TIMEOUT(peer.electionService()->role(), models::ServerRole::Client, 5000);
        QTRY_VERIFY_WITH_TIMEOUT(!peer.messagingServer()->isRunning(), 5000);
    }
};

QTEST_MAIN(TestApplicationReconciliationWiring)
#include "test_applicationreconciliationwiring.moc"
