#ifndef CORE_USERMANAGEMENTMODEL_H
#define CORE_USERMANAGEMENTMODEL_H

#include <QAbstractListModel>
#include <QVector>
#include "models/User.h"

namespace core {

/**
 * @brief Modèle QML pour la gestion des utilisateurs (issue #69).
 */
class UserManagementModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        IpAddressRole,
        StatusRole,
        RoleRole,
        IsAdminRole,
        CreatedAtRole
    };

    explicit UserManagementModel(QObject *parent = nullptr);
    ~UserManagementModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool createUser(const QString &name, const QString &password, bool isAdmin);
    Q_INVOKABLE bool deleteUser(int id);
    Q_INVOKABLE bool changeRole(int id, bool isAdmin);
    Q_INVOKABLE bool changeStatus(int id, const QString &status);

    void setUserManager(QObject *manager);

private:
    QVector<models::User> m_users;
    QObject *m_userManager = nullptr;
};

} // namespace core

#endif // CORE_USERMANAGEMENTMODEL_H
