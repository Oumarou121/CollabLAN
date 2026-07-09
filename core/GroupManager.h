#ifndef CORE_GROUPMANAGER_H
#define CORE_GROUPMANAGER_H

#include <QObject>
#include <QString>
#include <QVector>
#include <optional>

#include "models/Group.h"

namespace database {
class DatabaseManager;
}

namespace core {

enum class GroupManagerError {
    None,
    InvalidUser,
    InvalidGroup,
    InvalidName,
    DatabaseError,
    NotOwner
};

/**
 * @brief Gestion des groupes de discussion.
 *
 * Gere la creation de groupes, l'ajout/retrait de membres,
 * et l'envoi de messages dans les groupes.
 */
class GroupManager : public QObject
{
    Q_OBJECT

public:
    explicit GroupManager(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~GroupManager() override;

    /// Cree un nouveau groupe avec un nom et des membres initiaux.
    std::optional<models::Group> createGroup(const QString &name, qint64 ownerId, const QVector<qint64> &initialMembers);

    /// Ajoute un membre a un groupe.
    bool addMember(qint64 groupId, qint64 memberId, qint64 requesterId);

    /// Retire un membre d'un groupe.
    bool removeMember(qint64 groupId, qint64 memberId, qint64 requesterId);

    /// Recupere tous les groupes d'un utilisateur.
    QVector<models::Group> getUserGroups(qint64 userId);

    /// Recupere un groupe par son ID.
    std::optional<models::Group> getGroup(qint64 groupId);

    /// Derniere erreur survenue.
    GroupManagerError lastError() const { return m_lastError; }
    QString lastErrorString() const { return m_lastErrorString; }

signals:
    /// Emis lorsqu'un groupe est cree.
    void groupCreated(const models::Group &group);

    /// Emis lorsqu'un membre est ajoute a un groupe.
    void memberAdded(qint64 groupId, qint64 memberId);

    /// Emis lorsqu'un membre est retire d'un groupe.
    void memberRemoved(qint64 groupId, qint64 memberId);

private:
    database::DatabaseManager *m_dbManager = nullptr;
    GroupManagerError m_lastError = GroupManagerError::None;
    QString m_lastErrorString;
};

} // namespace core

#endif // CORE_GROUPMANAGER_H
