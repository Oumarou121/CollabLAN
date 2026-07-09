#include <QtTest>
#include <QSignalSpy>
#include "Discovery/DiscoveryService.h"

using network::DiscoveryService;
using network::DiscoveredPeer;

/*
 * Verifie le critere d'acceptation de l'issue #9 :
 * "Deux instances de l'app sur le meme reseau se detectent en moins de 5 secondes".
 *
 * Ici les deux instances tournent dans le meme process de test, mais
 * communiquent bien via de vrais sockets UDP loopback/broadcast, ce qui
 * exerce le vrai chemin reseau (envoi + ecoute + parsing du paquet).
 */
class TestDiscoveryService : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        qRegisterMetaType<network::DiscoveredPeer>("network::DiscoveredPeer");
    }

    void twoInstancesDiscoverEachOtherWithinFiveSeconds()
    {
        DiscoveryService serviceA;
        DiscoveryService serviceB;

        // Port dedie au test pour ne pas interferer avec une instance
        // reelle de l'application qui tournerait sur la machine de CI.
        const quint16 testPort = 45999;
        serviceA.setPort(testPort);
        serviceB.setPort(testPort);

        // Annonce rapide pour ne pas attendre inutilement pendant le test.
        serviceA.setAnnounceIntervalMs(300);
        serviceB.setAnnounceIntervalMs(300);

        serviceA.setLocalName("MachineA");
        serviceB.setLocalName("MachineB");

        QSignalSpy discoveredByA(&serviceA, &DiscoveryService::peerDiscovered);
        QSignalSpy discoveredByB(&serviceB, &DiscoveryService::peerDiscovered);

        QVERIFY(serviceA.start());
        QVERIFY(serviceB.start());

        // Les deux services doivent chacun decouvrir l'autre en moins de 5s.
        QVERIFY(discoveredByA.wait(5000));
        QVERIFY(discoveredByB.wait(5000));

        QCOMPARE(serviceA.peers().size(), 1);
        QCOMPARE(serviceB.peers().size(), 1);

        QCOMPARE(serviceA.peers().first().id, serviceB.localId());
        QCOMPARE(serviceB.peers().first().id, serviceA.localId());
        QCOMPARE(serviceA.peers().first().name, QStringLiteral("MachineB"));
        QCOMPARE(serviceB.peers().first().name, QStringLiteral("MachineA"));

        serviceA.stop();
        serviceB.stop();
    }

    void peerIsMarkedLostAfterTimeout()
    {
        DiscoveryService serviceA;
        DiscoveryService serviceB;

        const quint16 testPort = 46000;
        serviceA.setPort(testPort);
        serviceB.setPort(testPort);

        serviceA.setAnnounceIntervalMs(200);
        serviceB.setAnnounceIntervalMs(200);
        serviceA.setPeerTimeoutMs(600);
        serviceB.setPeerTimeoutMs(600);

        QSignalSpy discoveredByA(&serviceA, &DiscoveryService::peerDiscovered);
        QSignalSpy lostByA(&serviceA, &DiscoveryService::peerLost);

        QVERIFY(serviceA.start());
        QVERIFY(serviceB.start());

        QVERIFY(discoveredByA.wait(5000));
        QCOMPARE(serviceA.peers().size(), 1);

        // On arrete B : A ne doit plus recevoir d'annonces et finir par
        // considerer B comme perdu une fois peerTimeoutMs() ecoule.
        serviceB.stop();

        QVERIFY(lostByA.wait(5000));
        QCOMPARE(serviceA.peers().size(), 0);

        serviceA.stop();
    }
};

QTEST_MAIN(TestDiscoveryService)
#include "test_discoveryservice.moc"
