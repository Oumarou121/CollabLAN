#include "SharedFoldersModel.h"

#include "SharedFolderManager.h"
#include "database/DatabaseManager.h"

namespace core {

SharedFoldersModel::SharedFoldersModel(SharedFolderManager *manager, database::DatabaseManager *databaseManager, QObject *parent)
    : QAbstractListModel(parent)
    , m_manager(manager)
    , m_fileRepository(databaseManager ? databaseManager->database() : QSqlDatabase())
{
    if (m_manager) {
        connect(m_manager, &SharedFolderManager::foldersChanged, this, &SharedFoldersModel::reload);
    }
    reload();
}

void SharedFoldersModel::reload()
{
    beginResetModel();
    m_folders.clear();
    if (m_manager) {
        const auto active = m_manager->activeFolders();
        for (const auto &folder : active) {
            m_folders.append(folder);
        }
    }
    endResetModel();
    emit countChanged();
}

int SharedFoldersModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_folders.size();
}

QVariant SharedFoldersModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_folders.size()) {
        return QVariant();
    }

    const models::SharedFolder &folder = m_folders.at(index.row());
    switch (role) {
    case IdRole:
        return folder.id();
    case NameRole:
        return folder.name();
    case LocalPathRole:
        return folder.localPath();
    case FileCountRole:
        return m_fileRepository.countActiveByFolder(folder.id());
    case IsActiveRole:
        return folder.isActive();
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> SharedFoldersModel::roleNames() const
{
    return {
        {IdRole, "folderId"},
        {NameRole, "name"},
        {LocalPathRole, "localPath"},
        {FileCountRole, "fileCount"},
        {IsActiveRole, "isActive"},
    };
}

int SharedFoldersModel::count() const
{
    return m_folders.size();
}

} // namespace core
