#include "SharedFolderModel.h"

namespace models {

SharedFolderModel::SharedFolderModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

QHash<int, QByteArray> SharedFolderModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[FolderIdRole] = "folderId";
    roles[UuidRole] = "uuid";
    roles[NameRole] = "name";
    roles[LocalPathRole] = "localPath";
    roles[OwnerIdRole] = "ownerId";
    roles[FileCountRole] = "fileCount";
    roles[IsActiveRole] = "isActive";
    roles[IsLocalOriginRole] = "isLocalOrigin";
    roles[HasConflictRole] = "hasConflict";
    return roles;
}

int SharedFolderModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_folders.size();
}

QVariant SharedFolderModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_folders.size()) {
        return QVariant();
    }

    const SharedFolder &folder = m_folders.at(index.row());

    switch (role) {
    case FolderIdRole:
        return folder.id();
    case UuidRole:
        return folder.uuid();
    case NameRole:
        return folder.name();
    case LocalPathRole:
        return folder.localPath();
    case OwnerIdRole:
        return folder.ownerId();
    case FileCountRole:
        return m_fileCounts.value(folder.id(), 0);
    case IsActiveRole:
        return folder.isActive();
    case IsLocalOriginRole:
        return folder.isLocalOrigin();
    case HasConflictRole:
        return m_conflicts.value(folder.id(), false);
    default:
        return QVariant();
    }
}

void SharedFolderModel::setFolders(const QVector<SharedFolder> &folders)
{
    // Memes dossiers dans le meme ordre (cas courant d'un rafraichissement) :
    // simple mise a jour des lignes. Une reinitialisation faisait recreer
    // toutes les lignes cote QML a chaque rafraichissement.
    bool sameRows = folders.size() == m_folders.size() && !folders.isEmpty();
    for (int i = 0; sameRows && i < folders.size(); ++i)
        sameRows = folders.at(i).id() == m_folders.at(i).id();
    if (sameRows) {
        m_folders = folders;
        emit dataChanged(index(0), index(m_folders.size() - 1));
        return;
    }

    beginResetModel();
    m_folders = folders;
    endResetModel();
}

void SharedFolderModel::addFolder(const SharedFolder &folder)
{
    beginInsertRows(QModelIndex(), m_folders.size(), m_folders.size());
    m_folders.append(folder);
    endInsertRows();
}

void SharedFolderModel::removeFolder(qint64 folderId)
{
    for (int i = 0; i < m_folders.size(); ++i) {
        if (m_folders.at(i).id() == folderId) {
            beginRemoveRows(QModelIndex(), i, i);
            m_folders.removeAt(i);
            endRemoveRows();
            return;
        }
    }
}

void SharedFolderModel::clear()
{
    beginResetModel();
    m_folders.clear();
    m_fileCounts.clear();
    m_conflicts.clear();
    endResetModel();
}

void SharedFolderModel::setFileCounts(const QHash<qint64, int> &counts)
{
    m_fileCounts = counts;
    if (!m_folders.isEmpty()) {
        emit dataChanged(index(0), index(m_folders.size() - 1), {FileCountRole});
    }
}

void SharedFolderModel::setConflicts(const QHash<qint64, bool> &conflicts)
{
    m_conflicts = conflicts;
    if (!m_folders.isEmpty()) {
        emit dataChanged(index(0), index(m_folders.size() - 1), {HasConflictRole});
    }
}

} // namespace models
