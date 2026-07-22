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

        QSignalSpy spy(m_manager.get(), &PermissionManager::machineChanged);
        const bool trusted = m_manager->trustRemoteServerCertificate(
            QStringLiteral("srv-fp"), QStringLiteral("192.168.1.1"));

        QVERIFY(!trusted);
        QCOMPARE(spy.count(), 1);

        const auto machine = m_manager->findMachineByCertificateFingerprint(QStringLiteral("srv-fp"));
        QVERIFY(machine.has_value());
        QCOMPARE(machine->status(), models::MachineStatus::Pending);
        QVERIFY(!m_manager->isMachineAuthorizedByCertificate(QStringLiteral("srv-fp")));
    }

    void trustRemoteServerCertificate_authorizedCertificateIsAccepted()
    {
        freshDatabase();

        // Enregistre puis autorise manuellement, comme le ferait un admin
        // depuis une machine deja autorisee.
        m_manager->registerPendingMachineByCertificate(QStringLiteral("srv-fp"), QStringLiteral("10.0.0.1"));
        QVERIFY(m_manager->authorizeExistingMachineByCertificate(
            QStringLiteral("srv-fp"), 1, QStringLiteral("Autorise par admin")));

        QVERIFY(m_manager->trustRemoteServerCertificate(QStringLiteral("srv-fp"), QStringLiteral("10.0.0.1")));
        QVERIFY(m_manager->isMachineAuthorizedByCertificate(QStringLiteral("srv-fp")));
    }

    void trustRemoteServerCertificate_revokedCertificateIsRefused()
    {
        freshDatabase();

        m_manager->registerPendingMachineByCertificate(QStringLiteral("srv-fp"), QStringLiteral("10.0.0.1"));
        QVERIFY(m_manager->authorizeExistingMachineByCertificate(QStringLiteral("srv-fp"), 1, QString()));
        QVERIFY(m_manager->revokeMachineByCertificate(QStringLiteral("srv-fp"), 1, QStringLiteral("Revoque")));

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

    void bootstrapLocalAdminMachineIfNeeded_authorizesLocalMachineOnEmptyDatabase()
    {
        freshDatabase();

        QVERIFY(m_manager->bootstrapLocalAdminMachineIfNeeded(
            QStringLiteral("local-fp"), QStringLiteral("local-uuid"),
            QStringLiteral("my-pc"), QStringLiteral("127.0.0.1"), 1));

        QVERIFY(m_manager->isMachineAuthorizedByCertificate(QStringLiteral("local-fp")));
    }

    void bootstrapLocalAdminMachineIfNeeded_doesNothingWhenAnAuthorizedMachineAlreadyExists()
    {
        freshDatabase();

        QVERIFY(m_manager->bootstrapLocalAdminMachineIfNeeded(
            QStringLiteral("first-admin-fp"), QStringLiteral("uuid-1"),
            QStringLiteral("pc-1"), QStringLiteral("127.0.0.1"), 1));

        // Une deuxieme machine (meme un admin) ne doit jamais s'auto-autoriser
        // une fois le bootstrap initial effectue : elle doit passer par la
        // validation normale depuis une machine deja autorisee.
        const bool secondBootstrap = m_manager->bootstrapLocalAdminMachineIfNeeded(
            QStringLiteral("second-admin-fp"), QStringLiteral("uuid-2"),
            QStringLiteral("pc-2"), QStringLiteral("127.0.0.1"), 2);

        QVERIFY(!secondBootstrap);
        QVERIFY(!m_manager->isMachineAuthorizedByCertificate(QStringLiteral("second-admin-fp")));
        // La premiere machine bootstrappee reste autorisee.
        QVERIFY(m_manager->isMachineAuthorizedByCertificate(QStringLiteral("first-admin-fp")));
    }
};

QTEST_MAIN(TestPermissionManager)
#include "test_permissionmanager.moc"
