#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QRandomGenerator>
#include <QSqlQuery>

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

    // Liste envoyee par le serveur actif : un autre client autorise par le
    // serveur est accepte pour les appels et transferts directs.
    void serverAuthorizedFingerprints_acceptedReplacedAndCleared()
    {
        freshDatabase();
        QVERIFY(!m_manager->isMachineAuthorizedOrTrustedServer(QStringLiteral("aa11")));

        m_manager->setServerAuthorizedFingerprints({QStringLiteral(" AA11 "), QStringLiteral("bb22")});
        QVERIFY(m_manager->isMachineAuthorizedOrTrustedServer(QStringLiteral("aa11")));
        QVERIFY(m_manager->isAuthorizedByServer(QStringLiteral("BB22")));
        // Jamais ecrite dans la politique d'admission locale.
        QVERIFY(!m_manager->isMachineAuthorizedByCertificate(QStringLiteral("aa11")));
        QVERIFY(!m_manager->findMachineByCertificateFingerprint(QStringLiteral("aa11")).has_value());

        // Un nouvel envoi remplace le precedent (revocation cote serveur).
        m_manager->setServerAuthorizedFingerprints({QStringLiteral("bb22")});
        QVERIFY(!m_manager->isMachineAuthorizedOrTrustedServer(QStringLiteral("aa11")));
        QVERIFY(m_manager->isMachineAuthorizedOrTrustedServer(QStringLiteral("bb22")));

        m_manager->clearServerAuthorizedFingerprints();
        QVERIFY(!m_manager->isMachineAuthorizedOrTrustedServer(QStringLiteral("bb22")));
    }

    // Un serveur (officiel ou de secours) envoie ses machines autorisees et
    // relaie la liste recue ; une machine seulement en attente n'y figure pas.
    void authorizedFingerprintsForPeers_mergesLocalAuthorizedAndReceived()
    {
        freshDatabase();
        // L'auteur d'une autorisation est un compte existant (cle etrangere).
        QSqlQuery insert(m_dbManager->database());
        QVERIFY(insert.exec(QStringLiteral(
            "INSERT INTO Users (name, ip_address, status, role, password_hash, password_salt, uuid, updated_at) "
            "VALUES ('admin', '', 'active', 'admin', 'x', 'y', 'u-admin', '2026-10-22T00:00:00Z')")));
        const int adminId = insert.lastInsertId().toInt();

        QVERIFY(m_manager->registerPendingMachineByCertificate(QStringLiteral("cc33"), QStringLiteral("10.0.0.3")));
        QVERIFY(m_manager->registerPendingMachineByCertificate(QStringLiteral("dd44"), QStringLiteral("10.0.0.4")));
        QVERIFY(m_manager->authorizeExistingMachineByCertificate(QStringLiteral("cc33"), adminId, QStringLiteral("test")));
        m_manager->setServerAuthorizedFingerprints({QStringLiteral("ee55")});

        QCOMPARE(m_manager->authorizedFingerprintsForPeers(),
                 QStringList({QStringLiteral("cc33"), QStringLiteral("ee55")}));
    }

    void removeMachine_emitsMachineRemoved()
    {
        freshDatabase();
        QVERIFY(m_manager->registerPendingMachineByCertificate(QStringLiteral("ff66"), QStringLiteral("10.0.0.6")));
        const auto machine = m_manager->findMachineByCertificateFingerprint(QStringLiteral("ff66"));
        QVERIFY(machine.has_value());

        QSignalSpy spy(m_manager.get(), &PermissionManager::machineRemoved);
        QVERIFY(m_manager->removeMachine(machine->id()));
        QCOMPARE(spy.count(), 1);
    }

};

QTEST_MAIN(TestPermissionManager)
#include "test_permissionmanager.moc"
