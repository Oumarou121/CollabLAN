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
        app.setDiscoveryPort(nextPort());   // jamais 45454 : postes fantomes sur le reseau
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
        app.setDiscoveryPort(nextPort());   // jamais 45454 : postes fantomes sur le reseau
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
        app.setDiscoveryPort(nextPort());   // jamais 45454 : postes fantomes sur le reseau
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
        app.setDiscoveryPort(nextPort());   // jamais 45454 : postes fantomes sur le reseau
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
        // Port de messagerie annonce non nul : sans lui, Application rejette
        // l'annonce immediatement ("adresse ou port inconnu") et la validation
        // simulee plus bas n'aurait aucune chance de s'exercer.
        official.setMessagingPort(nextPort());
        official.setInitialState(models::ServerRole::Server, election->epoch() + 100);
        QVERIFY(official.start());

        // Depuis l'authentification du resultat d'election (Application appelle
        // ElectionService::setRequireValidatedServer(true)), une annonce UDP ne
        // suffit plus : elle n'est appliquee qu'une fois le poste annonce joint
        // en TLS avec un certificat reconnu. Ce test porte sur le pilotage de
        // MessagingServer, pas sur la couche TLS : on simule donc ici la
        // validation reussie. Le refus de valider est couvert par le test
        // suivant, et le mecanisme lui-meme par test_electionvalidation.
        QObject::connect(election, &network::ElectionService::serverEndpointPending, &app,
                          [election](const QString &machineUuid, const QHostAddress &, quint16) {
                              election->confirmPendingServer(machineUuid);
                          });

        official.reclaimAsOfficialServer();

        QTRY_VERIFY_WITH_TIMEOUT(!app.messagingServer()->isRunning(), 5000);
        QCOMPARE(election->role(), models::ServerRole::Client);

        official.stop();
    }

    // Revers de la medaille du test precedent, et raison d'etre du mecanisme :
    // sans validation, l'annonce d'un poste quelconque ne doit RIEN changer.
    // Avant cela, un simple datagramme portant un epoch plus grand suffisait a
    // faire ceder le serveur en place a n'importe quelle machine du reseau.
    void unvalidatedServerAnnouncementDoesNotStopMessagingServer()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const quint16 electionPort = nextPort();

        Application app;
        app.setDiscoveryPort(nextPort());   // jamais 45454 : postes fantomes sur le reseau
        app.initialize(nextPort(), dir.filePath(QStringLiteral("test.db")),
                        QStringLiteral("CLIENT"), -1, electionPort);

        network::ElectionService *election = app.electionService();
        QVERIFY(election != nullptr);
        election->setHeartbeatTimeoutMs(300);
        election->setElectionWindowMs(150);

        QTRY_VERIFY_WITH_TIMEOUT(app.messagingServer()->isRunning(), 5000);
        QCOMPARE(election->role(), models::ServerRole::TempServer);

        // Ce poste annonce un epoch bien superieur mais n'expose aucun service
        // de messagerie TLS : la validation ne peut pas aboutir.
        network::ElectionService intruder;
        intruder.setPort(electionPort);
        intruder.setInitialState(models::ServerRole::Server, election->epoch() + 100);
        QVERIFY(intruder.start());
        intruder.reclaimAsOfficialServer();

        QSignalSpy pending(election, &network::ElectionService::serverEndpointPending);
        QVERIFY(pending.wait(5000));

        // L'annonce reste en attente : le role et MessagingServer ne bougent pas.
        QTest::qWait(1000);
        QVERIFY(app.messagingServer()->isRunning());
        QCOMPARE(election->role(), models::ServerRole::TempServer);

        intruder.stop();
    }
};

QTEST_MAIN(TestApplicationElectionWiring)
#include "test_applicationelectionwiring.moc"
