// Lot 1 securite : un fichier n'est accepte que si l'expediteur PROUVE son identite par son
// certificat TLS. Recopier l'empreinte d'une machine autorisee (visible dans la decouverte UDP)
// dans la trame d'identite ne doit plus suffire.
#include <QtTest>
#include <QDataStream>
#include <QFile>
#include <QSet>
#include <QSignalSpy>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslSocket>
#include <QTemporaryDir>

#include "Security/SecurityService.h"
#include "Transfer/TransferService.h"

using network::SecurityService;
using network::TransferService;

// Remplace PermissionManager (appele par QMetaObject::invokeMethod) : liste blanche d'empreintes.
class FakePermissions : public QObject
{
    Q_OBJECT
public:
    QSet<QString> authorized;
    QStringList pending;

    Q_INVOKABLE bool isMachineAuthorizedByCertificate(const QString &fingerprint) const
    {
        return authorized.contains(fingerprint.toLower());
    }
    Q_INVOKABLE bool trustRemoteServerCertificate(const QString &, const QString &) { return false; }
    Q_INVOKABLE void recordMachineSeen(const QString &, const QString &) {}
    Q_INVOKABLE bool registerPendingMachineByCertificate(const QString &fingerprint, const QString &, const QString &)
    {
        pending << fingerprint.toLower();
        return true;
    }
};

class TestTransferIdentity : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dirA, m_dirB, m_dirAttacker, m_receiveDir, m_sourceDir;
    std::unique_ptr<SecurityService> m_a, m_b, m_attacker;

    static QByteArray frame(const QByteArray &payload)
    {
        QByteArray out;
        QDataStream stream(&out, QIODevice::WriteOnly);
        stream.setVersion(QDataStream::Qt_6_0);
        stream << static_cast<quint32>(payload.size());
        out.append(payload);
        return out;
    }

    QString writeSource()
    {
        const QString path = m_sourceDir.filePath(QStringLiteral("contrat.pdf"));
        QFile file(path);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(QByteArray(200 * 1024, 'x'));
            file.close();
        }
        return path;
    }

    /// En-tete de fichier, meme format que TransferService::encodeHeader().
    static QByteArray header(const QString &fileName, qint64 size)
    {
        QByteArray payload;
        QDataStream stream(&payload, QIODevice::WriteOnly);
        stream.setVersion(QDataStream::Qt_6_0);
        stream << fileName << size << QStringLiteral("1") << QStringLiteral("2") << QStringLiteral("machine-x")
               << static_cast<quint8>(0) << false << QString();
        return payload;
    }

    /// Client brut : poignee de main TLS (avec ou sans certificat), puis trame d'identite annoncant
    /// `claimedFingerprint` et en-tete d'un fichier, comme le ferait un vrai expediteur.
    /// Renvoie faux si la poignee de main TLS elle-meme n'aboutit pas (le test doit alors echouer :
    /// il ne prouverait rien).
    bool sendAsRawClient(quint16 port, SecurityService *identity, const QString &claimedFingerprint)
    {
        QSslSocket client;
        QSslConfiguration config = client.sslConfiguration();
        if (identity) {
            config.setLocalCertificate(QSslCertificate(identity->certificatePem(), QSsl::Pem));
            QFile keyFile(identity->privateKeyPath());
            if (keyFile.open(QIODevice::ReadOnly))
                config.setPrivateKey(QSslKey(keyFile.readAll(), QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey));
        }
        config.setPeerVerifyMode(QSslSocket::QueryPeer);
        client.setSslConfiguration(config);
        connect(&client, &QSslSocket::sslErrors, &client, [&client](const QList<QSslError> &) { client.ignoreSslErrors(); });
        // Attente non bloquante : le recepteur tourne dans la meme boucle d'evenements que ce client.
        QSignalSpy encrypted(&client, &QSslSocket::encrypted);
        client.connectToHostEncrypted(QStringLiteral("127.0.0.1"), port);
        if (!encrypted.wait(10000))
            return false;
        client.write(frame(QByteArrayLiteral("CLFT-ID1:") + claimedFingerprint.toUtf8()));
        client.write(frame(header(QStringLiteral("intrus.exe"), 1024)));
        client.flush();
        // Laisse au recepteur le temps de traiter les trames (et, avant correctif, de demarrer la reception).
        QTest::qWait(1500);
        return true;
    }

private slots:
    void initTestCase()
    {
        QVERIFY(m_dirA.isValid() && m_dirB.isValid() && m_dirAttacker.isValid() && m_receiveDir.isValid() && m_sourceDir.isValid());
        m_a = std::make_unique<SecurityService>(m_dirA.path());
        m_b = std::make_unique<SecurityService>(m_dirB.path());
        m_attacker = std::make_unique<SecurityService>(m_dirAttacker.path());
        QVERIFY(m_a->initialize());
        QVERIFY(m_b->initialize());
        QVERIFY(m_attacker->initialize());
    }

    void authorizedSenderIsAccepted()
    {
        FakePermissions receiverPermissions;
        receiverPermissions.authorized.insert(m_a->identity().fingerprintSha256.toLower());
        FakePermissions senderPermissions;
        senderPermissions.authorized.insert(m_b->identity().fingerprintSha256.toLower());

        TransferService receiver;
        receiver.setSecurityService(m_b.get());
        receiver.setPermissionManager(&receiverPermissions);
        receiver.setReceiveDirectory(m_receiveDir.path());
        QVERIFY(receiver.start(23561));

        TransferService sender;
        sender.setSecurityService(m_a.get());
        sender.setPermissionManager(&senderPermissions);

        QSignalSpy received(&receiver, &TransferService::transferCompleted);
        QSignalSpy failed(&receiver, &TransferService::transferFailed);
        QVERIFY(sender.sendFile(QHostAddress::LocalHost, 23561, writeSource(), QStringLiteral("1"), QStringLiteral("2")));
        QVERIFY2(received.wait(15000), "le fichier d'une machine autorisee doit etre recu");
        QCOMPARE(failed.count(), 0);
    }

    void copiedFingerprintOfAnAuthorizedMachineIsRefused()
    {
        FakePermissions receiverPermissions;
        receiverPermissions.authorized.insert(m_a->identity().fingerprintSha256.toLower());

        TransferService receiver;
        receiver.setSecurityService(m_b.get());
        receiver.setPermissionManager(&receiverPermissions);
        receiver.setReceiveDirectory(m_receiveDir.path());
        QVERIFY(receiver.start(23562));
        QSignalSpy started(&receiver, &TransferService::transferStarted);

        // L'attaquant presente SON certificat mais annonce l'empreinte de la machine A (autorisee).
        QVERIFY(sendAsRawClient(23562, m_attacker.get(), m_a->identity().fingerprintSha256.toLower()));
        QCOMPARE(started.count(), 0);
    }

    void connectionWithoutClientCertificateIsRefused()
    {
        FakePermissions receiverPermissions;
        receiverPermissions.authorized.insert(m_a->identity().fingerprintSha256.toLower());

        TransferService receiver;
        receiver.setSecurityService(m_b.get());
        receiver.setPermissionManager(&receiverPermissions);
        receiver.setReceiveDirectory(m_receiveDir.path());
        QVERIFY(receiver.start(23563));
        QSignalSpy started(&receiver, &TransferService::transferStarted);

        // Aucun certificat client : avant correctif, l'empreinte annoncee suffisait et le fichier etait recu.
        QVERIFY(sendAsRawClient(23563, nullptr, m_a->identity().fingerprintSha256.toLower()));
        QCOMPARE(started.count(), 0);
    }
};

QTEST_GUILESS_MAIN(TestTransferIdentity)
#include "test_transferidentity.moc"
