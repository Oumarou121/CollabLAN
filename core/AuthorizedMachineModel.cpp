#include "AuthorizedMachineModel.h"
#include "PermissionManager.h"
#include "Database/Repositories/AuthorizedMachineRepository.h"
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
    case HostnameRole:
        return machine.hostname();
    case AuthorizedRole:
        return machine.isAuthorized();
    case AddedByRole:
        return machine.addedBy().value_or(-1);
    case AddedAtRole:
        return machine.addedAt().toString(Qt::ISODate);
    case ReasonRole:
        return machine.reason();
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> AuthorizedMachineModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[IpAddressRole] = "ipAddress";
    roles[HostnameRole] = "hostname";
    roles[AuthorizedRole] = "authorized";
    roles[AddedByRole] = "addedBy";
    roles[AddedAtRole] = "addedAt";
    roles[ReasonRole] = "reason";
    return roles;
}

void AuthorizedMachineModel::refresh()
{
    beginResetModel();
    m_machines.clear();
    
    // Charger depuis AuthorizedMachineRepository via PermissionManager
    if (m_permissionManager) {
        auto *permissionManager = qobject_cast<PermissionManager*>(m_permissionManager);
        if (permissionManager) {
            const auto machines = permissionManager->getAllMachines();
            for (const auto &machine : machines) {
                m_machines.append(machine);
            }
        }
    }
    
    endResetModel();
}

bool AuthorizedMachineModel::addMachine(const QString &ipAddress, const QString &hostname, const QString &reason)
{
    if (m_permissionManager) {
        auto *permissionManager = qobject_cast<PermissionManager*>(m_permissionManager);
        if (permissionManager) {
            // Obtenir l'ID de l'utilisateur courant depuis le DatabaseManager
            // Pour l'instant, on utilise 1 comme valeur par défaut (admin)
            const int currentUserId = 1;
            if (permissionManager->authorizeMachine(ipAddress, currentUserId, reason)) {
                refresh(); // Recharger depuis la base
                return true;
            }
        }
    }
    return false;
}

bool AuthorizedMachineModel::revokeMachine(int id, const QString &reason)
{
    if (m_permissionManager) {
        auto *permissionManager = qobject_cast<PermissionManager*>(m_permissionManager);
        if (permissionManager) {
            // Trouver l'adresse IP correspondant à l'ID
            for (int i = 0; i < m_machines.size(); ++i) {
                if (m_machines[i].id() == id) {
                    const int currentUserId = 1;
                    if (permissionManager->revokeMachine(m_machines[i].ipAddress(), currentUserId, reason)) {
                        refresh(); // Recharger depuis la base
                        return true;
                    }
                    break;
                }
            }
        }
    }
    return false;
}

bool AuthorizedMachineModel::authorizeMachine(int id, const QString &reason)
{
    if (m_permissionManager) {
        auto *permissionManager = qobject_cast<PermissionManager*>(m_permissionManager);
        if (permissionManager) {
            // Trouver l'adresse IP correspondant à l'ID
            for (int i = 0; i < m_machines.size(); ++i) {
                if (m_machines[i].id() == id) {
                    const int currentUserId = 1;
                    if (permissionManager->authorizeMachine(m_machines[i].ipAddress(), currentUserId, reason)) {
                        refresh(); // Recharger depuis la base
                        return true;
                    }
                    break;
                }
            }
        }
    }
    return false;
}

bool AuthorizedMachineModel::removeMachine(int id)
{
    for (int i = 0; i < m_machines.size(); ++i) {
        if (m_machines[i].id() == id) {
            beginRemoveRows(QModelIndex(), i, i);
            m_machines.removeAt(i);
            endRemoveRows();
            return true;
        }
    }
    return false;
}

void AuthorizedMachineModel::setPermissionManager(QObject *manager)
{
    m_permissionManager = manager;
}

} // namespace core
