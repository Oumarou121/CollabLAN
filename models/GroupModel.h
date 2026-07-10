#ifndef MODELS_GROUPMODEL_H
#define MODELS_GROUPMODEL_H

#include <QAbstractListModel>
#include <QVector>
#include "Group.h"

namespace models {

/**
 * @brief Modèle QML pour exposer les groupes à l'interface.
 */
class GroupModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum GroupRoles {
        GroupIdRole = Qt::UserRole + 1,
        NameRole,
        OwnerIdRole,
        MemberCountRole,
        ConversationIdRole
    };

    explicit GroupModel(QObject *parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

    void setGroups(const QVector<Group> &groups);
    void addGroup(const Group &group);
    void clear();

    qint64 currentUserId() const { return m_currentUserId; }
    void setCurrentUserId(qint64 userId) { m_currentUserId = userId; }

private:
    QVector<Group> m_groups;
    qint64 m_currentUserId = 1;
};

} // namespace models

#endif // MODELS_GROUPMODEL_H
