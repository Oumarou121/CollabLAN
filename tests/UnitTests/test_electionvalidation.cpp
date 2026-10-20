#include <QtTest>
#include <QSignalSpy>
#include <QUdpSocket>
#include <QJsonDocument>
#include <QJsonObject>

#include "Election/ElectionService.h"
#include "models/ServerElection.h"

using network::ElectionService;
using models::ServerRole;

namespace {

// Diffuse un paquet d'election brut, comme le ferait n'importe quelle machine
// du reseau : c'est exactement le pouvoir dont dispose un attaquant, puisque
// ces datagrammes ne sont ni signes ni authentifies.
void broadcastRawPromotion(quint16 port, const QString &machineUuid, int epoch, quint16 messagingPort)
{
    QJsonObject packet;
    packet["type"] = QStringLiteral("localink.election");
    packet["version"] = 1;
    packet["msg"] = QStringLiteral("server_promoted");
    packet["epoch"] = epoch;
    packet["machine_uuid"] = machineUuid;
    packet["temporary"] = true;
    packet["messaging_port"] = messagingPort;

    QUdpSocket socket;
    const QByteArray data = QJsonDocument(packet).toJson(QJsonDocument::Compact);
    socket.writeDatagram(data, QHostAddress::LocalHost, port);
    socket.writeDatagram(data, QHostAddress::Broadcast, port);
}

} // namespace

/*
 * Authentification du resultat d'election (ElectionService::setRequireValidatedServer).
 *
 * Les paquets UDP d'election ne sont ni signes ni authentifies : avant ce
 * mecanisme, un seul datagramme server_promoted portant un epoch arbitrairement
 * grand suffisait a faire adopter n'importe quelle machine comme serveur par
 * tous les postes du reseau. Plutot que de signer les datagrammes, on valide le
 * RESULTAT : l'annonce n'est qu'une indication, et rien n'est applique tant que
 * l'appelant (Application, via une connexion TLS dont le certificat est
 * verifie) n'a pas appele confirmPendingServer().
 */
class TestElectionValidation : public QObject
{
    Q_OBJECT

private slots:
    void announcedServerIsNotAdoptedBeforeValidation()
    {
        ElectionService server;
        ElectionService client;

        const quint16 testPort = 47310;
        server.setPort(testPort);
        client.setPort(testPort);

        server.setHeartbeatIntervalMs(150);
        server.setInitialState(ServerRole::Server, 3);
        client.setRequireValidatedServer(true);
        // Assez long pour qu aucune election ne vienne brouiller la mesure.
        client.setHeartbeatTimeoutMs(60000);

        QSignalSpy pending(&client, &ElectionService::serverEndpointPending);

        QVERIFY(server.start());
        QVERIFY(client.start());

        QVERIFY(pending.wait(3000));

        // L etat local reste strictement inchange tant que la validation n a
        // pas eu lieu : ni epoch adopte, ni serveur actif.
        QCOMPARE(client.activeServerUuid(), QString());
        QCOMPARE(client.epoch(), 0);
        QCOMPARE(client.pendingServerUuid(), server.localMachineUuid());

        // Les heartbeats suivants (toutes les 150 ms) ne doivent pas redemander
        // une validation a chaque battement tant que celle-ci est en cours.
        const int afterFirst = pending.count();
        QTest::qWait(600);
        QCOMPARE(pending.count(), afterFirst);

        server.stop();
        client.stop();
    }

    void confirmingValidationAdoptsTheAnnouncedServer()
    {
        ElectionService server;
        ElectionService client;

        const quint16 testPort = 47311;
        server.setPort(testPort);
        client.setPort(testPort);

        server.setHeartbeatIntervalMs(150);
        server.setMessagingPort(23490);
        server.setInitialState(ServerRole::Server, 5);
        client.setRequireValidatedServer(true);
        client.setHeartbeatTimeoutMs(60000);

        QSignalSpy pending(&client, &ElectionService::serverEndpointPending);

        QVERIFY(server.start());
        QVERIFY(client.start());
        QVERIFY(pending.wait(3000));

        client.confirmPendingServer(server.localMachineUuid());

        QCOMPARE(client.activeServerUuid(), server.localMachineUuid());
        QCOMPARE(client.epoch(), 5);
        QCOMPARE(client.activeServerPort(), quint16(23490));
        QCOMPARE(client.pendingServerUuid(), QString());

        // Une fois valide, le meme serveur ne redemande plus de validation :
        // ses heartbeats sont pris en compte directement.
        const int afterConfirm = pending.count();
        QTest::qWait(600);
        QCOMPARE(pending.count(), afterConfirm);

        server.stop();
        client.stop();
    }

    void rejectedValidationLeavesStateUnchangedAndStillAllowsElection()
    {
        ElectionService server;
        ElectionService client;

        const quint16 testPort = 47312;
        server.setPort(testPort);
        client.setPort(testPort);

        server.setHeartbeatIntervalMs(150);
        server.setInitialState(ServerRole::Server, 7);
        client.setRequireValidatedServer(true);
        client.setHeartbeatTimeoutMs(800);
        client.setElectionWindowMs(200);

        QSignalSpy pending(&client, &ElectionService::serverEndpointPending);
        QSignalSpy rejected(&client, &ElectionService::serverEndpointRejected);

        QVERIFY(server.start());
        QVERIFY(client.start());
        QVERIFY(pending.wait(3000));

        client.rejectPendingServer(server.localMachineUuid(), QStringLiteral("certificat inconnu"));

        QCOMPARE(rejected.count(), 1);
        QCOMPARE(client.activeServerUuid(), QString());
        QCOMPARE(client.epoch(), 0);

        // Un rejet ne doit pas laisser le poste suspendu : faute de serveur
        // valide, le delai de heartbeat finit par declencher une election, que
        // ce poste (seul candidat valide) gagne.
        QVERIFY(QTest::qWaitFor([&]() { return client.role() == ServerRole::TempServer; }, 5000));

        server.stop();
        client.stop();
    }

    void forgedPromotionCannotHijackAnAlreadyValidatedServer()
    {
        ElectionService server;
        ElectionService client;

        const quint16 testPort = 47313;
        server.setPort(testPort);
        client.setPort(testPort);

        server.setHeartbeatIntervalMs(150);
        server.setMessagingPort(23491);
        server.setInitialState(ServerRole::Server, 2);
        client.setRequireValidatedServer(true);
        client.setHeartbeatTimeoutMs(60000);

        QSignalSpy pending(&client, &ElectionService::serverEndpointPending);

        QVERIFY(server.start());
        QVERIFY(client.start());
        QVERIFY(pending.wait(3000));
        client.confirmPendingServer(server.localMachineUuid());
        QCOMPARE(client.activeServerUuid(), server.localMachineUuid());

        // Attaque : un poste quelconque diffuse un server_promoted avec un epoch
        // enorme. Avant la validation du resultat, cela suffisait a detourner
        // tous les clients vers lui.
        const QString attacker = QStringLiteral("00000000-dead-beef-0000-000000000001");
        broadcastRawPromotion(testPort, attacker, 9999, 31337);

        QVERIFY(QTest::qWaitFor([&]() { return client.pendingServerUuid() == attacker; }, 3000));

        // Rien n a bouge : le serveur actif reste celui qui a ete valide.
        QCOMPARE(client.activeServerUuid(), server.localMachineUuid());
        QCOMPARE(client.activeServerPort(), quint16(23490 + 1));
        QCOMPARE(client.epoch(), 2);
        QCOMPARE(client.role(), ServerRole::Client);

        // Et le rejet de la validation ne change rien non plus.
        client.rejectPendingServer(attacker, QStringLiteral("certificat inconnu"));
        QCOMPARE(client.activeServerUuid(), server.localMachineUuid());
        QCOMPARE(client.epoch(), 2);

        server.stop();
        client.stop();
    }
};

QTEST_MAIN(TestElectionValidation)
#include "test_electionvalidation.moc"
