#include "UserManagementModel.h"
#include "UserManager.h"
#include "database/Repositories/UserRepository.h"
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

    if (auto *manager = qobject_cast<UserManager *>(m_userManager)) {
        const auto users = manager->allUsers();
        m_users.reserve(static_cast<int>(users.size()));
        for (const auto &user : users) {
            m_users.append(user);
        }
    }

    endResetModel();
}

bool UserManagementModel::createUser(const QString &name, const QString &password, bool isAdmin)
{
    auto *manager = qobject_cast<UserManager *>(m_userManager);
    if (!manager) {
        return false;
    }

    const auto created = manager->createUser(name, password, isAdmin);
    if (!created.has_value()) {
        return false;
    }

    // Rechargement complet plutot qu'une insertion locale : createUser()
    // emet deja userCreated() (branche par Application::appendUserSyncLog),
    // et refresh() garantit que ce modele reste le reflet fidele de la base
    // (uuid/updated_at generes cote UserRepository, pas devinables ici).
    refresh();
    return true;
}

bool UserManagementModel::deleteUser(int id)
{
    auto *manager = qobject_cast<UserManager *>(m_userManager);
    if (!manager) {
        return false;
    }

    if (!manager->deleteUser(id)) {
        return false;
    }

    refresh();
    return true;
}

bool UserManagementModel::changeRole(int id, bool isAdmin)
{
    auto *manager = qobject_cast<UserManager *>(m_userManager);
    if (!manager) {
        return false;
    }

    if (!manager->changeRole(id, isAdmin)) {
        return false;
    }

    refresh();
    return true;
}

bool UserManagementModel::changeStatus(int id, const QString &status)
{
    auto *manager = qobject_cast<UserManager *>(m_userManager);
    if (!manager) {
        return false;
    }

    const auto userStatus = models::userStatusFromString(status);
    if (!manager->setStatus(id, userStatus)) {
        return false;
    }

    refresh();
    return true;
}

QStringList UserManagementModel::names() const
{
    QStringList result;
    result.reserve(m_users.size());
    for (const auto &user : m_users) {
        result.append(user.name());
    }
    return result;
}

void UserManagementModel::setUserManager(QObject *manager)
{
    m_userManager = manager;
}

} // namespace core