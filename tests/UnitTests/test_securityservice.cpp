#include <QtTest>
#include <QTemporaryDir>
#include <QFile>
#include <QFileInfo>

#include "Security/SecurityService.h"

using network::SecurityService;
using network::LocalIdentity;

/*
 * Verifie le critere d'acceptation de l'issue #11 :
 * "Un certificat valide est present apres le premier lancement".
 *
 * Un repertoire de stockage temporaire est utilise pour ne pas polluer/
 * dependre du repertoire de donnees applicatif reel de la machine de CI.
 */
class TestSecurityService : public QObject
{
    Q_OBJECT

private slots:
    void firstLaunchGeneratesValidCertificate()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        SecurityService service(dir.path());

        QVERIFY(service.initialize());
        QVERIFY(service.isReady());

        const LocalIdentity id = service.identity();
        QVERIFY(id.valid);
        QVERIFY(id.wasGenerated);
        QVERIFY(!id.fingerprintSha256.isEmpty());
        QVERIFY(id.notBefore.isValid());
        QVERIFY(id.notAfter.isValid());
        QVERIFY(id.notAfter > QDateTime::currentDateTimeUtc());

        // Les fichiers cle/certificat doivent exister sur le disque.
        QVERIFY(QFile::exists(service.privateKeyPath()));
        QVERIFY(QFile::exists(service.certificatePath()));
        QVERIFY(!service.certificatePem().isEmpty());

        // Stockage securise : la cle privee ne doit etre accessible qu'au
        // proprietaire. Sur Linux/macOS (permissions POSIX), on verifie
        // explicitement l'absence d'acces groupe/autre. Sur Windows, le
        // systeme de fichiers NTFS n'a pas la notion POSIX
        // owner/group/other : QFileDevice::permissions() reflete les ACL
        // NTFS et rapporte les memes bits pour Owner/User/Group/Other des
        // qu'un utilisateur a acces au fichier, donc cette verification
        // stricte ne serait pas representative sur cette plateforme.
#ifndef Q_OS_WIN
        const QFileInfo keyInfo(service.privateKeyPath());
        const QFileDevice::Permissions perms = keyInfo.permissions();
        QVERIFY(!(perms & QFileDevice::ReadGroup));
        QVERIFY(!(perms & QFileDevice::ReadOther));
        QVERIFY(!(perms & QFileDevice::WriteGroup));
        QVERIFY(!(perms & QFileDevice::WriteOther));
#endif
    }

    void secondLaunchLoadsExistingIdentity()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        QString firstFingerprint;
        {
            SecurityService first(dir.path());
            QVERIFY(first.initialize());
            firstFingerprint = first.identity().fingerprintSha256;
            QVERIFY(first.identity().wasGenerated);
        }

        // Nouvelle instance pointant vers le meme repertoire : doit charger
        // l'identite existante plutot que d'en generer une nouvelle.
        SecurityService second(dir.path());
        QVERIFY(second.initialize());
        QVERIFY(second.isReady());
        QVERIFY(!second.identity().wasGenerated);
        QCOMPARE(second.identity().fingerprintSha256, firstFingerprint);
    }

    void corruptedKeyTriggersRegeneration()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        QString originalFingerprint;
        QString keyPath;
        {
            SecurityService first(dir.path());
            QVERIFY(first.initialize());
            originalFingerprint = first.identity().fingerprintSha256;
            keyPath = first.privateKeyPath();
        }

        // Corrompt le fichier de cle privee sur le disque.
        {
            QFile keyFile(keyPath);
            QVERIFY(keyFile.open(QIODevice::WriteOnly | QIODevice::Truncate));
            keyFile.write("not a valid pem key");
            keyFile.close();
        }

        SecurityService second(dir.path());
        QVERIFY(second.initialize());
        QVERIFY(second.isReady());
        QVERIFY(second.identity().wasGenerated);
        QVERIFY(second.identity().fingerprintSha256 != originalFingerprint);
    }
};

QTEST_MAIN(TestSecurityService)
#include "test_securityservice.moc"
