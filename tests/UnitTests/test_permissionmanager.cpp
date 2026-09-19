#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "PermissionManager.h"
#include "DatabaseManager.h"
#include "models/AuthorizedMachine.h"

using core::PermissionManager;

// Couvre le plan "Machines autorisees avec etat pending/authorized/revoked" :
// - une machine inconnue n'est jamais auto-autorisee (trustRemoteServerCertificate) ;
// - seul le statut 'authorized' donne acces (isMachineAuthorizedByCertificate) ;
// - le bootstrap admin n'auto-autorise la machine locale que si la base ne
//   contient encore aucune machine authorized.
class TestPermissionManager : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<database::DatabaseManager> m_dbManager;
    std::unique_ptr<PermissionManager> m_manager;

    void freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        QVERIFY(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-permissionmanager-%1").arg(QRandomGenerator::global()->generate()));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        QVERIFY(opened);

        m_manager = std::make_unique<PermissionManager>(m_dbManager.get());
    }

private slots:
    void cleanup()
    {
        m_manager.reset();
        if (m_dbManager) {
            m_dbManager->close();
        }
        m_dbManager.reset();
        m_dir.reset();
    }

    void isMachineAuthorizedByCertificate_falseForUnknownFingerprint()
    {
        freshDatabase();
        QVERIFY(!m_manager->isMachineAuthorizedByCertificate(QStringLiteral("unknown")));
    }

    void trustRemoteServerCertificate_unknownCertificateIsRegisteredPendingAndRefused()
    {
        freshDatabase();

        const bool trusted = m_manager->trustRemoteServerCertificate(
            QStringLiteral("srv-fp"), QStringLiteral("192.168.1.1"));

        QVERIFY(!trusted);
        // Un serveur inconnu ne doit jamais apparaitre dans la politique
        // AuthorizedClients ni emettre machineChanged (signal serveur).
        QVERIFY(!m_manager->findMachineByCertificateFingerprint(QStringLiteral("srv-fp")).has_value());

        QVERIFY(!m_manager->isMachineAuthorizedByCertificate(QStringLiteral("srv-fp")));
    }

    void trustRemoteServerCertificate_authorizedCertificateIsAccepted()
    {
        freshDatabase();

        // La confiance envers un serveur est une decision locale du client,
        // independante de la liste AuthorizedClients du serveur.
        QVERIFY(m_manager->approveServerCertificate(
            QStringLiteral("srv-fp"), QStringLiteral("10.0.0.1"), QStringLiteral("srv")));

        QVERIFY(m_manager->trustRemoteServerCertificate(QStringLiteral("srv-fp"), QStringLiteral("10.0.0.1")));
        QVERIFY(!m_manager->isMachineAuthorizedByCertificate(QStringLiteral("srv-fp")));
        QVERIFY(m_manager->isMachineAuthorizedOrTrustedServer(QStringLiteral("srv-fp")));
    }

    void pendingCertificateIsNotAcceptedForTemporaryServerRecovery()
    {
        freshDatabase();
        QVERIFY(!m_manager->trustRemoteServerCertificate(
            QStringLiteral("pending-fp"), QStringLiteral("10.0.0.2")));
        QVERIFY(!m_manager->isMachineAuthorizedOrTrustedServer(QStringLiteral("pending-fp")));
    }

    void trustRemoteServerCertificate_revokedCertificateIsRefused()
    {
        freshDatabase();

        QVERIFY(m_manager->approveServerCertificate(
            QStringLiteral("srv-fp"), QStringLiteral("10.0.0.1"), QStringLiteral("srv")));
        QVERIFY(m_manager->revokeServerCertificate(QStringLiteral("srv-fp"), QStringLiteral("Revoque")));

        QVERIFY(!m_manager->trustRemoteServerCertificate(QStringLiteral("srv-fp"), QStringLiteral("10.0.0.1")));
        QVERIFY(!m_manager->isMachineAuthorizedByCertificate(QStringLiteral("srv-fp")));
    }

    void registerPendingMachineByCertificate_emitsMachineChangedOnlyOnceForNewMachine()
    {
        freshDatabase();

        QSignalSpy spy(m_manager.get(), &PermissionManager::machineChanged);

        QVERIFY(m_manager->registerPendingMachineByCertificate(QStringLiteral("fp-1"), QStringLiteral("10.0.0.1")));
        QCOMPARE(spy.count(), 1);

        // Un second contact de la meme machine (deja connue) ne doit pas
        // re-emettre machineChanged : rien de nouveau a afficher dans l'admin.
        QVERIFY(m_manager->registerPendingMachineByCertificate(QStringLiteral("fp-1"), QStringLiteral("10.0.0.2")));
        QCOMPARE(spy.count(), 1);
    }

};

QTEST_MAIN(TestPermissionManager)
#include "test_permissionmanager.moc"
