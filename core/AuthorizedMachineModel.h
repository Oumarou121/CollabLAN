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
        UuidRole,
        CertificateFingerprintRole,
        LastIpAddressRole,
        HostnameRole,
        AuthorizedRole,
        StatusRole,
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
    Q_INVOKABLE bool addMachineByCertificate(const QString &fingerprint, const QString &machineUuid,
                                             const QString &ipAddress, const QString &hostname,
                                             const QString &reason);
    Q_INVOKABLE bool revokeMachine(int id, const QString &reason);
    Q_INVOKABLE bool authorizeMachine(int id, const QString &reason);
    Q_INVOKABLE bool removeMachine(int id);

    void setPermissionManager(core::PermissionManager *manager);
    void setUserManager(QObject *manager);

private:
    /// Id de l'utilisateur admin actuellement connecte, ou -1 si inconnu
    /// (UserManager absent ou personne connectee). Utilise comme added_by
    /// pour que l'audit reflete qui a reellement autorise/revoque la machine,
    /// plutot qu'un id fige.
    int currentUserId() const;

    QVector<models::AuthorizedMachine> m_machines;
    core::PermissionManager *m_permissionManager = nullptr;
    QObject *m_userManager = nullptr;
};

} // namespace core

#endif // CORE_AUTHORIZEDMACHINEMODEL_H
