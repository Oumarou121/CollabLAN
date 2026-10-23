#ifndef CORE_AUTHORIZEDMACHINEMODEL_H
#define CORE_AUTHORIZEDMACHINEMODEL_H

#include <QAbstractListModel>
#include <QHash>
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
        MachineIdRole, // Alias pour UuidRole pour clarifier l'utilisation
        CertificateFingerprintRole,
        LastIpAddressRole,
        HostnameRole,
        AuthorizedRole,
        StatusRole,
        AddedByRole,
        AddedAtRole,
        ReasonRole,
        LastUserUuidRole,
        LastUserNameRole
    };
    Q_ENUM(Roles)

    // Identifiants de roles lisibles depuis QML via l'instance
    // (ex. authorizedMachineModel.AuthorizedRole). Q_ENUM seul ne suffit
    // PAS : pour un objet expose par setContextProperty, une valeur d'enum
    // lue via l'instance vaut "undefined" en QML (verifie sous Qt 6.11), et
    // data() interrogeait alors Qt::DisplayRole -> QVariant() (compteurs de
    // machines autorisees, badges et liste des postes hors ligne faux).
    Q_PROPERTY(int IdRole READ idRoleId CONSTANT)
    Q_PROPERTY(int IpAddressRole READ ipAddressRoleId CONSTANT)
    Q_PROPERTY(int MachineIdRole READ machineIdRoleId CONSTANT)
    Q_PROPERTY(int CertificateFingerprintRole READ certificateFingerprintRoleId CONSTANT)
    Q_PROPERTY(int HostnameRole READ hostnameRoleId CONSTANT)
    Q_PROPERTY(int AuthorizedRole READ authorizedRoleId CONSTANT)
    Q_PROPERTY(int StatusRole READ statusRoleId CONSTANT)
    Q_PROPERTY(int LastUserNameRole READ lastUserNameRoleId CONSTANT)
    Q_PROPERTY(int LastUserUuidRole READ lastUserUuidRoleId CONSTANT)
    int idRoleId() const { return IdRole; }
    int ipAddressRoleId() const { return IpAddressRole; }
    int machineIdRoleId() const { return MachineIdRole; }
    int certificateFingerprintRoleId() const { return CertificateFingerprintRole; }
    int hostnameRoleId() const { return HostnameRole; }
    int authorizedRoleId() const { return AuthorizedRole; }
    int statusRoleId() const { return StatusRole; }
    int lastUserNameRoleId() const { return LastUserNameRole; }
    int lastUserUuidRoleId() const { return LastUserUuidRole; }

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
    /// Noms des comptes par uuid, relus a chaque rafraichissement.
    QHash<QString, QString> m_userNames;
};

} // namespace core

#endif // CORE_AUTHORIZEDMACHINEMODEL_H