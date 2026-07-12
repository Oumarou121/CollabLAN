#include "CallHistoryModel.h"
#include "CallHistoryManager.h"
#include "UserManager.h"

namespace core {

CallHistoryModel::CallHistoryModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

CallHistoryModel::~CallHistoryModel() = default;

int CallHistoryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_entries.size();
}

QVariant CallHistoryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_entries.size())
        return QVariant();

    const models::CallHistoryEntry &entry = m_entries.at(index.row());

    switch (role) {
    case IdRole:
        return entry.id();
    case DirectionRole:
        return models::callDirectionToString(entry.direction());
    case PeerAddressRole:
        return entry.peerAddress();
    case PeerNameRole:
        return entry.peerName();
    case StatusRole:
        return models::callStatusToString(entry.status());
    case StartedAtRole:
        return entry.startedAt().toLocalTime().toString(Qt::ISODate);
    case DurationSecondsRole:
        return entry.durationSeconds();
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> CallHistoryModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[DirectionRole] = "direction";
    roles[PeerAddressRole] = "peerAddress";
    roles[PeerNameRole] = "peerName";
    roles[StatusRole] = "status";
    roles[StartedAtRole] = "startedAt";
    roles[DurationSecondsRole] = "durationSeconds";
    return roles;
}

QObject* CallHistoryModel::callHistoryManager() const
{
    return m_callHistoryManager;
}

void CallHistoryModel::setCallHistoryManager(QObject *manager)
{
    if (static_cast<QObject*>(m_callHistoryManager) == manager)
        return;

    if (m_callHistoryManager) {
        m_callHistoryManager->disconnect(this);
    }

    m_callHistoryManager = qobject_cast<core::CallHistoryManager*>(manager);
    if (m_callHistoryManager) {
        connect(m_callHistoryManager, &core::CallHistoryManager::callRecorded,
                this, &CallHistoryModel::refresh);
        connect(m_callHistoryManager, &core::CallHistoryManager::callFinalized,
                this, &CallHistoryModel::refresh);
    }

    emit callHistoryManagerChanged();
    refresh();
}

void CallHistoryModel::setUserManager(UserManager *userManager)
{
    m_userManager = userManager;
}

void CallHistoryModel::setShowAllUsers(bool showAllUsers)
{
    if (m_showAllUsers == showAllUsers)
        return;
    m_showAllUsers = showAllUsers;
    emit showAllUsersChanged();
    refresh();
}

void CallHistoryModel::refresh()
{
    loadEntries();
}

void CallHistoryModel::loadEntries()
{
    if (!m_callHistoryManager) {
        return;
    }

    beginResetModel();
    m_entries.clear();

    std::vector<models::CallHistoryEntry> entries;
    if (!m_showAllUsers && m_userManager && m_userManager->currentUserId().has_value()) {
        entries = m_callHistoryManager->userCalls(*m_userManager->currentUserId());
    } else {
        entries = m_callHistoryManager->allCalls();
    }

    for (const models::CallHistoryEntry &entry : entries) {
        m_entries.append(entry);
    }

    endResetModel();
    emit countChanged();
}

} // namespace core
