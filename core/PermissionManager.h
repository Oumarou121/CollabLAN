#ifndef CORE_PERMISSIONMANAGER_H
#define CORE_PERMISSIONMANAGER_H

#include <QObject>
#include <QString>
#include <optional>
#include <memory>
#include <vector>
#include "models/AuthorizedMachine.h"

namespace database {
class DatabaseManager;
class AuthorizedMachineRepository;
}

namespace models {
class AuthorizedMachine;
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
    /// Q_INVOKABLE requis : MessagingServer/MessagingService l'appellent via
    /// QMetaObject::invokeMethod("isMachineAuthorized", ...) plutot que par un
    /// pointeur direct (voir issue #70). Sans ce marqueur, invokeMethod
    /// echoue silencieusement ("No such method...") et le controle d'acces
    /// se retrouve fail-open (authorized reste a sa valeur par defaut true).
    Q_INVOKABLE bool isMachineAuthorized(const QString &ipAddress) const;
    Q_INVOKABLE bool isMachineAuthorizedByCertificate(const QString &fingerprint) const;
    Q_INVOKABLE void recordMachineSeen(const QString &fingerprint, const QString &ipAddress);
    Q_INVOKABLE bool trustRemoteServerCertificate(const QString &fingerprint,
                                                  const QString &ipAddress);
    std::optional<models::AuthorizedMachine> findMachineByCertificateFingerprint(const QString &fingerprint) const;

    bool removeMachine(int id);
    bool applyRemoteMachineRemoval(const QString &machineUuid, const QString &fingerprint);

    /// Révoque une machine par son adresse IP (issue #68).
    bool revokeMachine(const QString &ipAddress, int revokedBy, const QString &reason = QString());

    /// Autorise une machine par son adresse IP (issue #68).
    bool authorizeMachine(const QString &ipAddress, int authorizedBy, const QString &reason = QString());
    bool authorizeMachineByCertificate(const QString &fingerprint, const QString &machineUuid,
                                       const QString &hostname, const QString &ipAddress,
                                       int authorizedBy, const QString &reason = QString());
    bool applyRemoteMachine(const models::AuthorizedMachine &machine);

    bool revokeMachineByCertificate(const QString &fingerprint, int revokedBy,
                                const QString &reason = QString());
    bool authorizeExistingMachineByCertificate(const QString &fingerprint, int authorizedBy,
                                const QString &reason = QString());

    /// Retourne toutes les machines (pour AuthorizedMachineModel)
    std::vector<models::AuthorizedMachine> getAllMachines() const;

    /// Retourne le DatabaseManager (pour AuthorizedMachineModel)
    database::DatabaseManager* databaseManager() const;

signals:
    void machineChanged(const models::AuthorizedMachine &machine);
    void machineRemoved(const QString &machineUuid, const QString &certificateFingerprint);
    void machineSynchronized();


private:
    database::DatabaseManager *m_dbManager = nullptr;
    std::unique_ptr<database::AuthorizedMachineRepository> m_repository;
};

} // namespace core

#endif // CORE_PERMISSIONMANAGER_H
