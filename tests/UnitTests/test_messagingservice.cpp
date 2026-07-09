#include <QtTest>
#include <QSignalSpy>
#include <QWebSocketServer>
#include <QWebSocket>
#include "Messaging/MessagingService.h"

using network::MessagingService;

/*
 * Verifie le critere d'acceptation de l'issue #43 :
 * "Un message envoye par PC-A est recu par PC-B en moins d'une seconde".
 *
 * Ce test utilise un QWebSocketServer local pour simuler PC-B et
 * MessagingService pour simuler PC-A, permettant de tester le chemin
 * complet de connexion, envoi et reception de messages WebSocket.
 */
class TestMessagingService : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        // Initialisation Qt WebSockets
    }

    void connectToHostSucceeds()
    {
        QWebSocketServer server(QStringLiteral("TestServer"), QWebSocketServer::NonSecureMode);
        QVERIFY(server.listen(QHostAddress::LocalHost, 12345));

        MessagingService client;
        QSignalSpy connectedSpy(&client, &MessagingService::connected);
        QSignalSpy errorSpy(&client, &MessagingService::error);

        QVERIFY(client.connectToHost(QHostAddress::LocalHost, 12345));
        QVERIFY(connectedSpy.wait(5000));
        QCOMPARE(errorSpy.count(), 0);
        QVERIFY(client.isConnected());

        client.disconnectFromHost();
        server.close();
    }

    void sendMessageDeliveredToServer()
    {
        QWebSocketServer server(QStringLiteral("TestServer"), QWebSocketServer::NonSecureMode);
        QVERIFY(server.listen(QHostAddress::LocalHost, 12346));

        QWebSocket *serverSocket = nullptr;
        QObject::connect(&server, &QWebSocketServer::newConnection, [&]() {
            serverSocket = server.nextPendingConnection();
        });

        MessagingService client;
        QSignalSpy connectedSpy(&client, &MessagingService::connected);

        QVERIFY(client.connectToHost(QHostAddress::LocalHost, 12346));
        QVERIFY(connectedSpy.wait(5000));
        QVERIFY(serverSocket != nullptr);

        QSignalSpy messageReceivedSpy(serverSocket, &QWebSocket::textMessageReceived);

        const QString testMessage = QStringLiteral("Hello from client");
        QVERIFY(client.sendMessage(testMessage));
        QVERIFY(messageReceivedSpy.wait(1000));

        QCOMPARE(messageReceivedSpy.count(), 1);
        QCOMPARE(messageReceivedSpy.first().at(0).toString(), testMessage);

        client.disconnectFromHost();
        server.close();
    }

    void messageReceivedFromServer()
    {
        QWebSocketServer server(QStringLiteral("TestServer"), QWebSocketServer::NonSecureMode);
        QVERIFY(server.listen(QHostAddress::LocalHost, 12347));

        QWebSocket *serverSocket = nullptr;
        QObject::connect(&server, &QWebSocketServer::newConnection, [&]() {
            serverSocket = server.nextPendingConnection();
        });

        MessagingService client;
        QSignalSpy connectedSpy(&client, &MessagingService::connected);
        QSignalSpy messageReceivedSpy(&client, &MessagingService::messageReceived);

        QVERIFY(client.connectToHost(QHostAddress::LocalHost, 12347));
        QVERIFY(connectedSpy.wait(5000));
        QVERIFY(serverSocket != nullptr);

        const QString testMessage = QStringLiteral("Hello from server");
        serverSocket->sendTextMessage(testMessage);

        QVERIFY(messageReceivedSpy.wait(1000));
        QCOMPARE(messageReceivedSpy.count(), 1);
        QCOMPARE(messageReceivedSpy.first().at(0).toString(), testMessage);

        client.disconnectFromHost();
        server.close();
    }

    void messageRoundTripUnderOneSecond()
    {
        QWebSocketServer server(QStringLiteral("TestServer"), QWebSocketServer::NonSecureMode);
        QVERIFY(server.listen(QHostAddress::LocalHost, 12348));

        QWebSocket *serverSocket = nullptr;
        QObject::connect(&server, &QWebSocketServer::newConnection, [&]() {
            serverSocket = server.nextPendingConnection();
        });

        MessagingService client;
        QSignalSpy connectedSpy(&client, &MessagingService::connected);
        QSignalSpy messageReceivedSpy(&client, &MessagingService::messageReceived);

        QVERIFY(client.connectToHost(QHostAddress::LocalHost, 12348));
        QVERIFY(connectedSpy.wait(5000));
        QVERIFY(serverSocket != nullptr);

        QSignalSpy serverMessageSpy(serverSocket, &QWebSocket::textMessageReceived);

        const QString testMessage = QStringLiteral("Test message");
        QElapsedTimer timer;
        timer.start();

        // Client -> Server
        QVERIFY(client.sendMessage(testMessage));
        QVERIFY(serverMessageSpy.wait(1000));

        // Server -> Client (echo)
        serverSocket->sendTextMessage(testMessage);
        QVERIFY(messageReceivedSpy.wait(1000));

        const qint64 elapsedMs = timer.elapsed();
        QVERIFY2(elapsedMs < 1000,
                  qPrintable(QStringLiteral("Round trip en %1 ms, attendu < 1000 ms").arg(elapsedMs)));

        client.disconnectFromHost();
        server.close();
    }

    void disconnectEmitsSignal()
    {
        QWebSocketServer server(QStringLiteral("TestServer"), QWebSocketServer::NonSecureMode);
        QVERIFY(server.listen(QHostAddress::LocalHost, 12349));

        MessagingService client;
        QSignalSpy connectedSpy(&client, &MessagingService::connected);
        QSignalSpy disconnectedSpy(&client, &MessagingService::disconnected);

        QVERIFY(client.connectToHost(QHostAddress::LocalHost, 12349));
        QVERIFY(connectedSpy.wait(5000));

        client.disconnectFromHost();
        QVERIFY(disconnectedSpy.wait(1000));
        QVERIFY(!client.isConnected());

        server.close();
    }

    void sendMessageWhenNotConnectedFails()
    {
        MessagingService client;
        QVERIFY(!client.isConnected());

        const QString testMessage = QStringLiteral("Test");
        QVERIFY(!client.sendMessage(testMessage));
    }
};

QTEST_MAIN(TestMessagingService)
#include "test_messagingservice.moc"
