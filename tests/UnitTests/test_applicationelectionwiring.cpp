#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "Application.h"
#include "Election/ElectionService.h"
#include "Messaging/MessagingServer.h"
#include "models/ServerElection.h"

/*
 * Verifie le cablage reel (pas seulement ElectionService en isolation,
 * deja couvert par test_electionservice.cpp) entre ElectionService et
 * MessagingServer au sein d'Application::initialize() : c'est l'etape 3
 * du plan de mise en oeuvre de HYBRID_SERVER_FAILOVER.md, section 9.
 *
 *  - Server/TempServer -> MessagingServer doit ecouter.
 *  - Client             -> MessagingServer doit rester silencieux.
 *  - Une transition de role (perte de heartbeat -> election -> promotion,
 *    ou reprise de main par le serveur officiel) doit demarrer/arreter
 *    MessagingServer en consequence, via le slot connecte a
 *    ElectionService::roleChanged dans Application.cpp.
 */
class TestApplicationElectionWiring : public QObject
{
    Q_OBJECT

private:
    // Chaque test utilise un port ElectionService et un port MessagingServer
    // distincts (et une base SQLite dans un repertoire temporaire propre)
    // pour ne pas interferer avec les autres tests ni entre eux si executes
    // en parallele par ctest.
    quint16 nextPort()
    {
        return static_cast<quint16>(20000 + (QRandomGenerator::global()->bounded(20000)));
    }

private slots:
    void initializeAsServerStartsMessagingServerImmediately()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        Application app;
        app.initialize(nextPort(), dir.filePath(QStringLiteral("test.db")),
                        QStringLiteral("SERVER"), -1, nextPort());

        QVERIFY(app.messagingServer() != nullptr);
        QVERIFY(app.messagingServer()->isRunning());
        QCOMPARE(app.electionService()->role(), models::ServerRole::Server);
    }

    void initializeAsClientDoesNotStartMessagingServer()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        Application app;
        app.initialize(nextPort(), dir.filePath(QStringLiteral("test.db")),
                        QStringLiteral("CLIENT"), -1, nextPort());

        QVERIFY(app.messagingServer() != nullptr);
        QVERIFY(!app.messagingServer()->isRunning());
        QCOMPARE(app.electionService()->role(), models::ServerRole::Client);
    }

    void clientPromotedToTempServerAfterHeartbeatLossStartsMessagingServer()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        Application app;
        app.initialize(nextPort(), dir.filePath(QStringLiteral("test.db")),
                        QStringLiteral("CLIENT"), -1, nextPort());

        QVERIFY(!app.messagingServer()->isRunning());

        // Accelere le cycle heartbeat/election : ce poste, seul sur ce port,
        // n'a jamais vu de heartbeat et va donc detecter une "panne" tres
        // rapidement puis remporter l'election (seul candidat).
        network::ElectionService *election = app.electionService();
        QVERIFY(election != nullptr);
        election->setHeartbeatTimeoutMs(300);
        election->setElectionWindowMs(150);

        QTRY_VERIFY_WITH_TIMEOUT(app.messagingServer()->isRunning(), 5000);
        QCOMPARE(election->role(), models::ServerRole::TempServer);
    }

    void officialServerReclaimStopsMessagingServerOnTempServer()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const quint16 electionPort = nextPort();

        // --- Le poste sous test : promu TempServer suite a une panne. ---
        Application app;
        app.initialize(nextPort(), dir.filePath(QStringLiteral("test.db")),
                        QStringLiteral("CLIENT"), -1, electionPort);

        network::ElectionService *election = app.electionService();
        QVERIFY(election != nullptr);
        election->setHeartbeatTimeoutMs(300);
        election->setElectionWindowMs(150);

        QTRY_VERIFY_WITH_TIMEOUT(app.messagingServer()->isRunning(), 5000);
        QCOMPARE(election->role(), models::ServerRole::TempServer);

        // --- Le "vrai" serveur officiel revient avec un epoch superieur ---
        // (simule ici par un ElectionService nu, comme dans
        // test_electionservice.cpp, plutot qu'une seconde Application
        // complete : seul le comportement d'Application sous test nous
        // interesse ici).
        network::ElectionService official;
        official.setPort(electionPort);
        official.setInitialState(models::ServerRole::Server, election->epoch() + 100);
        QVERIFY(official.start());
        official.reclaimAsOfficialServer();

        QTRY_VERIFY_WITH_TIMEOUT(!app.messagingServer()->isRunning(), 5000);
        QCOMPARE(election->role(), models::ServerRole::Client);

        official.stop();
    }
};

QTEST_MAIN(TestApplicationElectionWiring)
#include "test_applicationelectionwiring.moc"
