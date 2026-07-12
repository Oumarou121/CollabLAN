#include "SyncEngine.h"

#include <QDir>
#include <QFileInfo>

#include "ConflictResolver.h"
#include "database/DatabaseManager.h"
#include "services/FileHasher.h"

namespace core {

SyncEngine::SyncEngine(database::DatabaseManager *databaseManager, QString localMachineId, QObject *parent)
    : QObject(parent)
    , m_databaseManager(databaseManager)
    , m_localMachineId(std::move(localMachineId))
    , m_fileRepository(databaseManager ? databaseManager->database() : QSqlDatabase())
    , m_operationRepository(databaseManager ? databaseManager->database() : QSqlDatabase())
{
}

SyncEngine::~SyncEngine() = default;

void SyncEngine::attachFolder(const models::SharedFolder &folder)
{
    if (m_watchedFolders.contains(folder.id())) {
        return;
    }

    auto *watcher = new services::FolderWatcher(this);
    if (!watcher->watch(folder.localPath())) {
        delete watcher;
        return;
    }

    const int folderId = folder.id();
    connect(watcher, &services::FolderWatcher::fileCreated, this, [this, folderId](const QString &relativePath) {
        onLocalFileCreatedOrChanged(folderId, relativePath, models::SyncOperationType::Create);
    });
    connect(watcher, &services::FolderWatcher::fileChanged, this, [this, folderId](const QString &relativePath) {
        onLocalFileCreatedOrChanged(folderId, relativePath, models::SyncOperationType::Update);
    });
    connect(watcher, &services::FolderWatcher::fileDeleted, this, [this, folderId](const QString &relativePath) {
        onLocalFileDeleted(folderId, relativePath);
    });

    WatchedFolder watched;
    watched.folder = folder;
    watched.watcher = watcher;
    m_watchedFolders.insert(folderId, watched);
}

void SyncEngine::detachFolder(int folderId)
{
    auto it = m_watchedFolders.find(folderId);
    if (it == m_watchedFolders.end()) {
        return;
    }
    it->watcher->unwatch();
    it->watcher->deleteLater();
    m_watchedFolders.erase(it);
}

bool SyncEngine::isAttached(int folderId) const
{
    return m_watchedFolders.contains(folderId);
}

void SyncEngine::recordOperation(int fileId, models::SyncOperationType type, int version)
{
    models::SyncOperation operation;
    operation.setFileId(fileId);
    operation.setType(type);
    operation.setVersion(version);
    operation.setMachineId(m_localMachineId);
    m_operationRepository.create(operation);
}

void SyncEngine::onLocalFileCreatedOrChanged(int folderId, const QString &relativePath, models::SyncOperationType type)
{
    const auto it = m_watchedFolders.find(folderId);
    if (it == m_watchedFolders.end()) {
        return;
    }

    const QString absolutePath = QDir(it->folder.localPath()).filePath(relativePath);
    const QFileInfo info(absolutePath);
    if (!info.exists() || !info.isFile()) {
        return; // deja supprime entre l'evenement et le traitement
    }

    const QString hash = services::FileHasher::hashFile(absolutePath);
    auto existing = m_fileRepository.findByFolderAndPath(folderId, relativePath);

    models::SharedFile file = existing.value_or(models::SharedFile());
    file.setFolderId(folderId);
    file.setRelativePath(relativePath);
    file.setHash(hash);
    file.setSize(info.size());
    file.setLastModified(info.lastModified());
    file.setDeleted(false);
    file.setVersion(existing ? existing->version() + 1 : 1);

    int fileId;
    if (existing) {
        m_fileRepository.update(file);
        fileId = file.id();
    } else {
        fileId = m_fileRepository.create(file);
        file.setId(fileId);
    }

    recordOperation(fileId, existing ? models::SyncOperationType::Update : models::SyncOperationType::Create, file.version());
    emit localFileChanged(folderId, it->folder.name(), relativePath, hash, file.size(), file.version());
}

void SyncEngine::onLocalFileDeleted(int folderId, const QString &relativePath)
{
    const auto it = m_watchedFolders.find(folderId);
    if (it == m_watchedFolders.end()) {
        return;
    }

    auto existing = m_fileRepository.findByFolderAndPath(folderId, relativePath);
    if (!existing) {
        return;
    }

    existing->setDeleted(true);
    existing->setVersion(existing->version() + 1);
    m_fileRepository.update(*existing);

    recordOperation(existing->id(), models::SyncOperationType::Delete, existing->version());
    emit localFileDeleted(folderId, it->folder.name(), relativePath, existing->version());
}

void SyncEngine::applyRemoteFileInfo(int folderId, const QString &relativePath, const QString &hash, qint64 size, int remoteVersion, const QString &remoteMachineLabel)
{
    auto existing = m_fileRepository.findByFolderAndPath(folderId, relativePath);

    if (existing) {
        const auto resolution = ConflictResolver::resolve(*existing, remoteVersion, hash);
        if (resolution == ConflictResolver::Resolution::RemoteIsOlder) {
            return; // rien a faire, on est deja a jour ou en avance
        }
        if (resolution == ConflictResolver::Resolution::Conflict) {
            const QString renamedTo = ConflictResolver::conflictFileName(relativePath, remoteMachineLabel);
            emit conflictDetected(folderId, relativePath, renamedTo);
            // La copie locale renommee redevient un nouveau fichier
            // (avec son propre historique) ; le remote peut alors etre
            // applique sous le nom d'origine sans perte de donnees.
            existing->setRelativePath(renamedTo);
            m_fileRepository.update(*existing);
            existing = std::nullopt;
        }
    }

    models::SharedFile file = existing.value_or(models::SharedFile());
    file.setFolderId(folderId);
    file.setRelativePath(relativePath);
    file.setHash(hash);
    file.setSize(size);
    file.setLastModified(QDateTime::currentDateTimeUtc());
    file.setVersion(remoteVersion);
    file.setDeleted(false);

    if (existing) {
        m_fileRepository.update(file);
    } else {
        const int fileId = m_fileRepository.create(file);
        file.setId(fileId);
    }
}

void SyncEngine::applyRemoteDelete(int folderId, const QString &relativePath, int remoteVersion)
{
    auto existing = m_fileRepository.findByFolderAndPath(folderId, relativePath);
    if (!existing) {
        return;
    }
    if (remoteVersion <= existing->version()) {
        return;
    }
    existing->setDeleted(true);
    existing->setVersion(remoteVersion);
    m_fileRepository.update(*existing);
}

void SyncEngine::applyRemoteRename(int folderId, const QString &oldRelativePath, const QString &newRelativePath, int remoteVersion)
{
    auto existing = m_fileRepository.findByFolderAndPath(folderId, oldRelativePath);
    if (!existing) {
        return;
    }
    if (remoteVersion <= existing->version()) {
        return;
    }
    existing->setRelativePath(newRelativePath);
    existing->setVersion(remoteVersion);
    m_fileRepository.update(*existing);
}

} // namespace core
