#include "PermissionManager.h"
#include "DatabaseManager.h"
#include "Database/Repositories/AuthorizedMachineRepository.h"

namespace core {

QString userRoleToString(UserRole role)
{
    switch (role) {
    case UserRole::Admin:
        return QStringLiteral("admin");
    case UserRole::User:
        return QStringLiteral("user");
    }
    return QStringLiteral("user");
}

std::optional<UserRole> stringToUserRole(const QString &str)
{
    if (str == QStringLiteral("admin"))
        return UserRole::Admin;
    if (str == QStringLiteral("user"))
        return UserRole::User;
    return std::nullopt;
}

PermissionManager::PermissionManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
{
    if (m_dbManager) {
        m_repository = std::make_unique<database::AuthorizedMachineRepository>(m_dbManager->database());
    }
}

PermissionManager::~PermissionManager()
{
}

bool PermissionManager::canPerformAdminAction(UserRole role)
{
    return role == UserRole::Admin;
}

bool PermissionManager::canAccessAdminView(UserRole role)
{
    return role == UserRole::Admin;
}

bool PermissionManager::canManageUsers(UserRole role)
{
    return role == UserRole::Admin;
}

bool PermissionManager::canManageAuthorizedMachines(UserRole role)
{
    return role == UserRole::Admin;
}

bool PermissionManager::isMachineAuthorized(const QString &ipAddress) const
{
    if (!m_repository)
        return true; // Par défaut, autorisé si le repository n'est pas initialisé
    return m_repository->isAuthorized(ipAddress);
}

bool PermissionManager::revokeMachine(const QString &ipAddress, int revokedBy, const QString &reason)
{
    if (!m_repository)
        return false;
    return m_repository->revokeByIpAddress(ipAddress, revokedBy, reason);
}

bool PermissionManager::authorizeMachine(const QString &ipAddress, int authorizedBy, const QString &reason)
{
    if (!m_repository)
        return false;
    return m_repository->authorizeByIpAddress(ipAddress, authorizedBy, reason);
}

} // namespace core
