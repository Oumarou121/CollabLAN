#ifndef CORE_AUTHORIZEDMACHINEMODEL_H
#define CORE_AUTHORIZEDMACHINEMODEL_H

#include <QAbstractListModel>
#include <QVector>
#include "models/AuthorizedMachine.h"

namespace core {

class PermissionManager;

/**
 * @brief Modèle QML pour la liste des machines autorisées/révoquées (issue #68, #69).
 */
class AuthorizedMachineModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        IpAddressRole,
        HostnameRole,
        AuthorizedRole,
        AddedByRole,
        AddedAtRole,
        ReasonRole
    };

    explicit AuthorizedMachineModel(QObject *parent = nullptr);
    ~AuthorizedMachineModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool addMachine(const QString &ipAddress, const QString &hostname, const QString &reason);
    Q_INVOKABLE bool revokeMachine(int id, const QString &reason);
    Q_INVOKABLE bool authorizeMachine(int id, const QString &reason);
    Q_INVOKABLE bool removeMachine(int id);

    void setPermissionManager(core::PermissionManager *manager);

private:
    QVector<models::AuthorizedMachine> m_machines;
    core::PermissionManager *m_permissionManager = nullptr;
};

} // namespace core

#endif // CORE_AUTHORIZEDMACHINEMODEL_H
