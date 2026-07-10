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
    
    // TODO: Charger depuis AuthorizedMachineRepository via PermissionManager
    // Pour l'instant, données de test
    m_machines.append(models::AuthorizedMachine(1, "192.168.1.10", "PC-Alice", true, 1, QDateTime::currentDateTime(), "Machine par défaut"));
    m_machines.append(models::AuthorizedMachine(2, "192.168.1.11", "PC-Bilal", true, 1, QDateTime::currentDateTime(), "Machine par défaut"));
    
    endResetModel();
}

bool AuthorizedMachineModel::addMachine(const QString &ipAddress, const QString &hostname, const QString &reason)
{
    // TODO: Appeler PermissionManager.authorizeMachine()
    beginInsertRows(QModelIndex(), m_machines.size(), m_machines.size());
    models::AuthorizedMachine machine;
    machine.setIpAddress(ipAddress);
    machine.setHostname(hostname);
    machine.setAuthorized(true);
    machine.setReason(reason);
    machine.setAddedAt(QDateTime::currentDateTime());
    m_machines.append(machine);
    endInsertRows();
    return true;
}

bool AuthorizedMachineModel::revokeMachine(int id, const QString &reason)
{
    // TODO: Appeler PermissionManager.revokeMachine()
    for (int i = 0; i < m_machines.size(); ++i) {
        if (m_machines[i].id() == id) {
            m_machines[i].setAuthorized(false);
            m_machines[i].setReason(reason);
            emit dataChanged(index(i), index(i));
            return true;
        }
    }
    return false;
}

bool AuthorizedMachineModel::authorizeMachine(int id, const QString &reason)
{
    // TODO: Appeler PermissionManager.authorizeMachine()
    for (int i = 0; i < m_machines.size(); ++i) {
        if (m_machines[i].id() == id) {
            m_machines[i].setAuthorized(true);
            m_machines[i].setReason(reason);
            emit dataChanged(index(i), index(i));
            return true;
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
