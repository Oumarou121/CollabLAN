#ifndef CORE_SYNCENGINE_H
#define CORE_SYNCENGINE_H

#include <QHash>
#include <QObject>
#include <QString>

#include "database/Repositories/SharedFileRepository.h"
#include "database/Repositories/SyncOperationRepository.h"
#include "models/SharedFolder.h"
#include "models/SyncOperation.h"
#include "services/FolderWatcher.h"

namespace database {
class DatabaseManager;
}

namespace core {

/**
 * @brief Coeur de la synchronisation des dossiers partages (Phase 4) :
 * relie la surveillance disque (services::FolderWatcher) a la base de
 * donnees (SharedFileRepository / SyncOperationRepository) et expose des
 * signaux consommes par la couche reseau (network::SyncNetworkService),
 * brancheS depuis Application. SyncEngine ne fait lui-meme aucun appel
 * reseau : il reste testable independamment.
 *
 * Flux local -> reseau : FolderWatcher detecte un changement -> SyncEngine
 * met a jour SharedFiles + insere un SyncOperation -> emet
 * localChangeReady(), qu'Application relie a
 * SyncNetworkService::broadcast*().
 *
 * Flux reseau -> local : Application relie
 * SyncNetworkService::fileInfoReceived/deleteFileReceived/... aux
 * methodes applyRemote*() de SyncEngine, qui statuent via
 * ConflictResolver puis mettent a jour la base (et, pour applyRemoteFile,
 * le contenu recu par FileTransferService).
 */
class SyncEngine : public QObject {
    Q_OBJECT

public:
    explicit SyncEngine(database::DatabaseManager *databaseManager, QString localMachineId, QObject *parent = nullptr);
    ~SyncEngine() override;

    // Demarre la surveillance disque d'un dossier partage actif.
    void attachFolder(const models::SharedFolder &folder);
    void detachFolder(int folderId);
    bool isAttached(int folderId) const;

    // --- Application de changements recus du reseau ---------------------

    // Enregistre les metadonnees d'un fichier distant (recues via
    // FILE_INFO) : detecte un eventuel conflit (core::ConflictResolver) et
    // met a jour la base. N'ecrit rien sur le disque local -- c'est le
    // role de network::TransferService une fois le contenu recu.
    void applyRemoteFileInfo(int folderId, const QString &relativePath, const QString &hash, qint64 size, int remoteVersion, const QString &remoteMachineLabel);

    void applyRemoteDelete(int folderId, const QString &relativePath, int remoteVersion);
    void applyRemoteRename(int folderId, const QString &oldRelativePath, const QString &newRelativePath, int remoteVersion);

signals:
    // Emis apres qu'un changement local a ete persiste, pour diffusion
    // reseau immediate (Phase 7).
    void localFileChanged(int folderId, const QString &folderName, const QString &relativePath, const QString &hash, qint64 size, int version);
    void localFileDeleted(int folderId, const QString &folderName, const QString &relativePath, int version);

    // Emis quand un conflit a ete detecte et resolu par renommage de la
    // copie locale (Phase 9) : utile pour notifier l'utilisateur.
    void conflictDetected(int folderId, const QString &relativePath, const QString &renamedTo);

private:
    struct WatchedFolder {
        models::SharedFolder folder;
        services::FolderWatcher *watcher = nullptr;
    };

    void onLocalFileCreatedOrChanged(int folderId, const QString &relativePath, models::SyncOperationType type);
    void onLocalFileDeleted(int folderId, const QString &relativePath);
    void recordOperation(int fileId, models::SyncOperationType type, int version);

    database::DatabaseManager *m_databaseManager;
    QString m_localMachineId;
    database::SharedFileRepository m_fileRepository;
    database::SyncOperationRepository m_operationRepository;
    QHash<int, WatchedFolder> m_watchedFolders; // cle = folderId
};

} // namespace core

#endif // CORE_SYNCENGINE_H
