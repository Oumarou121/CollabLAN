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

    // Serveur officiel qui revient : il reprend les autorisations donnees sur
    // le serveur de secours, sauf pour une machine sur laquelle il a deja tranche.
    void adoptTempServerAuthorization_onlyUnknownOrPending()
    {
        freshDatabase();
        // Inconnue : reprise, sans auteur local (cle etrangere nulle).
        QVERIFY(m_manager->adoptTempServerAuthorization(QStringLiteral("a1"), QStringLiteral("uuid-a1"),
                                                        QStringLiteral("POSTE-A1"), QStringLiteral("10.0.0.1"),
                                                        std::nullopt, QStringLiteral("secours")));
        QVERIFY(m_manager->isMachineAuthorizedByCertificate(QStringLiteral("a1")));
        QCOMPARE(m_manager->findMachineByCertificateFingerprint(QStringLiteral("a1"))->reason(), QStringLiteral("secours"));

        // En attente : reprise.
        QVERIFY(m_manager->registerPendingMachineByCertificate(QStringLiteral("b2"), QStringLiteral("10.0.0.2")));
        QVERIFY(m_manager->adoptTempServerAuthorization(QStringLiteral("b2"), QString(), QString(),
                                                        QStringLiteral("10.0.0.2"), std::nullopt, QStringLiteral("secours")));
        QVERIFY(m_manager->isMachineAuthorizedByCertificate(QStringLiteral("b2")));

        // Revoquee ici : la revocation fait foi.
        QSqlQuery insert(m_dbManager->database());
        QVERIFY(insert.exec(QStringLiteral(
            "INSERT INTO Users (name, ip_address, status, role, password_hash, password_salt, uuid, updated_at) "
            "VALUES ('admin', '', 'active', 'admin', 'x', 'y', 'u-admin', '2026-10-22T00:00:00Z')")));
        QVERIFY(m_manager->revokeMachineByCertificate(QStringLiteral("b2"), insert.lastInsertId().toInt(),
                                                      QStringLiteral("revoque")));
        QVERIFY(!m_manager->adoptTempServerAuthorization(QStringLiteral("b2"), QString(), QString(),
                                                         QStringLiteral("10.0.0.2"), std::nullopt, QStringLiteral("secours")));
        QVERIFY(!m_manager->isMachineAuthorizedByCertificate(QStringLiteral("b2")));

        // Deja autorisee : inchangee (pas de reecriture de la raison).
        QVERIFY(!m_manager->adoptTempServerAuthorization(QStringLiteral("a1"), QString(), QString(),
                                                         QString(), std::nullopt, QStringLiteral("autre")));
        QCOMPARE(m_manager->findMachineByCertificateFingerprint(QStringLiteral("a1"))->reason(), QStringLiteral("secours"));
    }

    // Serveur designe par le serveur actif (champ "servers") : epingle au
    // premier contact, sauf s'il a ete revoque localement.
    void vouchedServer_pinnedUnlessRevoked()
    {
        freshDatabase();
        QVERIFY(!m_manager->trustRemoteServerCertificate(QStringLiteral("s1"), QStringLiteral("10.0.0.9")));

        m_manager->setVouchedServerFingerprints({QStringLiteral(" S1 "), QStringLiteral("s2")});
        QVERIFY(m_manager->trustRemoteServerCertificate(QStringLiteral("s1"), QStringLiteral("10.0.0.9")));
        // Epingle : reste reconnu quand la liste est remplacee (redemarrage).
        m_manager->setVouchedServerFingerprints({});
        QVERIFY(m_manager->isTrustedServer(QStringLiteral("s1")));
        QCOMPARE(m_manager->trustedServerFingerprints(), QStringList({QStringLiteral("s1")}));

        // Revoque localement : la designation ne le retablit pas.
        QVERIFY(m_manager->approveServerCertificate(QStringLiteral("s2"), QStringLiteral("10.0.0.8")));
        QVERIFY(m_manager->revokeServerCertificate(QStringLiteral("s2"), QStringLiteral("revoque")));
        m_manager->setVouchedServerFingerprints({QStringLiteral("s2")});
        QVERIFY(!m_manager->trustRemoteServerCertificate(QStringLiteral("s2"), QStringLiteral("10.0.0.8")));
        QVERIFY(!m_manager->isTrustedServer(QStringLiteral("s2")));
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

    // Adresse IPv4 rapportee au format IPv6 par une socket double pile :
    // enregistree sous sa forme IPv4 (elle s'affichait comme nom de poste).
    void ipv4MappedAddressIsStoredAsIpv4()
    {
        freshDatabase();
        QVERIFY(m_manager->registerPendingMachineByCertificate(QStringLiteral("ab12"), QStringLiteral("::ffff:192.168.1.147")));
        auto machine = m_manager->findMachineByCertificateFingerprint(QStringLiteral("ab12"));
        QVERIFY(machine.has_value());
        QCOMPARE(machine->ipAddress(), QStringLiteral("192.168.1.147"));

        m_manager->recordMachineSeen(QStringLiteral("ab12"), QStringLiteral("::ffff:192.168.1.148"));
        machine = m_manager->findMachineByCertificateFingerprint(QStringLiteral("ab12"));
        QCOMPARE(machine->lastIpAddress(), QStringLiteral("192.168.1.148"));
    }

    // Nom du poste et dernier compte (decouverte) gardes pour le nommer hors
    // ligne ; signal d'affichage seulement quand quelque chose change, sans
    // machineChanged (qui rediffuserait la liste des postes autorises).
    void recordMachineIdentity_keepsNameAndLastUser()
    {
        freshDatabase();
        QVERIFY(m_manager->registerPendingMachineByCertificate(QStringLiteral("cd34"), QStringLiteral("192.168.1.20")));
        QSignalSpy identity(m_manager.get(), &PermissionManager::machineIdentityChanged);
        QSignalSpy changed(m_manager.get(), &PermissionManager::machineChanged);

        m_manager->recordMachineIdentity(QStringLiteral("CD34"), QStringLiteral("PC-COMPTA"), QStringLiteral("uuid-awa"));
        auto machine = m_manager->findMachineByCertificateFingerprint(QStringLiteral("cd34"));
        QCOMPARE(machine->hostname(), QStringLiteral("PC-COMPTA"));
        QCOMPARE(machine->lastUserUuid(), QStringLiteral("uuid-awa"));
        QCOMPARE(identity.count(), 1);

        // Annonce identique, puis annonce sans compte (personne connectee) :
        // rien ne change, le dernier compte reste connu.
        m_manager->recordMachineIdentity(QStringLiteral("cd34"), QStringLiteral("PC-COMPTA"), QStringLiteral("uuid-awa"));
        m_manager->recordMachineIdentity(QStringLiteral("cd34"), QStringLiteral("PC-COMPTA"), QString());
        machine = m_manager->findMachineByCertificateFingerprint(QStringLiteral("cd34"));
        QCOMPARE(machine->lastUserUuid(), QStringLiteral("uuid-awa"));
        QCOMPARE(identity.count(), 1);
        QCOMPARE(changed.count(), 0);

        // Poste inconnu : rien n'est cree.
        m_manager->recordMachineIdentity(QStringLiteral("zz99"), QStringLiteral("PC-X"), QStringLiteral("uuid-x"));
        QVERIFY(!m_manager->findMachineByCertificateFingerprint(QStringLiteral("zz99")).has_value());
    }

};

QTEST_MAIN(TestPermissionManager)
#include "test_permissionmanager.moc"
