#ifndef CORE_PERMISSIONMANAGER_H
#define CORE_PERMISSIONMANAGER_H

#include <QObject>
#include <QString>
#include <optional>
#include <memory>

namespace database {
class DatabaseManager;
class AuthorizedMachineRepository;
}

namespace core {

/**
 * @brief Rôles utilisateurs dans l'application (issue #67).
 */
enum class UserRole {
    User,   ///< Utilisateur standard (accès limité)
    Admin   ///< Administrateur (accès complet, y compris administration)
};

/**
 * @brief Convertit un rôle en chaîne de caractères pour stockage en base.
 */
QString userRoleToString(UserRole role);

/**
 * @brief Convertit une chaîne de caractères en rôle.
 */
std::optional<UserRole> stringToUserRole(const QString &str);

/**
 * @brief Gestion des permissions et des rôles (admin, utilisateur...).
 *
 * Vérifie les droits avant les actions sensibles (accès à l'administration,
 * gestion des utilisateurs, etc.) et gère la liste blanche/noire des machines
 * autorisées (issue #68).
 */
class PermissionManager : public QObject
{
    Q_OBJECT

public:
    explicit PermissionManager(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~PermissionManager() override;

    /// Vérifie si un rôle a le droit d'effectuer une action d'administration.
    static bool canPerformAdminAction(UserRole role);

    /// Vérifie si un rôle a le droit d'accéder à l'écran d'administration.
    static bool canAccessAdminView(UserRole role);

    /// Vérifie si un rôle a le droit de gérer les utilisateurs.
    static bool canManageUsers(UserRole role);

    /// Vérifie si un rôle a le droit de gérer les machines autorisées.
    static bool canManageAuthorizedMachines(UserRole role);

    /// Vérifie si une adresse IP est autorisée à rejoindre le réseau (issue #68).
    bool isMachineAuthorized(const QString &ipAddress) const;

    /// Révoque une machine par son adresse IP (issue #68).
    bool revokeMachine(const QString &ipAddress, int revokedBy, const QString &reason = QString());

    /// Autorise une machine par son adresse IP (issue #68).
    bool authorizeMachine(const QString &ipAddress, int authorizedBy, const QString &reason = QString());

private:
    database::DatabaseManager *m_dbManager = nullptr;
    std::unique_ptr<database::AuthorizedMachineRepository> m_repository;
};

} // namespace core

#endif // CORE_PERMISSIONMANAGER_H
