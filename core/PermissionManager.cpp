#include "PermissionManager.h"
#include "DatabaseManager.h"
#include "database/Repositories/AuthorizedMachineRepository.h"
#include "models/AuthorizedMachine.h"

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
        return false; // Fail-closed : refuse par défaut si le repository n'est pas initialisé
    Q_UNUSED(ipAddress)
    return false;
}

bool PermissionManager::isMachineAuthorizedByCertificate(const QString &fingerprint) const
{
    if (!m_repository || fingerprint.trimmed().isEmpty()) return false;
    const auto machine = m_repository->findByCertificateFingerprint(fingerprint);
    // Seul le statut 'authorized' donne acces ; 'pending' et 'revoked'
    // restent refuses meme si l'ancien champ authorized trainait a true.
    return machine.has_value() && machine->status() == models::MachineStatus::Authorized;
}

void PermissionManager::recordMachineSeen(const QString &fingerprint, const QString &ipAddress)
{
    if (!m_repository || fingerprint.trimmed().isEmpty()) return;
    m_repository->updateLastSeen(fingerprint, ipAddress);
}

bool PermissionManager::trustRemoteServerCertificate(const QString &fingerprint,
                                                      const QString &ipAddress)
{
    if (!m_repository || fingerprint.trimmed().isEmpty()) return false;
    const auto existing = m_repository->findByCertificateFingerprint(fingerprint);
    if (existing.has_value()) {
        if (existing->status() != models::MachineStatus::Authorized) return false;
        m_repository->updateLastSeen(fingerprint, ipAddress);
        return true;
    }

    // Machine/serveur inconnu : on l'enregistre pour affichage dans l'admin,
    // mais on ne l'autorise jamais automatiquement (plan #71).
    registerPendingMachineByCertificate(fingerprint, ipAddress, QStringLiteral("Serveur distant"));
    return false;
}

bool PermissionManager::registerPendingMachineByCertificate(const QString &fingerprint,
                                                             const QString &ipAddress,
                                                             const QString &hostname)
{
    if (!m_repository || fingerprint.trimmed().isEmpty()) return false;

    const bool alreadyKnown = m_repository->findByCertificateFingerprint(fingerprint).has_value();
    const bool ok = m_repository->registerPendingByCertificate(
        fingerprint, ipAddress, hostname,
        QStringLiteral("Machine détectée — autorisation requise"));
    if (ok && !alreadyKnown) {
        const auto saved = m_repository->findByCertificateFingerprint(fingerprint);
        if (saved) emit machineChanged(*saved);
    }
    return ok;
}

bool PermissionManager::bootstrapLocalAdminMachineIfNeeded(const QString &fingerprint,
                                                            const QString &machineUuid,
                                                            const QString &hostname,
                                                            const QString &ipAddress,
                                                            int adminUserId)
{
    if (!m_repository || fingerprint.trimmed().isEmpty()) return false;

    // Une machine autorisee existe deja : pas de bootstrap, la nouvelle
    // machine (meme locale, meme admin) doit passer par la validation
    // normale depuis une machine deja autorisee.
    if (m_repository->hasAnyAuthorizedMachine()) return false;

    const auto existing = m_repository->findByCertificateFingerprint(fingerprint);
    models::AuthorizedMachine machine = existing.value_or(models::AuthorizedMachine());
    machine.setUuid(machineUuid.isEmpty() ? machine.uuid() : machineUuid);
    machine.setCertificateFingerprint(fingerprint.toLower());
    machine.setHostname(hostname);
    machine.setIpAddress(ipAddress);
    machine.setLastIpAddress(ipAddress);
    machine.setStatus(models::MachineStatus::Authorized);
    machine.setAddedBy(adminUserId);
    machine.setReason(QStringLiteral("Machine locale initiale autorisée"));

    const bool ok = existing.has_value() ? m_repository->update(machine)
                                          : (m_repository->create(machine) >= 0);
    if (ok) {
        const auto saved = m_repository->findByCertificateFingerprint(fingerprint);
        if (saved) emit machineChanged(*saved);
    }
    return ok;
}

std::optional<models::AuthorizedMachine> PermissionManager::findMachineByCertificateFingerprint(const QString &fingerprint) const
{
    if (!m_repository) return std::nullopt;
    return m_repository->findByCertificateFingerprint(fingerprint);
}

bool PermissionManager::revokeMachine(const QString &ipAddress, int revokedBy, const QString &reason)
{
    if (!m_repository)
        return false;
    const bool ok = m_repository->revokeByIpAddress(ipAddress, revokedBy, reason);
    if (ok) { auto machine = m_repository->findByIpAddress(ipAddress); if (machine) emit machineChanged(*machine); }
    return ok;
}

bool PermissionManager::revokeMachineByCertificate(const QString &fingerprint,
                                                   int revokedBy,
                                                   const QString &reason)
{
    if (!m_repository || fingerprint.trimmed().isEmpty())
        return false;

    const bool ok = m_repository->setAuthorizationByCertificate(
        fingerprint,
        false,
        revokedBy,
        reason
    );

    if (ok) {
        auto machine = m_repository->findByCertificateFingerprint(fingerprint);
        if (machine) {
            emit machineChanged(*machine);
        }
    }

    return ok;
}

bool PermissionManager::authorizeExistingMachineByCertificate(const QString &fingerprint,
                                                              int authorizedBy,
                                                              const QString &reason)
{
    if (!m_repository || fingerprint.trimmed().isEmpty())
        return false;

    const bool ok = m_repository->setAuthorizationByCertificate(
        fingerprint,
        true,
        authorizedBy,
        reason
    );

    if (ok) {
        auto machine = m_repository->findByCertificateFingerprint(fingerprint);
        if (machine) {
            emit machineChanged(*machine);
        }
    }

    return ok;
}

bool PermissionManager::authorizeMachine(const QString &ipAddress, int authorizedBy, const QString &reason)
{
    if (!m_repository)
        return false;
    const bool ok = m_repository->authorizeByIpAddress(ipAddress, authorizedBy, reason);
    if (ok) { auto machine = m_repository->findByIpAddress(ipAddress); if (machine) emit machineChanged(*machine); }
    return ok;
}

bool PermissionManager::applyRemoteMachine(const models::AuthorizedMachine &machine)
{
    if (!m_repository) return false;

    const bool ok = m_repository->upsertRemote(machine);
    if (ok) emit machineSynchronized();
    return ok;
}

bool PermissionManager::removeMachine(int id)
{
    if (!m_repository)
        return false;

    QString machineUuid;
    QString fingerprint;
    for (const auto &machine : m_repository->findAll()) {
        if (machine.id() == id) {
            machineUuid = machine.uuid();
            fingerprint = machine.certificateFingerprint();
            break;
        }
    }

    const bool ok = m_repository->remove(id);
    if (ok) {
        emit machineRemoved(machineUuid, fingerprint);
    }
    return ok;
}

bool PermissionManager::applyRemoteMachineRemoval(const QString &machineUuid, const QString &fingerprint)
{
    if (!m_repository)
        return false;

    const bool ok = m_repository->removeByUuidOrCertificate(machineUuid, fingerprint);
    if (ok) {
        emit machineSynchronized();
    }
    return ok;
}

bool PermissionManager::authorizeMachineByCertificate(const QString &fingerprint, const QString &machineUuid,
                                                      const QString &hostname, const QString &ipAddress,
                                                      int authorizedBy, const QString &reason)
{
    if (!m_repository || fingerprint.trimmed().isEmpty()) return false;
    models::AuthorizedMachine machine;
    machine.setUuid(machineUuid);
    machine.setCertificateFingerprint(fingerprint.toLower());
    machine.setHostname(hostname);
    machine.setIpAddress(ipAddress);
    machine.setLastIpAddress(ipAddress);
    machine.setStatus(models::MachineStatus::Authorized);
    machine.setAddedBy(authorizedBy);
    machine.setReason(reason);
    const auto existing = m_repository->findByCertificateFingerprint(fingerprint);
    bool ok = false;
    if (existing.has_value()) {
        machine.setId(existing->id());
        ok = m_repository->update(machine);
    } else {
        ok = m_repository->create(machine) >= 0;
    }
    if (ok) {
        const auto saved = m_repository->findByCertificateFingerprint(fingerprint);
        if (saved) emit machineChanged(*saved);
    }
    return ok;
}

std::vector<models::AuthorizedMachine> PermissionManager::getAllMachines() const
{
    if (!m_repository)
        return {};
    return m_repository->findAll();
}

database::DatabaseManager* PermissionManager::databaseManager() const
{
    return m_dbManager;
}

} // namespace core
