#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QHostAddress>
#include <QFile>
#include <QRandomGenerator>

#include "database/DatabaseManager.h"
#include "database/Repositories/TransferRepository.h"
#include "database/Repositories/UserRepository.h"
#include "database/Repositories/SettingsRepository.h"
#include "models/Settings.h"
#include "network/Transfer/TransferService.h"
#include "TransferManager.h"

/*
 * Issue #55 : "Enregistrement d'un transfert (fichier, expediteur,
 * destinataire, statut)" + "Mise a jour du statut (en cours / termine /
 * echoue)", avec comme critere d'acceptation que "L'historique des
 * transferts est consultable apres redemarrage".
 *
 * On fait realiser un transfert TCP complet (TransferService en boucle
 * locale, a la fois expediteur et destinataire) pilote par un
 * core::TransferManager, puis on "redemarre" en rouvrant une toute
 * nouvelle database::DatabaseManager sur le meme fichier .sqlite pour
 * verifier que l'historique persiste bel et bien sur disque.
 */
class TestTransferManager : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dbDir;
    QTemporaryDir m_sourceDir;
    QTemporaryDir m_destDir;
    QString m_dbPath;
    QString m_senderUuid;
    QString m_recipientUuid;

private slots:
    void init()
    {
        QVERIFY(m_dbDir.isValid());
        QVERIFY(m_sourceDir.isValid());
        QVERIFY(m_destDir.isValid());
        m_dbPath = m_dbDir.filePath(
            QStringLiteral("test_%1.sqlite").arg(QRandomGenerator::global()->generate()));

        database::DatabaseManager setup(
            QStringLiteral("test_transfermanager_setup_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(setup.open(m_dbPath));

        database::UserRepository userRepo(setup.database());
        models::User sender;
        sender.setName(QStringLiteral("alice"));
        sender.setPasswordHash(QStringLiteral("hash"));
        sender.setPasswordSalt(QStringLiteral("salt"));
        const int senderId = userRepo.create(sender);
        QVERIFY(senderId >= 0);
        m_senderUuid = userRepo.findById(senderId)->uuid();
        QVERIFY(!m_senderUuid.isEmpty());

        models::User recipient;
        recipient.setName(QStringLiteral("bob"));
        recipient.setPasswordHash(QStringLiteral("hash"));
        recipient.setPasswordSalt(QStringLiteral("salt"));
        const int recipientId = userRepo.create(recipient);
        QVERIFY(recipientId >= 0);
        m_recipientUuid = userRepo.findById(recipientId)->uuid();
        QVERIFY(!m_recipientUuid.isEmpty());

        setup.close();
    }

    void completedTransferIsRecordedAndSurvivesRestart()
    {
        const QString sourcePath = m_sourceDir.filePath(QStringLiteral("note.txt"));
        {
            QFile file(sourcePath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(QByteArrayLiteral("contenu du transfert de test"));
            file.close();
        }

        // --- Session 1 : realise le transfert (avant "redemarrage") ---
        int recordedIncomingId = -1;
        {
            database::DatabaseManager dbManager(
                QStringLiteral("test_transfermanager_session1_%1").arg(QRandomGenerator::global()->generate()));
            QVERIFY(dbManager.open(m_dbPath));

            network::TransferService transferService;
            transferService.setReceiveDirectory(m_destDir.path());
            QVERIFY(transferService.start(23470));

            core::TransferManager manager(&dbManager);
            manager.setTransferService(&transferService);

            QSignalSpy recorded(&manager, &core::TransferManager::transferRecorded);
            QSignalSpy statusChanged(&manager, &core::TransferManager::transferStatusChanged);
            QSignalSpy completed(&transferService, &network::TransferService::transferCompleted);

            QVERIFY(manager.sendFile(QHostAddress::LocalHost, 23470, sourcePath, m_senderUuid, m_recipientUuid));

            // Deux transferCompleted attendus : le socket expediteur ET le
            // socket destinataire (TransferService envoie et recoit ici
            // via la meme instance, en boucle locale).
            QVERIFY(completed.wait(5000));
            if (completed.count() < 2) {
                QVERIFY(completed.wait(5000));
            }
            QCOMPARE(completed.count(), 2);

            // Laisse le temps aux deux transferStatusChanged(Completed)
            // de se propager (traitement asynchrone des deux sockets).
            QTRY_COMPARE(statusChanged.count(), 2);

            QCOMPARE(recorded.count(), 2); // un enregistrement sortant + un entrant
            for (const auto &args : statusChanged) {
                QCOMPARE(args.at(1).value<models::TransferStatus>(), models::TransferStatus::Completed);
            }

            const auto history = manager.userTransfers(m_recipientUuid);
            QVERIFY(!history.empty());
            for (const auto &t : history) {
                if (t.recipientUuid() == m_recipientUuid && t.senderUuid() == m_senderUuid) {
                    recordedIncomingId = t.id();
                }
            }
            QVERIFY(recordedIncomingId >= 0);

            const auto found = manager.transfer(recordedIncomingId);
            QVERIFY(found.has_value());
            QCOMPARE(found->status(), models::TransferStatus::Completed);
            QCOMPARE(found->fileName(), QStringLiteral("note.txt"));
            // Le chemin de destination (dossier de reception + nom de
            // fichier) n'est connu qu'a la fin du transfert : verifie qu'il
            // a bien ete renseigne en base (issue "ouvrir l'emplacement").
            QVERIFY(!found->filePath().isEmpty());
            QVERIFY(found->filePath().startsWith(m_destDir.path()));

            transferService.stop();
            dbManager.close();
        }
        // dbManager et transferService detruits ici : simule la fermeture
        // complete de l'application.

        // --- Session 2 : "redemarrage" de l'application ---
        {
            database::DatabaseManager dbManager(
                QStringLiteral("test_transfermanager_session2_%1").arg(QRandomGenerator::global()->generate()));
            QVERIFY(dbManager.open(m_dbPath));

            database::TransferRepository repoAfterRestart(dbManager.database());
            const auto reloaded = repoAfterRestart.findById(recordedIncomingId);
            QVERIFY(reloaded.has_value());
            QCOMPARE(reloaded->fileName(), QStringLiteral("note.txt"));
            QCOMPARE(reloaded->status(), models::TransferStatus::Completed);
            QCOMPARE(reloaded->senderUuid(), m_senderUuid);
            QCOMPARE(reloaded->recipientUuid(), m_recipientUuid);
            QVERIFY(!reloaded->filePath().isEmpty());

            const auto userHistory = repoAfterRestart.findByUser(m_recipientUuid);
            QVERIFY(!userHistory.empty());

            dbManager.close();
        }
    }

    void transferWithoutValidUserUuidsIsStillPersisted()
    {
        // Avant la migration #012, sender_id/recipient_id etaient NOT NULL
        // REFERENCES Users(id) : un id inconnu violait la contrainte de
        // cle etrangere et l'INSERT echouait silencieusement, privant
        // l'utilisateur de tout historique pour ce transfert. La migration
        // #017 a remplace ces colonnes par sender_uuid/recipient_uuid, sans
        // contrainte : le transfert doit toujours apparaitre dans
        // l'historique, avec un uuid "inconnu" represente par une chaine
        // vide (voir TransferRepository::transferFromQuery()).
        const QString sourcePath = m_sourceDir.filePath(QStringLiteral("anonymous.txt"));
        {
            QFile file(sourcePath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(QByteArrayLiteral("x"));
            file.close();
        }

        database::DatabaseManager dbManager(
            QStringLiteral("test_transfermanager_novalid_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(dbManager.open(m_dbPath));

        network::TransferService transferService;
        transferService.setReceiveDirectory(m_destDir.path());
        QVERIFY(transferService.start(23471));

        core::TransferManager manager(&dbManager);
        manager.setTransferService(&transferService);

        QSignalSpy completed(&transferService, &network::TransferService::transferCompleted);
        QVERIFY(manager.sendFile(QHostAddress::LocalHost, 23471, sourcePath, /*senderUuid=*/QString(), /*recipientUuid=*/QString()));
        QVERIFY(completed.wait(5000));
        if (completed.count() < 2) {
            QVERIFY(completed.wait(5000));
        }

        const auto history = manager.allTransfers();
        bool found = false;
        for (const auto &t : history) {
            if (t.fileName() == QStringLiteral("anonymous.txt")) {
                QVERIFY(t.senderUuid().isEmpty());
                QVERIFY(t.recipientUuid().isEmpty());
                found = true;
            }
        }
        QVERIFY(found);

        transferService.stop();
        dbManager.close();
    }

    void sendFile_usesKnownPeerMachineIdForOutgoingRecord()
    {
        // Reproduit le bug signale : sans DiscoveryService (ou si le pair
        // n'y figure pas/plus, ex. machine multi-interfaces), TransferManager
        // ne pouvait deviner peerMachineId pour un ENVOI qu'en comparant des
        // adresses IP -- resolution fragile qui echoue justement dans ce cas.
        // La reception, elle, connait toujours ce champ (en-tete reseau), si
        // bien qu'un meme correspondant pouvait finir dans deux dossiers/
        // tuiles distincts cote UI (regroupement par peerMachineId, voir
        // FileTransferView.qml::buildPeerGroups()). Verifie que le
        // peerMachineId connu par l'appelant (cf. TransferContext::sendFile(),
        // alimente par availableRecipients()) est applique a l'enregistrement
        // SORTANT meme sans DiscoveryService configure.
        const QString sourcePath = m_sourceDir.filePath(QStringLiteral("known-peer.txt"));
        {
            QFile file(sourcePath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(QByteArrayLiteral("y"));
            file.close();
        }

        database::DatabaseManager dbManager(
            QStringLiteral("test_transfermanager_knownpeer_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(dbManager.open(m_dbPath));

        network::TransferService transferService;
        transferService.setReceiveDirectory(m_destDir.path());
        QVERIFY(transferService.start(23472));

        core::TransferManager manager(&dbManager);
        manager.setTransferService(&transferService);
        // Volontairement pas de setDiscoveryService() : simule le cas ou le
        // pair n'est pas (ou plus) resolvable par adresse IP au moment ou
        // transferStarted() arrive.

        const QString knownPeerId = QStringLiteral("11111111-2222-3333-4444-555555555555");

        QSignalSpy completed(&transferService, &network::TransferService::transferCompleted);
        QVERIFY(manager.sendFile(QHostAddress::LocalHost, 23472, sourcePath, m_senderUuid, m_recipientUuid,
                                  knownPeerId));
        QVERIFY(completed.wait(5000));
        if (completed.count() < 2) {
            QVERIFY(completed.wait(5000));
        }

        const auto history = manager.allTransfers();
        bool foundOutgoing = false;
        for (const auto &t : history) {
            if (t.fileName() == QStringLiteral("known-peer.txt") && t.filePath() == sourcePath) {
                QCOMPARE(t.peerMachineId(), knownPeerId);
                foundOutgoing = true;
            }
        }
        QVERIFY(foundOutgoing);

        transferService.stop();
        dbManager.close();
    }
    void resolvePeerName_usesPersistedCacheEvenWithoutDiscoveryService()
    {
        // Reproduit le bug signale : le dossier physique "CollabLAN
        // Transfers/<nom>/" et la colonne peer_name en base etaient
        // resolus a CHAQUE transfert via DiscoveryService::peers(), dont
        // le champ "name" est en realite le nom d'utilisateur *actuellement*
        // connecte sur le poste distant (cf. Application::setLocalName()
        // sur authenticationChanged). Deux transferts successifs du meme
        // correspondant (meme peerMachineId) pouvaient donc atterrir sous
        // deux noms differents (reconnexion sous un autre compte, pair
        // momentanement absent de la decouverte...). On verifie ici que,
        // des lors qu'un nom a deja ete resolu une fois pour un
        // peerMachineId donne (et fige dans la table Settings, cle
        // "peer_folder_name:<uuid>"), il est reutilise tel quel -- meme
        // sans aucun DiscoveryService configure, ce qui est justement le
        // cas le plus defavorable pour l'ancien code (resolvePeerName()
        // retournait alors systematiquement une chaine vide).
        const QString peerMachineId = QStringLiteral("99999999-8888-7777-6666-555555555555");

        database::DatabaseManager dbManager(
            QStringLiteral("test_transfermanager_peername_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(dbManager.open(m_dbPath));

        // Fige le nom comme le ferait un premier transfert reussi (via
        // Application::setupTransferPeerFolders() ou TransferManager::
        // resolvePeerName() cote reel) : on le pre-remplit directement ici
        // pour isoler le comportement de lecture du cache, independamment
        // de DiscoveryService.
        {
            database::SettingsRepository settingsRepository(dbManager.database());
            QVERIFY(settingsRepository.save(models::Settings(
                QStringLiteral("peer_folder_name:%1").arg(peerMachineId),
                QStringLiteral("Marie (portable)"))));
        }

        const QString sourcePath = m_sourceDir.filePath(QStringLiteral("cached-peer.txt"));
        {
            QFile file(sourcePath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(QByteArrayLiteral("z"));
            file.close();
        }

        network::TransferService transferService;
        transferService.setReceiveDirectory(m_destDir.path());
        // Porte le peerMachineId dans l'en-tete cote emission, exactement
        // comme le ferait Application::initialize() en usage reel (voir
        // TransferManager::onNetworkTransferStarted(), branche reception).
        transferService.setLocalMachineId(peerMachineId);
        QVERIFY(transferService.start(23473));

        core::TransferManager manager(&dbManager);
        manager.setTransferService(&transferService);
        // Volontairement pas de setDiscoveryService() : le seul moyen pour
        // resolvePeerName() de retourner un nom non vide est donc le cache
        // Settings pre-rempli ci-dessus.

        QSignalSpy completed(&transferService, &network::TransferService::transferCompleted);
        QVERIFY(manager.sendFile(QHostAddress::LocalHost, 23473, sourcePath, m_senderUuid, m_recipientUuid));
        QVERIFY(completed.wait(5000));
        if (completed.count() < 2) {
            QVERIFY(completed.wait(5000));
        }

        const auto history = manager.allTransfers();
        bool foundIncoming = false;
        for (const auto &t : history) {
            if (t.fileName() == QStringLiteral("cached-peer.txt") && t.peerMachineId() == peerMachineId) {
                QCOMPARE(t.peerName(), QStringLiteral("Marie (portable)"));
                foundIncoming = true;
            }
        }
        QVERIFY(foundIncoming);

        transferService.stop();
        dbManager.close();
    }
};

QTEST_MAIN(TestTransferManager)
#include "test_transfermanager.moc"
