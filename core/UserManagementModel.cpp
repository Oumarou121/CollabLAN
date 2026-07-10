#include "UserManagementModel.h"
#include "UserManager.h"
#include "Database/Repositories/UserRepository.h"
#include "DatabaseManager.h"

namespace core {

UserManagementModel::UserManagementModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

UserManagementModel::~UserManagementModel() = default;

int UserManagementModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_users.size();
}

QVariant UserManagementModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_users.size())
        return QVariant();

    const models::User &user = m_users[index.row()];

    switch (role) {
    case IdRole:
        return user.id();
    case NameRole:
        return user.name();
    case IpAddressRole:
        return user.ipAddress();
    case StatusRole:
        return models::userStatusToString(user.status());
    case RoleRole:
        return models::userRoleToString(user.role());
    case IsAdminRole:
        return user.isAdmin();
    case CreatedAtRole:
        return user.createdAt().toString(Qt::ISODate);
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> UserManagementModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[NameRole] = "name";
    roles[IpAddressRole] = "ipAddress";
    roles[StatusRole] = "status";
    roles[RoleRole] = "role";
    roles[IsAdminRole] = "isAdmin";
    roles[CreatedAtRole] = "createdAt";
    return roles;
}

void UserManagementModel::refresh()
{
    beginResetModel();
    m_users.clear();
    
    // TODO: Charger depuis UserRepository via UserManager
    // Pour l'instant, données de test
    m_users.append(models::User(1, "admin", "192.168.1.10", models::UserStatus::Online, models::UserRole::Admin, "", "", QDateTime::currentDateTime()));
    m_users.append(models::User(2, "alice", "192.168.1.11", models::UserStatus::Online, models::UserRole::User, "", "", QDateTime::currentDateTime()));
    m_users.append(models::User(3, "bilal", "192.168.1.12", models::UserStatus::Offline, models::UserRole::User, "", "", QDateTime::currentDateTime()));
    
    endResetModel();
}

bool UserManagementModel::createUser(const QString &name, const QString &password, bool isAdmin)
{
    // TODO: Appeler UserManager.createUser()
    beginInsertRows(QModelIndex(), m_users.size(), m_users.size());
    models::User user;
    user.setName(name);
    user.setStatus(models::UserStatus::Offline);
    user.setRole(isAdmin ? models::UserRole::Admin : models::UserRole::User);
    user.setCreatedAt(QDateTime::currentDateTime());
    m_users.append(user);
    endInsertRows();
    return true;
}

bool UserManagementModel::deleteUser(int id)
{
    for (int i = 0; i < m_users.size(); ++i) {
        if (m_users[i].id() == id) {
            beginRemoveRows(QModelIndex(), i, i);
            m_users.removeAt(i);
            endRemoveRows();
            return true;
        }
    }
    return false;
}

bool UserManagementModel::changeRole(int id, bool isAdmin)
{
    for (int i = 0; i < m_users.size(); ++i) {
        if (m_users[i].id() == id) {
            m_users[i].setRole(isAdmin ? models::UserRole::Admin : models::UserRole::User);
            emit dataChanged(index(i), index(i));
            return true;
        }
    }
    return false;
}

bool UserManagementModel::changeStatus(int id, const QString &status)
{
    const auto userStatus = models::userStatusFromString(status);
    for (int i = 0; i < m_users.size(); ++i) {
        if (m_users[i].id() == id) {
            m_users[i].setStatus(userStatus);
            emit dataChanged(index(i), index(i));
            return true;
        }
    }
    return false;
}

void UserManagementModel::setUserManager(QObject *manager)
{
    m_userManager = manager;
}

} // namespace core
