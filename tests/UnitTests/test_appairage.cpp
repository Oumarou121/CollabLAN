// Code d'appairage : le serveur et un poste neuf affichent chacun un code a
// 6 chiffres, calcule a partir des deux certificats ; l'administrateur et
// l'utilisateur verifient que c'est le meme avant d'autoriser / approuver.
#include <QtTest>
#include <QHostAddress>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QTemporaryDir>

#include "Application.h"
#include "PermissionManager.h"
#include "UserManager.h"
#include "Election/ElectionService.h"
#include "Messaging/MessagingService.h"
#include "Security/SecurityService.h"
#include "models/AuthorizedMachine.h"

using network::SecurityService;

class TestAppairage : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;

private slots:
    void codeIsSymmetricStableAndSixDigits()
    {
        const QString a = QStringLiteral("13b5c43e09e3ef79fe47bf2e8452a821da66ead8d7889cadbb30587d356e71b2");
        const QString b = QStringLiteral("fcf6ba7e0b2844ca4324b82644d36bde9e122282854b2ae988bdf5ff3d7467d8");
        const QString code = SecurityService::pairingCode(a, b);
        QVERIFY(QRegularExpression(QStringLiteral("^\\d{6}$")).match(code).hasMatch());
        // Meme code des deux cotes, quelle que soit la casse ou la forme.
        QCOMPARE(SecurityService::pairingCode(b, a), code);
        QCOMPARE(SecurityService::pairingCode(a.toUpper(), b), code);
        QCOMPARE(SecurityService::pairingCode(a, b), code);
    }

    void codeChangesWhenOneCertificateChanges()
    {
        const QString a = QStringLiteral("13b5c43e09e3ef79fe47bf2e8452a821da66ead8d7889cadbb30587d356e71b2");
        const QString b = QStringLiteral("fcf6ba7e0b2844ca4324b82644d36bde9e122282854b2ae988bdf5ff3d7467d8");
        const QString intruder = QStringLiteral("6cf497be1ecf931ff3451a8568a47ac00b552b98df6eac92ba10b6386a07f3b4");
        QVERIFY(SecurityService::pairingCode(a, b) != SecurityService::pairingCode(intruder, b));
        QVERIFY(SecurityService::pairingCode(a, b) != SecurityService::pairingCode(a, intruder));
        QVERIFY(SecurityService::pairingCode(QString(), b).isEmpty());
    }

    // Parcours reel : un poste neuf contacte le serveur ; chacun affiche le meme
    // code ; une fois les deux confirmations faites, le poste est relie.
    void newPostShowsSameCodeAsAdministrator()
    {
        QVERIFY(m_dir.isValid());
        const quint16 base = static_cast<quint16>(34000 + QRandomGenerator::global()->bounded(1500) * 10);
        Application server;
        server.setDiscoveryPort(static_cast<quint16>(base + 5));
        server.initialize(base, m_dir.filePath(QStringLiteral("serveur.db")), QStringLiteral("SERVER"), -1,
                          static_cast<quint16>(base + 6));
        Application post;
        post.setDiscoveryPort(static_cast<quint16>(base + 15));
        post.initialize(static_cast<quint16>(base + 10), m_dir.filePath(QStringLiteral("poste.db")),
                        QStringLiteral("CLIENT"), -1, static_cast<quint16>(base + 16));
        post.electionService()->setHeartbeatTimeoutMs(10 * 60 * 1000);
        const QString serverFp = server.securityService()->identity().fingerprintSha256.toLower();
        const QString postFp = post.securityService()->identity().fingerprintSha256.toLower();

        // Le poste neuf ne connait pas encore le serveur : demande d'approbation.
        QSignalSpy pending(&post, &Application::pendingServerChanged);
        QVERIFY(post.messagingService()->connectToHost(QHostAddress::LocalHost, base));
        QTRY_VERIFY_WITH_TIMEOUT(!post.pendingServerFingerprint().isEmpty(), 10000);
        QCOMPARE(post.pendingServerFingerprint().toLower(), serverFp);

        // Cote serveur, la machine apparait en attente.
        QTRY_VERIFY_WITH_TIMEOUT(server.permissionManager()->findMachineByCertificateFingerprint(postFp).has_value(), 10000);

        // Les deux ecrans affichent le meme code.
        const QString postSide = post.pendingServerPairingCode();
        const QString adminSide = server.pairingCodeWith(postFp);
        QVERIFY(!postSide.isEmpty());
        QCOMPARE(postSide, adminSide);

        // Les deux confirmations : l'administrateur autorise, l'utilisateur approuve.
        const auto admin = server.userManager()->createUser(QStringLiteral("admin"), QStringLiteral("motdepasse"));
        QVERIFY(admin.has_value());
        QVERIFY(server.permissionManager()->authorizeExistingMachineByCertificate(postFp, admin->id(), QStringLiteral("codes identiques")));
        QVERIFY(post.approvePendingServerCertificate());
        QTRY_VERIFY_WITH_TIMEOUT(post.messagingService()->isConnected() && post.messagingService()->peerPort() == base, 10000);
        QVERIFY(post.pendingServerFingerprint().isEmpty());
    }
};

QTEST_MAIN(TestAppairage)
#include "test_appairage.moc"
