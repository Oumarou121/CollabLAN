#include "SyncEngine.h"

#include "database/DatabaseManager.h"

namespace core::sync {

SyncEngine::SyncEngine(core::SharedFolderManager *folderManager,
                        database::DatabaseManager *dbManager,
                        QString machineId,
                        QObject *parent)
    : QObject(parent)
    , m_folderManager(folderManager)
    , m_operationRepository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_machineId(std::move(machineId))
{
    connect(&m_watcher, &FolderWatcher::changesDetected, this, &SyncEngine::onWatcherChangesDetected);

    if (m_folderManager) {
        connect(m_folderManager, &core::SharedFolderManager::folderCreated, this, &SyncEngine::onFolderCreated);
        connect(m_folderManager, &core::SharedFolderManager::folderRemoved, this, &SyncEngine::onFolderRemoved);
    }
}

SyncEngine::~SyncEngine() = default;

void SyncEngine::start()
{
    if (!m_folderManager) {
        return;
    }
    for (const models::SharedFolder &folder : m_folderManager->getFolders()) {
        watchFolder(folder.id());
    }
}

void SyncEngine::watchFolder(qint64 folderId)
{
    if (!m_folderManager) {
        return;
    }
    const auto folder = m_folderManager->getFolder(folderId);
    if (!folder.has_value()) {
        return;
    }
    // Voir le commentaire dans onFolderCreated() : un dossier distant n'a
    // pas de local_path reel a surveiller.
    if (!folder->isLocalOrigin()) {
        return;
    }

    QStringList relativePaths;
    for (const models::SharedFile &file : m_folderManager->getFiles(folderId)) {
        relativePaths.append(file.relativePath());
    }
    m_watcher.watchFolder(folderId, folder->localPath(), relativePaths);
}

void SyncEngine::onFolderCreated(const models::SharedFolder &folder)
{
    // Un dossier distant (replique depuis un autre poste, cf. migration 020
    // et SharedFolderManager::registerRemoteFolder()) n'a pas de contenu
    // reel sur CE disque : son local_path est une chaine vide. Tenter de le
    // surveiller (QFileSystemWatcher::addPath("")) produit l'avertissement
    // Qt "Empty filename passed to function" et ne sert a rien -- seul le
    // proprietaire (origine locale) doit etre surveille pour detecter les
    // changements a diffuser.
    if (!folder.isLocalOrigin()) {
        return;
    }

    // Indexer le contenu initial du dossier pour que les fichiers soient
    // disponibles pour le resync (folder_resync_request)
    reindexFolder(folder.id());
}

void SyncEngine::onFolderRemoved(qint64 folderId)
{
    m_watcher.unwatchFolder(folderId);
}

void SyncEngine::onWatcherChangesDetected(qint64 folderId)
{
    reindexFolder(folderId);
}

int SyncEngine::reindexFolder(qint64 folderId)
{
    if (!m_folderManager) {
        return -1;
    }

    const auto folder = m_folderManager->getFolder(folderId);
    if (!folder.has_value()) {
        return -1;
    }

    // Un dossier distant (localPath vide) ne peut pas être réindexé
    // car il n'y a pas de contenu local à scanner.
    if (folder->localPath().isEmpty()) {
        qDebug() << "[SyncEngine] reindexFolder ignoré : dossier distant sans localPath" << folder->name();
        return 0;
    }

    const auto changes = m_folderManager->shareFolder(folderId);
    if (!changes.has_value()) {
        return -1;
    }

    int persistedCount = 0;
    for (const models::SharedFileChange &change : *changes) {
        models::FileSyncOperation operation;
        operation.setType(change.type());
        operation.setFileId(change.file().id());
        operation.setOldRelativePath(change.oldRelativePath());
        operation.setVersion(change.file().version());
        operation.setMachineId(m_machineId);

        if (m_operationRepository.insert(operation).has_value()) {
            ++persistedCount;
        }
    }

    // Rafraichit la surveillance (nouveaux fichiers a surveiller pour
    // leurs futures modifications de contenu, fichiers disparus a ne
    // plus surveiller) ; watchFolder() est appele en filet de securite
    // si le dossier n'etait pas encore surveille (ex: tout premier
    // reindexFolder() suivant onFolderCreated()).
    if (const auto folder = m_folderManager->getFolder(folderId); folder.has_value()) {
        QStringList relativePaths;
        for (const models::SharedFile &file : m_folderManager->getFiles(folderId)) {
            relativePaths.append(file.relativePath());
        }
        m_watcher.refreshWatchedFiles(folderId, relativePaths);
    }

    emit folderReindexed(folderId, persistedCount);
    return persistedCount;
}

QVector<models::FileSyncOperation> SyncEngine::historyForFolder(qint64 folderId, int limit) const
{
    return m_operationRepository.getByFolderId(folderId, limit);
}

} // namespace core::sync