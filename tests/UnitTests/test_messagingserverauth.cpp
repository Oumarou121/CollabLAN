// Lot 1 securite : une machine en attente d'autorisation, connectee au serveur de messagerie,
// ne doit rien recevoir (diffusions, messages cibles) ni pouvoir revendiquer un utilisateur.
#include <QtTest>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QSignalSpy>
#include <QSslConfiguration>
#include <QSslKey>
#include <QTemporaryDir>
#include <QWebSocket>

#include "Messaging/MessagingServer.h"
#include "Security/SecurityService.h"

using network::MessagingServer;
using network::SecurityService;

class FakePermissions : public QObject
{
    Q_OBJECT
public:
    QSet<QString> authorized;
    Q_INVOKABLE bool isMachineAuthorizedOrTrustedServer(const QString &fingerprint) const
    {
        return authorized.contains(fingerprint.toLower());
    }
    Q_INVOKABLE void recordMachineSeen(const QString &, const QString &) {}
    Q_INVOKABLE bool registerPendingMachineByCertificate(const QString &, const QString &, const QString &) { return true; }
};

class TestMessagingServerAuth : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dirServer, m_dirAuthorized, m_dirPending;
    std::unique_ptr<SecurityService> m_server, m_authorized, m_pending;

    static QString fp(SecurityService *s) { return s->identity().fingerprintSha256.toLower(); }

    std::unique_ptr<QWebSocket> connectClient(SecurityService *identity, quint16 port)
    {
        auto socket = std::make_unique<QWebSocket>();
        QSslConfiguration config = QSslConfiguration::defaultConfiguration();
        config.setLocalCertificate(QSslCertificate(identity->certificatePem(), QSsl::Pem));
        QFile keyFile(identity->privateKeyPath());
        if (keyFile.open(QIODevice::ReadOnly))
            config.setPrivateKey(QSslKey(keyFile.readAll(), QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey));
        config.setPeerVerifyMode(QSslSocket::VerifyNone);
        socket->setSslConfiguration(config);
        QWebSocket *raw = socket.get();
        connect(raw, &QWebSocket::sslErrors, raw, [raw](const QList<QSslError> &) { raw->ignoreSslErrors(); });
        QSignalSpy connected(raw, &QWebSocket::connected);
        socket->open(QUrl(QStringLiteral("wss://127.0.0.1:%1").arg(port)));
        if (!connected.wait(10000))
            return nullptr;
        return socket;
    }

    static void identify(QWebSocket *socket, SecurityService *identity, const QString &userUuid)
    {
        QJsonObject payload{{QStringLiteral("type"), QStringLiteral("identify")},
                            {QStringLiteral("userUuid"), userUuid},
                            {QStringLiteral("certificate_fingerprint"), identity->identity().fingerprintSha256.toLower()}};
        socket->sendTextMessage(QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
    }

private slots:
    void initTestCase()
    {
        m_server = std::make_unique<SecurityService>(m_dirServer.path());
        m_authorized = std::make_unique<SecurityService>(m_dirAuthorized.path());
        m_pending = std::make_unique<SecurityService>(m_dirPending.path());
        QVERIFY(m_server->initialize() && m_authorized->initialize() && m_pending->initialize());
    }

    void pendingMachineReceivesNothingAndCannotClaimAUser()
    {
        FakePermissions permissions;
        permissions.authorized.insert(fp(m_authorized.get()));

        MessagingServer server(m_server.get());
        server.setPermissionManager(&permissions);
        QVERIFY(server.start(23661));

        auto authorized = connectClient(m_authorized.get(), 23661);
        auto pending = connectClient(m_pending.get(), 23661);
        QVERIFY(authorized && pending);

        QSignalSpy authorizedReceived(authorized.get(), &QWebSocket::textMessageReceived);
        QSignalSpy pendingReceived(pending.get(), &QWebSocket::textMessageReceived);

        // La machine en attente revendique l'utilisateur de la machine autorisee.
        identify(authorized.get(), m_authorized.get(), QStringLiteral("user-alice"));
        identify(pending.get(), m_pending.get(), QStringLiteral("user-alice"));
        QTest::qWait(500);

        QCOMPARE(server.sendToUuids(QStringLiteral("{\"type\":\"message\",\"content\":\"prive\"}"), {QStringLiteral("user-alice")}), 1);
        QCOMPARE(server.broadcastMessage(QStringLiteral("{\"type\":\"user_event\",\"passwordHash\":\"x\"}")), 1);
        QCOMPARE(server.sendToFingerprint(QStringLiteral("{}"), fp(m_pending.get())), 0);

        QTRY_COMPARE_WITH_TIMEOUT(authorizedReceived.count(), 2, 5000);
        QTest::qWait(500);
        QCOMPARE(pendingReceived.count(), 0);
    }

    void authorizationGrantedLaterAppliesWithoutReconnection()
    {
        FakePermissions permissions;
        MessagingServer server(m_server.get());
        server.setPermissionManager(&permissions);
        QVERIFY(server.start(23662));

        auto client = connectClient(m_pending.get(), 23662);
        QVERIFY(client);
        QSignalSpy received(client.get(), &QWebSocket::textMessageReceived);
        QTest::qWait(300);
        QCOMPARE(server.broadcastMessage(QStringLiteral("{}")), 0);

        permissions.authorized.insert(fp(m_pending.get())); // l'administrateur autorise la machine
        QCOMPARE(server.broadcastMessage(QStringLiteral("{}")), 1);
        QTRY_COMPARE_WITH_TIMEOUT(received.count(), 1, 5000);

        permissions.authorized.clear(); // puis la revoque
        QCOMPARE(server.broadcastMessage(QStringLiteral("{}")), 0);
    }

    void serverRefusesToStartWithoutTlsIdentity()
    {
        MessagingServer server(nullptr);
        QVERIFY(!server.start(23663));
        QVERIFY(!server.isRunning());
    }
};

QTEST_GUILESS_MAIN(TestMessagingServerAuth)
#include "test_messagingserverauth.moc"
