#include "SharedFolderManager.h"

#include <QDir>
#include <QFileInfo>

#include "database/DatabaseManager.h"

namespace core {

SharedFolderManager::SharedFolderManager(database::DatabaseManager *databaseManager, QObject *parent)
    : QObject(parent)
    , m_databaseManager(databaseManager)
    , m_repository(databaseManager ? databaseManager->database() : QSqlDatabase())
{
}

SharedFolderManager::~SharedFolderManager() = default;

bool SharedFolderManager::createFolder(const QString &name, const QString &localPath, int ownerId)
{
    const QString trimmedName = name.trimmed();
    if (trimmedName.isEmpty()) {
        m_lastError = QStringLiteral("Le nom du dossier partage est obligatoire.");
        emit folderOperationFailed(m_lastError);
        return false;
    }

    const QFileInfo info(localPath);
    if (!info.exists() || !info.isDir()) {
        m_lastError = QStringLiteral("Le chemin local n'existe pas ou n'est pas un dossier : %1").arg(localPath);
        emit folderOperationFailed(m_lastError);
        return false;
    }

    const QString normalizedPath = QDir(localPath).absolutePath();
    if (m_repository.existsByLocalPath(normalizedPath)) {
        m_lastError = QStringLiteral("Ce dossier est deja partage.");
        emit folderOperationFailed(m_lastError);
        return false;
    }

    models::SharedFolder folder;
    folder.setName(trimmedName);
    folder.setLocalPath(normalizedPath);
    folder.setOwnerId(ownerId);
    folder.setIsActive(true);

    const int id = m_repository.create(folder);
    if (id < 0) {
        m_lastError = m_repository.lastError();
        emit folderOperationFailed(m_lastError);
        return false;
    }

    folder.setId(id);
    emit folderCreated(folder);
    emit foldersChanged();
    return true;
}

bool SharedFolderManager::removeFolder(int folderId)
{
    auto folder = m_repository.findById(folderId);
    if (!folder.has_value()) {
        m_lastError = QStringLiteral("Dossier partage introuvable.");
        emit folderOperationFailed(m_lastError);
        return false;
    }

    // On desactive plutot que de supprimer definitivement : conserve
    // l'historique (SyncOperations) et evite de casser les references
    // des postes qui n'ont pas encore recu la nouvelle liste.
    folder->setIsActive(false);
    if (!m_repository.update(*folder)) {
        m_lastError = m_repository.lastError();
        emit folderOperationFailed(m_lastError);
        return false;
    }

    emit folderRemoved(folderId);
    emit foldersChanged();
    return true;
}

bool SharedFolderManager::shareFolder(int folderId)
{
    auto folder = m_repository.findById(folderId);
    if (!folder.has_value()) {
        m_lastError = QStringLiteral("Dossier partage introuvable.");
        emit folderOperationFailed(m_lastError);
        return false;
    }

    folder->setIsActive(true);
    if (!m_repository.update(*folder)) {
        m_lastError = m_repository.lastError();
        emit folderOperationFailed(m_lastError);
        return false;
    }

    emit folderShared(*folder);
    emit foldersChanged();
    return true;
}

int SharedFolderManager::folderCount() const
{
    return static_cast<int>(activeFolders().size());
}

std::vector<models::SharedFolder> SharedFolderManager::getFolders() const
{
    return m_repository.findAll();
}

std::vector<models::SharedFolder> SharedFolderManager::activeFolders() const
{
    return m_repository.findActive();
}

std::optional<models::SharedFolder> SharedFolderManager::findById(int folderId) const
{
    return m_repository.findById(folderId);
}

QString SharedFolderManager::lastError() const
{
    return m_lastError;
}

} // namespace core
