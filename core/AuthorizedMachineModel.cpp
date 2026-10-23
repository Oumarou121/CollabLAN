#include "AuthorizedMachineModel.h"
#include "PermissionManager.h"
#include "UserManager.h"
#include "database/Repositories/AuthorizedMachineRepository.h"
#include "DatabaseManager.h"

#include <QDateTime>

namespace core {

AuthorizedMachineModel::AuthorizedMachineModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

AuthorizedMachineModel::~AuthorizedMachineModel() = default;

int AuthorizedMachineModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_machines.size();
}

QVariant AuthorizedMachineModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_machines.size())
        return QVariant();

    const models::AuthorizedMachine &machine = m_machines[index.row()];

    switch (role) {
    case IdRole:
        return machine.id();
    case IpAddressRole:
        return machine.ipAddress();
    case UuidRole:
        return machine.uuid();
    case MachineIdRole:
        return machine.uuid();
    case CertificateFingerprintRole:
        return machine.certificateFingerprint();
    case LastIpAddressRole:
        return machine.lastIpAddress();
    case HostnameRole:
        return machine.hostname();
    case AuthorizedRole:
        return machine.isAuthorized();
    case StatusRole:
        return machine.status();
    case AddedByRole:
        return machine.addedBy().value_or(-1);
    case AddedAtRole:
        return machine.addedAt().toString(Qt::ISODate);
    case ReasonRole:
        return machine.reason();
    case LastUserUuidRole:
        return machine.lastUserUuid();
    case LastUserNameRole:
        return m_userNames.value(machine.lastUserUuid());
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> AuthorizedMachineModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[IpAddressRole] = "ipAddress";
    roles[UuidRole] = "machineUuid";
    roles[MachineIdRole] = "machineId";
    roles[CertificateFingerprintRole] = "certificateFingerprint";
    roles[LastIpAddressRole] = "lastIpAddress";
    roles[HostnameRole] = "hostname";
    roles[AuthorizedRole] = "authorized";
    roles[StatusRole] = "status";
    roles[AddedByRole] = "addedBy";
    roles[AddedAtRole] = "addedAt";
    roles[ReasonRole] = "reason";
    roles[LastUserUuidRole] = "lastUserUuid";
    roles[LastUserNameRole] = "lastUserName";
    return roles;
}

void AuthorizedMachineModel::refresh()
{
    beginResetModel();
    m_machines.clear();

    // Noms des comptes (dernier compte vu sur chaque poste).
    m_userNames.clear();
    if (auto *users = qobject_cast<UserManager *>(m_userManager)) {
        for (const models::User &user : users->allUsers())
            m_userNames.insert(user.uuid(), user.name());
    }
    
    // Charger depuis AuthorizedMachineRepository via PermissionManager
    if (m_permissionManager) {
        const auto machines = m_permissionManager->getAllMachines();
        for (const auto &machine : machines) {
            m_machines.append(machine);
        }
    }
    
    endResetModel();
}

bool AuthorizedMachineModel::addMachine(const QString &ipAddress, const QString &hostname, const QString &reason)
{
    Q_UNUSED(hostname)
    if (m_permissionManager) {
        if (m_permissionManager->authorizeMachine(ipAddress, currentUserId(), reason)) {
            refresh(); // Recharger depuis la base
            return true;
        }
    }
    return false;
}

bool AuthorizedMachineModel::revokeMachine(int id, const QString &reason)
{
    if (m_permissionManager) {
        // Trouver l'empreinte certificat correspondant à l'ID
        for (int i = 0; i < m_machines.size(); ++i) {
            if (m_machines[i].id() == id) {
                if (m_permissionManager->revokeMachineByCertificate(m_machines[i].certificateFingerprint(), currentUserId(), reason)) {
                    refresh(); // Recharger depuis la base
                    return true;
                }
                break;
            }
        }
    }
    return false;
}

bool AuthorizedMachineModel::authorizeMachine(int id, const QString &reason)
{
    if (m_permissionManager) {
        // Trouver l'empreinte certificat correspondant à l'ID
        for (int i = 0; i < m_machines.size(); ++i) {
            if (m_machines[i].id() == id) {
                if (m_permissionManager->authorizeExistingMachineByCertificate(m_machines[i].certificateFingerprint(), currentUserId(), reason)) {
                    refresh(); // Recharger depuis la base
                    return true;
                }
                break;
            }
        }
    }
    return false;
}

bool AuthorizedMachineModel::removeMachine(int id)
{
    if (!m_permissionManager || !m_permissionManager->removeMachine(id))
        return false;

    refresh();
    return true;
}

void AuthorizedMachineModel::setPermissionManager(core::PermissionManager *manager)
{
    m_permissionManager = manager;
    if (m_permissionManager) {
        connect(m_permissionManager, &PermissionManager::machineChanged,
                this, [this](const models::AuthorizedMachine &) { refresh(); });
        connect(m_permissionManager, &PermissionManager::machineIdentityChanged,
                this, &AuthorizedMachineModel::refresh);
        refresh();
    }
}

void AuthorizedMachineModel::setUserManager(QObject *manager)
{
    m_userManager = manager;
}

int AuthorizedMachineModel::currentUserId() const
{
    if (auto *manager = qobject_cast<UserManager *>(m_userManager)) {
        return manager->currentUserId().value_or(-1);
    }
    return -1;
}

bool AuthorizedMachineModel::addMachineByCertificate(const QString &fingerprint, const QString &machineUuid,
                                                      const QString &ipAddress, const QString &hostname,
                                                      const QString &reason)
{
    if (!m_permissionManager) return false;
    const bool ok = m_permissionManager->authorizeMachineByCertificate(
        fingerprint, machineUuid, hostname, ipAddress, currentUserId(), reason);
    if (ok) refresh();
    return ok;
}

} // namespace core
