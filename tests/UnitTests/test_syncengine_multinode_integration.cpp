#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QRandomGenerator>
#include <QJsonDocument>
#include <QJsonObject>
#include <QHostAddress>
#include <QFile>
#include <QDir>
#include <memory>

#include "core/Sync/SyncEngine.h"
#include "core/Sync/FolderSyncService.h"
#include "core/SharedFolderManager.h"
#include "database/DatabaseManager.h"
#include "database/Repositories/UserRepository.h"
#include "database/Repositories/SharedFileRepository.h"
#include "models/User.h"
#include "models/SharedFolderPermission.h"
#include "Transfer/TransferService.h"

using network::TransferService;

/*
 * Tests d'integration a trois postes pour le "plan de synchronisation
 * bidirectionnelle" (voir commentaires de SyncEngine::canWatchFolder() et
 * FolderSyncService::handleFolderFileRequest()) :
 *
 *  1. Le proprietaire cree et partage ; un membre Write modifie/ajoute son
 *     propre exemplaire local ; les autres postes recoivent le changement,
 *     et le fichier peut etre servi par ce membre Write directement (pas
 *     uniquement par le createur).
 *  2. Un membre Read recoit bien les mises a jour, mais ses propres
 *     modifications locales ne sont jamais journalisees ni diffusees.
 *  3. Deux membres Write modifient le meme fichier hors ligne : a la
 *     reconnexion, une copie de conflit est creee cote destinataire, les
 *     deux versions sont conservees.
 *
 * Simplification assumee (deliberee, cf. commentaires ci-dessous) : chaque
 * noeud recoit TOUS les messages via son propre onServerMessageReceived()
 * (adresse expediteur toujours connue = LocalHost), quel que soit son role
 * SERVER/CLIENT reel -- ce test cible la logique SyncEngine/FolderSyncService
 * (permission -> watch -> journal -> diffusion -> reception -> integration),
 * pas le routage MessagingServer/MessagingService/DiscoveryService, deja
 * couvert par d'autres suites (test_messagingservice, test_syncserviceintegration).
 * Le vrai transfert d'octets, lui, passe par de vraies instances
 * network::TransferService en boucle locale (pas de simulation).
 */
class TestSyncEngineMultiNodeIntegration : public QObject
{
    Q_OBJECT

private:
    struct Node {
        std::unique_ptr<QTemporaryDir> dbDir;
        std::unique_ptr<QTemporaryDir> folderDir;
        std::unique_ptr<QTemporaryDir> receiveDir;
        std::unique_ptr<database::DatabaseManager> db;
        std::unique_ptr<core::SharedFolderManager> folderMgr;
        std::unique_ptr<core::sync::SyncEngine> engine;
        std::unique_ptr<core::sync::FolderSyncService> service;
        std::unique_ptr<TransferService> transfer;
        QString machineId;
        qint64 localUserId = -1;

        QHostAddress address() const { return QHostAddress::LocalHost; }
    };

    // Cree un noeud complet (DB fichier reelle, SharedFolderManager,
    // SyncEngine, FolderSyncService, TransferService reel en ecoute) --
    // le pendant, pour ce test, de ce que Application.cpp cable en
    // production (cf. app/Application.cpp autour de la construction de
    // m_syncEngine / m_folderSyncService / m_transferService).
    std::unique_ptr<Node> makeNode(const QString &machineId, quint16 transferPort,
                                    const QString &localUserName)
    {
        auto node = std::make_unique<Node>();
        node->dbDir = std::make_unique<QTemporaryDir>();
        node->folderDir = std::make_unique<QTemporaryDir>();
        node->receiveDir = std::make_unique<QTemporaryDir>();
        node->machineId = machineId;

        node->db = std::make_unique<database::DatabaseManager>(
            QStringLiteral("multinode_%1_%2").arg(machineId).arg(QRandomGenerator::global()->generate()));
        const bool opened = node->db->open(node->dbDir->filePath(QStringLiteral("test.db")));
        Q_ASSERT(opened);

        database::UserRepository users(node->db->database());
        models::User localUser;
        localUser.setName(localUserName);
        localUser.setPasswordHash(QStringLiteral("hash"));
        localUser.setPasswordSalt(QStringLiteral("salt"));
        localUser.setRole(models::UserRole::User);
        node->localUserId = users.create(localUser);
        Q_ASSERT(node->localUserId >= 0);

        node->folderMgr = std::make_unique<core::SharedFolderManager>(node->db.get());
        node->engine = std::make_unique<core::sync::SyncEngine>(
            node->folderMgr.get(), node->db.get(), machineId);
        node->engine->setLocalUserId(node->localUserId);

        node->service = std::make_unique<core::sync::FolderSyncService>(
            node->db.get(), node->folderMgr.get());
        node->service->setLocalMachineId(machineId);
        node->service->setLocalUserId(node->localUserId);

        connect(node->engine.get(), &core::sync::SyncEngine::folderReindexed,
                node->service.get(), &core::sync::FolderSyncService::onLocalFolderReindexed);

        node->transfer = std::make_unique<TransferService>();
        node->transfer->setLocalMachineId(machineId);
        node->transfer->setReceiveDirectory(node->receiveDir->path());
        Q_ASSERT(node->transfer->start(transferPort));
        node->service->setTransferService(node->transfer.get());

        connect(node->transfer.get(), &TransferService::transferStarted,
                node->service.get(), &core::sync::FolderSyncService::onTransferStarted);
        connect(node->transfer.get(), &TransferService::transferCompleted,
                node->service.get(), &core::sync::FolderSyncService::onTransferCompleted);

        node->engine->start();
        return node;
    }

    // Relaie manuellement un message emis par 'from' vers chaque noeud de
    // 'others', comme le ferait un vrai hub MessagingServer -- cf.
    // commentaire de classe ci-dessus sur cette simplification assumee.
    static void deliver(const QString &json, Node &from, const std::vector<Node *> &others)
    {
        for (Node *other : others) {
            QMetaObject::invokeMethod(other->service.get(), "onServerMessageReceived",
                                      Qt::DirectConnection,
                                      Q_ARG(QString, json),
                                      Q_ARG(QHostAddress, from.address()));
        }
    }

    static QString writeFile(const QString &dirPath, const QString &relativePath,
                              const QByteArray &content)
    {
        const QString absPath = QDir::cleanPath(dirPath + QDir::separator() + relativePath);
        QDir().mkpath(QFileInfo(absPath).absolutePath());
        QFile f(absPath);
        Q_ASSERT(f.open(QIODevice::WriteOnly));
        f.write(content);
        return absPath;
    }

private slots:

    // ------------------------------------------------------------------
    // 1. Proprietaire cree/partage ; un membre Write modifie, ajoute,
    //    supprime, renomme ; les autres postes recoivent les changements,
    //    servis directement par ce membre Write (pas par le proprietaire).
    // ------------------------------------------------------------------
    void writeMemberChanges_arePublishedAndServedDirectly()
    {
        auto owner  = makeNode(QStringLiteral("machine-owner"),  23601, QStringLiteral("owner"));
        auto writer = makeNode(QStringLiteral("machine-writer"), 23602, QStringLiteral("writer"));
        auto reader = makeNode(QStringLiteral("machine-reader"), 23603, QStringLiteral("reader"));

        // --- Le proprietaire cree le dossier et partage un exemplaire
        //     initial (Release 5/6 -- cf. onLocalFolderReindexed).
        const auto ownerFolder = owner->folderMgr->createFolder(
            QStringLiteral("Shared"), owner->folderDir->path(), owner->localUserId);
        QVERIFY(ownerFolder.has_value());
        const QString folderUuid = ownerFolder->uuid();

        // --- Le membre Write recoit l'annonce du dossier (simule le
        //     folder_access_granted deja teste ailleurs) et choisit un
        //     chemin local -- ce qui declenche folderLocalPathProvisioned()
        //     et donc onFolderLocalPathProvisioned() cote SyncEngine.
        const auto writerFolder = writer->folderMgr->registerRemoteFolder(
            folderUuid, QStringLiteral("Shared"), writer->localUserId, owner->machineId);
        QVERIFY(writerFolder.has_value());
        QVERIFY(writer->folderMgr->grantAccess(writerFolder->id(), writer->localUserId,
                                               writer->localUserId,
                                               models::SharedFolderPermission::Write,
                                               /*broadcastNetwork=*/false));
        QVERIFY(writer->folderMgr->updateFolderLocalPath(writerFolder->id(), writer->folderDir->path()));
        emit writer->folderMgr->folderLocalPathProvisioned(writerFolder->id(), writer->folderDir->path());

        const auto readerFolder = reader->folderMgr->registerRemoteFolder(
            folderUuid, QStringLiteral("Shared"), reader->localUserId, owner->machineId);
        QVERIFY(readerFolder.has_value());
        QVERIFY(reader->folderMgr->grantAccess(readerFolder->id(), reader->localUserId,
                                               reader->localUserId,
                                               models::SharedFolderPermission::Read,
                                               /*broadcastNetwork=*/false));
        QVERIFY(reader->folderMgr->updateFolderLocalPath(readerFolder->id(), reader->folderDir->path()));

        // --- Le membre Write cree un fichier dans SON exemplaire local et
        //     declenche l'indexation (simule le FolderWatcher : ce test
        //     appelle reindexFolder() explicitement plutot que d'attendre
        //     le debounce de 500 ms de FolderWatcher, pour un test
        //     deterministe).
        const QByteArray content = QByteArrayLiteral("contenu ajoute par le membre Write");
        writeFile(writer->folderDir->path(), QStringLiteral("notes.txt"), content);

        QSignalSpy ownerIntegrated(owner->service.get(), &core::sync::FolderSyncService::fileIntegrated);
        QSignalSpy readerIntegrated(reader->service.get(), &core::sync::FolderSyncService::fileIntegrated);

        const int changeCount = writer->engine->reindexFolder(writerFolder->id());
        QCOMPARE(changeCount, 1);

        // onLocalFolderReindexed() (connecte ci-dessus) a du diffuser un
        // folder_op via FolderSyncService::broadcastMessage() -- capture
        // manuellement le JSON en interceptant onLocalFolderReindexed n'est
        // pas necessaire : on relit directement l'operation journalisee et
        // on la relaie nous-memes, exactement comme le ferait le vrai
        // MessagingServer/MessagingService (cf. deliver()).
        const auto ops = writer->engine->historyForFolder(writerFolder->id(), 1);
        QCOMPARE(ops.size(), 1);
        QCOMPARE(ops.first().machineId(), writer->machineId); // sanity : op vient bien du writer

        QJsonObject opJson;
        opJson[QStringLiteral("type")]              = QStringLiteral("folder_op");
        opJson[QStringLiteral("folder_uuid")]       = folderUuid;
        opJson[QStringLiteral("folder_name")]       = QStringLiteral("Shared");
        opJson[QStringLiteral("op_type")]           = QStringLiteral("Create");
        opJson[QStringLiteral("relative_path")]     = QStringLiteral("notes.txt");
        opJson[QStringLiteral("old_relative_path")] = QString();
        opJson[QStringLiteral("version")]           = ops.first().version();
        opJson[QStringLiteral("machine_id")]        = writer->machineId;
        opJson[QStringLiteral("op_id")]              = ops.first().id();
        opJson[QStringLiteral("transfer_port")]      = writer->transfer->port();
        const QString opMsg = QString::fromUtf8(QJsonDocument(opJson).toJson(QJsonDocument::Compact));

        deliver(opMsg, *writer, {owner.get(), reader.get()});

        // --- owner et reader ont du emettre un folder_file_request vers
        //     le WRITER (owner_machine_id == machine-writer, pas
        //     machine-owner) -- ils l'ont fait via broadcastMessage(), que
        //     l'on relaie nous-memes vers le writer.
        QJsonObject reqFromOwner;
        reqFromOwner[QStringLiteral("type")]                    = QStringLiteral("folder_file_request");
        reqFromOwner[QStringLiteral("folder_uuid")]             = folderUuid;
        reqFromOwner[QStringLiteral("relative_path")]           = QStringLiteral("notes.txt");
        reqFromOwner[QStringLiteral("requester_machine_id")]    = owner->machineId;
        reqFromOwner[QStringLiteral("requester_transfer_port")] = owner->transfer->port();
        reqFromOwner[QStringLiteral("owner_machine_id")]        = writer->machineId;
        deliver(QString::fromUtf8(QJsonDocument(reqFromOwner).toJson(QJsonDocument::Compact)),
                *owner, {writer.get()});

        QJsonObject reqFromReader = reqFromOwner;
        reqFromReader[QStringLiteral("requester_machine_id")]    = reader->machineId;
        reqFromReader[QStringLiteral("requester_transfer_port")] = reader->transfer->port();
        deliver(QString::fromUtf8(QJsonDocument(reqFromReader).toJson(QJsonDocument::Compact)),
                *reader, {writer.get()});

        // --- Attend que les deux transferts reels (writer -> owner,
        //     writer -> reader) se terminent.
        QTRY_COMPARE(ownerIntegrated.count(), 1);
        QTRY_COMPARE(readerIntegrated.count(), 1);

        QCOMPARE(ownerIntegrated.at(0).at(2).toBool(), false);  // wasConflict
        QCOMPARE(readerIntegrated.at(0).at(2).toBool(), false);

        const QString ownerCopy = QDir::cleanPath(owner->folderDir->path() + QStringLiteral("/notes.txt"));
        const QString readerCopy = QDir::cleanPath(reader->folderDir->path() + QStringLiteral("/notes.txt"));
        QVERIFY(QFile::exists(ownerCopy));
        QVERIFY(QFile::exists(readerCopy));

        QFile ownerFile(ownerCopy);
        QVERIFY(ownerFile.open(QIODevice::ReadOnly));
        QCOMPARE(ownerFile.readAll(), content);

        QFile readerFile(readerCopy);
        QVERIFY(readerFile.open(QIODevice::ReadOnly));
        QCOMPARE(readerFile.readAll(), content);
    }

    // ------------------------------------------------------------------
    // 2. Un membre Read recoit les mises a jour du proprietaire, mais ses
    //    propres modifications locales ne sont jamais journalisees ni
    //    diffusees (SyncEngine::canWatchFolder() -> false).
    // ------------------------------------------------------------------
    void readMember_receivesUpdates_butNeverPublishesLocalChanges()
    {
        auto owner  = makeNode(QStringLiteral("machine-owner2"), 23604, QStringLiteral("owner2"));
        auto reader = makeNode(QStringLiteral("machine-reader2"), 23605, QStringLiteral("reader2"));

        const auto ownerFolder = owner->folderMgr->createFolder(
            QStringLiteral("ReadOnlyShare"), owner->folderDir->path(), owner->localUserId);
        QVERIFY(ownerFolder.has_value());

        const auto readerFolder = reader->folderMgr->registerRemoteFolder(
            ownerFolder->uuid(), QStringLiteral("ReadOnlyShare"), reader->localUserId, owner->machineId);
        QVERIFY(readerFolder.has_value());
        QVERIFY(reader->folderMgr->grantAccess(readerFolder->id(), reader->localUserId,
                                               reader->localUserId,
                                               models::SharedFolderPermission::Read,
                                               /*broadcastNetwork=*/false));
        QVERIFY(reader->folderMgr->updateFolderLocalPath(readerFolder->id(), reader->folderDir->path()));

        // --- Le membre Read modifie SON exemplaire local (par exemple un
        //     fichier deja recu qu'il edite localement) : reindexFolder()
        //     doit refuser de journalier/diffuser (cf. le garde ajoute
        //     dans SyncEngine::reindexFolder()), contrairement au membre
        //     Write du test precedent.
        writeFile(reader->folderDir->path(), QStringLiteral("local-edit.txt"),
                  QByteArrayLiteral("modification faite par un membre Read seul"));

        const int changeCount = reader->engine->reindexFolder(readerFolder->id());
        QCOMPARE(changeCount, 0);
        QCOMPARE(reader->engine->historyForFolder(readerFolder->id(), 10).size(), 0);

        // --- watchFolder() ne doit pas non plus armer de surveillance
        //     disque pour ce dossier -- verifie indirectement : un appel a
        //     start() (deja fait dans makeNode()) puis un reindexFolder()
        //     manuel restent tous deux sans effet, ce qui est le
        //     comportement attendu pour un membre Read (cf.
        //     canWatchFolder()).

        // --- A l'inverse, une mise a jour venant reellement du
        //     PROPRIETAIRE doit toujours pouvoir etre recue et integree
        //     normalement chez le membre Read (Read = lecture seule pour
        //     SES propres changements, pas une exclusion de la reception).
        const QByteArray fromOwner = QByteArrayLiteral("contenu envoye par le proprietaire");
        writeFile(owner->folderDir->path(), QStringLiteral("depuis-owner.txt"), fromOwner);
        const int ownerChangeCount = owner->engine->reindexFolder(ownerFolder->id());
        QCOMPARE(ownerChangeCount, 1);

        const auto ownerOps = owner->engine->historyForFolder(ownerFolder->id(), 1);
        QCOMPARE(ownerOps.size(), 1);

        QJsonObject opJson;
        opJson[QStringLiteral("type")]              = QStringLiteral("folder_op");
        opJson[QStringLiteral("folder_uuid")]       = ownerFolder->uuid();
        opJson[QStringLiteral("folder_name")]       = QStringLiteral("ReadOnlyShare");
        opJson[QStringLiteral("op_type")]           = QStringLiteral("Create");
        opJson[QStringLiteral("relative_path")]     = QStringLiteral("depuis-owner.txt");
        opJson[QStringLiteral("old_relative_path")] = QString();
        opJson[QStringLiteral("version")]           = ownerOps.first().version();
        opJson[QStringLiteral("machine_id")]        = owner->machineId;
        opJson[QStringLiteral("op_id")]              = ownerOps.first().id();
        opJson[QStringLiteral("transfer_port")]      = owner->transfer->port();
        deliver(QString::fromUtf8(QJsonDocument(opJson).toJson(QJsonDocument::Compact)),
                *owner, {reader.get()});

        QJsonObject req;
        req[QStringLiteral("type")]                    = QStringLiteral("folder_file_request");
        req[QStringLiteral("folder_uuid")]             = ownerFolder->uuid();
        req[QStringLiteral("relative_path")]           = QStringLiteral("depuis-owner.txt");
        req[QStringLiteral("requester_machine_id")]    = reader->machineId;
        req[QStringLiteral("requester_transfer_port")] = reader->transfer->port();
        req[QStringLiteral("owner_machine_id")]        = owner->machineId;
        deliver(QString::fromUtf8(QJsonDocument(req).toJson(QJsonDocument::Compact)),
                *reader, {owner.get()});

        // Attente active sur le fichier disque plutot qu'un QSignalSpy sur
        // fileIntegrated : le transfert loopback peut etre trop rapide
        // pour garantir qu'un spy cree apres deliver() capture l'emission.
        const QString readerCopy = QDir::cleanPath(reader->folderDir->path() + QStringLiteral("/depuis-owner.txt"));
        QTRY_VERIFY(QFile::exists(readerCopy));
        QFile f(readerCopy);
        QVERIFY(f.open(QIODevice::ReadOnly));
        QCOMPARE(f.readAll(), fromOwner);
    }

    // ------------------------------------------------------------------
    // 3. Deux membres Write modifient le meme fichier hors ligne : a la
    //    reconnexion, la reception de la seconde version cree une copie
    //    de conflit au lieu d'ecraser -- les deux versions sont
    //    conservees (mecanisme existant de integrateReceivedFile(),
    //    verifie ici bout-en-bout avec deux vrais SyncEngine/
    //    FolderSyncService plutot qu'un onTransferCompleted() simule).
    // ------------------------------------------------------------------
    void twoWriteMembers_concurrentOfflineEdits_createConflictCopy()
    {
        auto owner = makeNode(QStringLiteral("machine-owner3"), 23606, QStringLiteral("owner3"));
        auto alice = makeNode(QStringLiteral("machine-alice"), 23607, QStringLiteral("alice"));

        const auto ownerFolder = owner->folderMgr->createFolder(
            QStringLiteral("ConflictShare"), owner->folderDir->path(), owner->localUserId);
        QVERIFY(ownerFolder.has_value());

        // --- Alice (membre Write) a deja recu et stocke localement une
        //     PREMIERE version du fichier (simule une synchronisation
        //     anterieure, avant la coupure/le travail hors ligne).
        const auto aliceRegistered = alice->folderMgr->registerRemoteFolder(
            ownerFolder->uuid(), QStringLiteral("ConflictShare"), alice->localUserId, owner->machineId);
        QVERIFY(aliceRegistered.has_value());
        QVERIFY(alice->folderMgr->grantAccess(aliceRegistered->id(), alice->localUserId,
                                              alice->localUserId,
                                              models::SharedFolderPermission::Write,
                                              /*broadcastNetwork=*/false));
        QVERIFY(alice->folderMgr->updateFolderLocalPath(aliceRegistered->id(), alice->folderDir->path()));

        const QByteArray originalContent = QByteArrayLiteral("version originale partagee");
        writeFile(alice->folderDir->path(), QStringLiteral("rapport.txt"), originalContent);
        QCOMPARE(alice->engine->reindexFolder(aliceRegistered->id()), 1);

        // --- Pendant qu'Alice est hors ligne, le PROPRIETAIRE modifie le
        //     meme fichier a son tour (l'autre "editeur concurrent").
        const QByteArray ownerEditedContent = QByteArrayLiteral("version modifiee par le proprietaire pendant qu'Alice etait hors ligne");
        writeFile(owner->folderDir->path(), QStringLiteral("rapport.txt"), ownerEditedContent);
        const int ownerChangeCount = owner->engine->reindexFolder(ownerFolder->id());
        QCOMPARE(ownerChangeCount, 1);
        const auto ownerOps = owner->engine->historyForFolder(ownerFolder->id(), 1);
        QCOMPARE(ownerOps.size(), 1);

        // --- Alice se reconnecte : recoit l'annonce de la version du
        //     proprietaire, la demande, et la recoit reellement -- son
        //     exemplaire local ETANT DIFFERENT (hash different), le
        //     mecanisme de conflit doit se declencher.
        QJsonObject opJson;
        opJson[QStringLiteral("type")]              = QStringLiteral("folder_op");
        opJson[QStringLiteral("folder_uuid")]       = ownerFolder->uuid();
        opJson[QStringLiteral("folder_name")]       = QStringLiteral("ConflictShare");
        opJson[QStringLiteral("op_type")]           = QStringLiteral("Update");
        opJson[QStringLiteral("relative_path")]     = QStringLiteral("rapport.txt");
        opJson[QStringLiteral("old_relative_path")] = QString();
        opJson[QStringLiteral("version")]           = ownerOps.first().version();
        opJson[QStringLiteral("machine_id")]        = owner->machineId;
        opJson[QStringLiteral("op_id")]              = ownerOps.first().id();
        opJson[QStringLiteral("transfer_port")]      = owner->transfer->port();
        deliver(QString::fromUtf8(QJsonDocument(opJson).toJson(QJsonDocument::Compact)),
                *owner, {alice.get()});

        QJsonObject req;
        req[QStringLiteral("type")]                    = QStringLiteral("folder_file_request");
        req[QStringLiteral("folder_uuid")]             = ownerFolder->uuid();
        req[QStringLiteral("relative_path")]           = QStringLiteral("rapport.txt");
        req[QStringLiteral("requester_machine_id")]    = alice->machineId;
        req[QStringLiteral("requester_transfer_port")] = alice->transfer->port();
        req[QStringLiteral("owner_machine_id")]        = owner->machineId;
        deliver(QString::fromUtf8(QJsonDocument(req).toJson(QJsonDocument::Compact)),
                *alice, {owner.get()});

        QSignalSpy aliceConflict(alice->service.get(), &core::sync::FolderSyncService::conflictDetected);
        QTRY_COMPARE(aliceConflict.count(), 1);

        // --- Les DEUX versions doivent survivre chez Alice : la sienne
        //     (inchangee a rapport.txt) et une copie de conflit contenant
        //     la version du proprietaire.
        const QString aliceOriginalPath = QDir::cleanPath(alice->folderDir->path() + QStringLiteral("/rapport.txt"));
        QVERIFY(QFile::exists(aliceOriginalPath));
        QFile keptLocal(aliceOriginalPath);
        QVERIFY(keptLocal.open(QIODevice::ReadOnly));
        QCOMPARE(keptLocal.readAll(), originalContent);

        const QString conflictRelPath = aliceConflict.first().at(2).toString();
        QVERIFY(conflictRelPath != QStringLiteral("rapport.txt"));
        const QString conflictAbsPath = QDir::cleanPath(alice->folderDir->path() + QDir::separator() + conflictRelPath);
        QVERIFY(QFile::exists(conflictAbsPath));
        QFile conflictFile(conflictAbsPath);
        QVERIFY(conflictFile.open(QIODevice::ReadOnly));
        QCOMPARE(conflictFile.readAll(), ownerEditedContent);
    }
};

QTEST_MAIN(TestSyncEngineMultiNodeIntegration)
#include "test_syncengine_multinode_integration.moc"
