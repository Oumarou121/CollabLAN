#include "GroupModel.h"

namespace models {

GroupModel::GroupModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

QHash<int, QByteArray> GroupModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[GroupIdRole] = "groupId";
    roles[NameRole] = "name";
    roles[OwnerIdRole] = "ownerId";
    roles[MemberCountRole] = "memberCount";
    roles[ConversationIdRole] = "conversationId";
    return roles;
}

int GroupModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_groups.size();
}

QVariant GroupModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_groups.size()) {
        return QVariant();
    }

    const Group &group = m_groups.at(index.row());

    switch (role) {
    case GroupIdRole:
        return group.id();
    case NameRole:
        return group.name();
    case OwnerIdRole:
        return group.ownerId();
    case MemberCountRole:
        return group.memberIds().size();
    case ConversationIdRole:
        return group.conversationId();
    default:
        return QVariant();
    }
}

void GroupModel::setGroups(const QVector<Group> &groups)
{
    beginResetModel();
    m_groups = groups;
    endResetModel();
}

void GroupModel::addGroup(const Group &group)
{
    beginInsertRows(QModelIndex(), m_groups.size(), m_groups.size());
    m_groups.append(group);
    endInsertRows();
}

void GroupModel::clear()
{
    beginResetModel();
    m_groups.clear();
    endResetModel();
}

} // namespace models
