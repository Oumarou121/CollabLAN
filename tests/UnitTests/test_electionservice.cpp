#include <QtTest>
#include <QSignalSpy>

#include "Election/ElectionService.h"
#include "models/ServerElection.h"

using network::ElectionService;
using models::ServerRole;

/*
 * Verifie les criteres d'acceptation de HYBRID_SERVER_FAILOVER.md (sections 4 a 8) :
 *  - un Server emet un heartbeat regulier,
 *  - la perte du heartbeat declenche une election en < 20 s,
 *  - le gagnant (priority_weight le plus bas) devient TempServer et incremente l'epoch,
 *  - les autres postes basculent leur activeServerUuid() vers le nouveau TempServer,
 *  - la regle anti split-brain ignore tout server_promoted avec un epoch perime.
 */
class TestElectionService : public QObject
{
    Q_OBJECT

private slots:
    void serverEmitsHeartbeatAndClientTracksIt()
    {
        ElectionService server;
        ElectionService client;

        const quint16 testPort = 46999;
        server.setPort(testPort);
        client.setPort(testPort);

        server.setHeartbeatIntervalMs(200);
        server.setInitialState(ServerRole::Server, 1);

        QVERIFY(server.start());
        QVERIFY(client.start());

        // Le client ne doit rien declencher tant que le heartbeat arrive.
        QTest::qWait(600);

        QCOMPARE(client.role(), ServerRole::Client);
        QCOMPARE(client.activeServerUuid(), server.localMachineUuid());
        QCOMPARE(client.epoch(), 1);

        server.stop();
        client.stop();
    }

    void clientIsPromotedToTempServerAfterHeartbeatLoss()
    {
        ElectionService serverGoneMissing;
        ElectionService client;

        const quint16 testPort = 47000;
        serverGoneMissing.setPort(testPort);
        client.setPort(testPort);

        serverGoneMissing.setHeartbeatIntervalMs(150);
        serverGoneMissing.setInitialState(ServerRole::Server, 1);

        client.setHeartbeatTimeoutMs(500);
        client.setElectionWindowMs(200);
        client.setPriorityWeight(10);

        QSignalSpy heartbeatLostSpy(&client, &ElectionService::heartbeatLost);
        QSignalSpy promotedSpy(&client, &ElectionService::serverPromoted);
        QSignalSpy roleChangedSpy(&client, &ElectionService::roleChanged);

        QVERIFY(serverGoneMissing.start());
        QVERIFY(client.start());

        // Laisse le client voir au moins un heartbeat, puis on "tue" le serveur.
        QTest::qWait(300);
        serverGoneMissing.stop();

        QVERIFY(heartbeatLostSpy.wait(2000));
        QVERIFY(promotedSpy.wait(2000));

        QCOMPARE(client.role(), ServerRole::TempServer);
        QCOMPARE(client.epoch(), 2); // incremente depuis l'epoch 1 connu du serveur
        QVERIFY(roleChangedSpy.count() >= 1);

        client.stop();
    }

    void lowerPriorityWeightWinsElection()
    {
        ElectionService serverGoneMissing;
        ElectionService candidateHighPriority;   // priority_weight bas => plus prioritaire
        ElectionService candidateLowPriority;

        const quint16 testPort = 47001;
        serverGoneMissing.setPort(testPort);
        candidateHighPriority.setPort(testPort);
        candidateLowPriority.setPort(testPort);

        serverGoneMissing.setHeartbeatIntervalMs(150);
        serverGoneMissing.setInitialState(ServerRole::Server, 5);

        for (ElectionService *svc : {&candidateHighPriority, &candidateLowPriority}) {
            svc->setHeartbeatTimeoutMs(500);
            svc->setElectionWindowMs(300);
        }
        candidateHighPriority.setPriorityWeight(1);   // doit gagner
        candidateLowPriority.setPriorityWeight(50);

        QSignalSpy promotedOnWinner(&candidateHighPriority, &ElectionService::serverPromoted);
        QSignalSpy promotedOnLoser(&candidateLowPriority, &ElectionService::serverPromoted);

        QVERIFY(serverGoneMissing.start());
        QVERIFY(candidateHighPriority.start());
        QVERIFY(candidateLowPriority.start());

        QTest::qWait(300);
        serverGoneMissing.stop();

        QVERIFY(promotedOnWinner.wait(2000));
        QVERIFY(promotedOnLoser.wait(2000));

        QCOMPARE(candidateHighPriority.role(), ServerRole::TempServer);
        QCOMPARE(candidateLowPriority.role(), ServerRole::Client);
        QCOMPARE(candidateLowPriority.activeServerUuid(), candidateHighPriority.localMachineUuid());
        QCOMPARE(candidateHighPriority.epoch(), candidateLowPriority.epoch());

        candidateHighPriority.stop();
        candidateLowPriority.stop();
    }

    void staleServerPromotedIsIgnoredAntiSplitBrain()
    {
        ElectionService service;
        service.setPort(47002);
        service.setInitialState(ServerRole::Client, 10);

        QSignalSpy ignoredSpy(&service, &ElectionService::splitBrainAttemptIgnored);
        QVERIFY(service.start());

        // Simule la reception (via handlePacket indirectement impossible depuis
        // le test sans exposer la methode) d'un epoch perime en passant par un
        // second service qui tente de se promouvoir avec un epoch trop bas :
        // on verifie plutot le comportement observable equivalent via
        // reclaimAsOfficialServer() sur un epoch deja depasse localement.
        ElectionService stalePromoter;
        stalePromoter.setPort(47002);
        stalePromoter.setInitialState(ServerRole::Server, 1); // epoch < 10 : perime
        QVERIFY(stalePromoter.start());
        stalePromoter.reclaimAsOfficialServer(); // tente epoch 2, toujours < 10

        QVERIFY(ignoredSpy.wait(2000));
        QCOMPARE(service.epoch(), 10); // inchange
        QCOMPARE(service.role(), ServerRole::Client);

        service.stop();
        stalePromoter.stop();
    }
};

QTEST_GUILESS_MAIN(TestElectionService)
#include "test_electionservice.moc"
