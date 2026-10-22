// Appels vocaux : un client doit accepter l'appel du serveur qu'il a approuve
// (liste TrustedServers), comme il accepte deja ses messages et ses fichiers.
// Avant le correctif, la connexion de signalisation entrante n'acceptait que
// les machines autorisees : le serveur appelait le client sans que l'appel
// passe, et il etait meme inscrit comme machine en attente cote client.
#include <QtTest>
#include <QHostAddress>
#include <QSet>
#include <QSignalSpy>
#include <QTemporaryDir>

#include "Security/SecurityService.h"
#include "Voice/VoiceSignalingChannel.h"

using network::SecurityService;
using network::VoiceSignalingChannel;

class FakePermissions : public QObject
{
    Q_OBJECT
public:
    QSet<QString> authorizedMachines;   // AuthorizedMachines (geree par l'administrateur)
    QSet<QString> trustedServers;       // TrustedServers (serveur approuve par ce poste)
    int pendingRegistrations = 0;

    Q_INVOKABLE bool isMachineAuthorizedByCertificate(const QString &fingerprint) const
    {
        return authorizedMachines.contains(fingerprint.toLower());
    }
    Q_INVOKABLE bool isMachineAuthorizedOrTrustedServer(const QString &fingerprint) const
    {
        return authorizedMachines.contains(fingerprint.toLower()) || trustedServers.contains(fingerprint.toLower());
    }
    Q_INVOKABLE bool trustRemoteServerCertificate(const QString &fingerprint, const QString &)
    {
        return isMachineAuthorizedOrTrustedServer(fingerprint);
    }
    Q_INVOKABLE void recordMachineSeen(const QString &, const QString &) {}
    Q_INVOKABLE bool registerPendingMachineByCertificate(const QString &, const QString &, const QString &)
    {
        ++pendingRegistrations;
        return true;
    }
};

class TestVoiceSignalingAuth : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dirServer, m_dirClient, m_dirStranger;
    std::unique_ptr<SecurityService> m_server, m_client, m_stranger;

    static QString fp(SecurityService *s) { return s->identity().fingerprintSha256.toLower(); }

private slots:
    void initTestCase()
    {
        m_server = std::make_unique<SecurityService>(m_dirServer.path());
        m_client = std::make_unique<SecurityService>(m_dirClient.path());
        m_stranger = std::make_unique<SecurityService>(m_dirStranger.path());
        QVERIFY(m_server->initialize() && m_client->initialize() && m_stranger->initialize());
    }

    // Le serveur appelle le client : cote client, le serveur n'est pas une machine
    // autorisee mais un serveur approuve.
    void clientAcceptsCallFromItsTrustedServer()
    {
        FakePermissions clientPermissions;
        clientPermissions.trustedServers.insert(fp(m_server.get()));
        FakePermissions serverPermissions;
        serverPermissions.authorizedMachines.insert(fp(m_client.get()));

        VoiceSignalingChannel callee(m_client.get());
        callee.setPermissionManager(&clientPermissions);
        QVERIFY(callee.listen(23671));
        QSignalSpy incoming(&callee, &VoiceSignalingChannel::peerConnected);
        QSignalSpy calleeError(&callee, &VoiceSignalingChannel::error);

        VoiceSignalingChannel caller(m_server.get());
        caller.setPermissionManager(&serverPermissions);
        QSignalSpy outgoing(&caller, &VoiceSignalingChannel::peerConnected);
        QVERIFY(caller.connectToPeer(QHostAddress::LocalHost, 23671));

        QTRY_COMPARE_WITH_TIMEOUT(outgoing.count(), 1, 10000);
        QTRY_COMPARE_WITH_TIMEOUT(incoming.count(), 1, 10000);
        QCOMPARE(calleeError.count(), 0);
        QCOMPARE(clientPermissions.pendingRegistrations, 0);
    }

    // Une machine ni autorisee ni approuvee reste refusee (et notee en attente).
    void unknownMachineCallIsStillRefused()
    {
        FakePermissions calleePermissions;
        calleePermissions.trustedServers.insert(fp(m_server.get()));
        FakePermissions strangerPermissions;
        strangerPermissions.authorizedMachines.insert(fp(m_client.get()));

        VoiceSignalingChannel callee(m_client.get());
        callee.setPermissionManager(&calleePermissions);
        QVERIFY(callee.listen(23672));
        QSignalSpy incoming(&callee, &VoiceSignalingChannel::peerConnected);
        QSignalSpy calleeError(&callee, &VoiceSignalingChannel::error);

        VoiceSignalingChannel caller(m_stranger.get());
        caller.setPermissionManager(&strangerPermissions);
        QVERIFY(caller.connectToPeer(QHostAddress::LocalHost, 23672));

        QTRY_COMPARE_WITH_TIMEOUT(calleeError.count(), 1, 10000);
        QTest::qWait(300);
        QCOMPARE(incoming.count(), 0);
        QCOMPARE(calleePermissions.pendingRegistrations, 1);
    }

    // Sens inverse, qui fonctionnait deja : le client appelle le serveur.
    void serverAcceptsCallFromAuthorizedClient()
    {
        FakePermissions serverPermissions;
        serverPermissions.authorizedMachines.insert(fp(m_client.get()));
        FakePermissions clientPermissions;
        clientPermissions.trustedServers.insert(fp(m_server.get()));

        VoiceSignalingChannel callee(m_server.get());
        callee.setPermissionManager(&serverPermissions);
        QVERIFY(callee.listen(23673));
        QSignalSpy incoming(&callee, &VoiceSignalingChannel::peerConnected);

        VoiceSignalingChannel caller(m_client.get());
        caller.setPermissionManager(&clientPermissions);
        QSignalSpy outgoing(&caller, &VoiceSignalingChannel::peerConnected);
        QVERIFY(caller.connectToPeer(QHostAddress::LocalHost, 23673));

        QTRY_COMPARE_WITH_TIMEOUT(outgoing.count(), 1, 10000);
        QTRY_COMPARE_WITH_TIMEOUT(incoming.count(), 1, 10000);
        QCOMPARE(serverPermissions.pendingRegistrations, 0);
    }
};

QTEST_GUILESS_MAIN(TestVoiceSignalingAuth)
#include "test_voicesignalingauth.moc"
