#include "GroupManager.h"

#include "DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QDebug>

namespace core {

GroupManager::GroupManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
{
}

GroupManager::~GroupManager()
{
}

std::optional<models::Group> GroupManager::createGroup(const QString &name, qint64 ownerId, const QVector<qint64> &initialMembers)
{
    if (!m_dbManager) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return std::nullopt;
    }

    if (name.trimmed().isEmpty()) {
        m_lastError = GroupManagerError::InvalidName;
        m_lastErrorString = QStringLiteral("Group name cannot be empty");
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    // Creer le groupe
    query.prepare(QStringLiteral(
        "INSERT INTO Groups (name, owner_id) "
        "VALUES (:name, :owner_id)"));
    query.bindValue(QStringLiteral(":name"), name);
    query.bindValue(QStringLiteral(":owner_id"), ownerId);

    if (!query.exec()) {
        qWarning() << "Failed to create group:" << query.lastError().text();
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = query.lastError().text();
        return std::nullopt;
    }

    const qint64 groupId = query.lastInsertId().toLongLong();
    models::Group group(groupId, name);
    group.setOwnerId(ownerId);

    // Creer la Conversation (type='group') associee, pour reutiliser telle
    // quelle la messagerie existante (Messages.conversationId) : envoyer/
    // recevoir un message dans un groupe ne differe alors en rien d'une
    // conversation individuelle du point de vue de MessagingManager.
    QSqlQuery convQuery(db);
    convQuery.prepare(QStringLiteral(
        "INSERT INTO Conversations (type, name) VALUES ('group', :name)"));
    convQuery.bindValue(QStringLiteral(":name"), name);

    if (!convQuery.exec()) {
        qWarning() << "Failed to create conversation for group:" << convQuery.lastError().text();
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = convQuery.lastError().text();
        return std::nullopt;
    }

    const qint64 conversationId = convQuery.lastInsertId().toLongLong();
    group.setConversationId(conversationId);

    QSqlQuery linkQuery(db);
    const QString linkQueryString = QStringLiteral(
        "UPDATE Groups SET conversation_id = %1 WHERE id = %2"
    ).arg(conversationId).arg(groupId);

    if (!linkQuery.exec(linkQueryString)) {
        qWarning() << "Failed to link group to conversation:" << linkQuery.lastError().text();
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = linkQuery.lastError().text();
        return std::nullopt;
    }

    // Ajouter le propriétaire comme membre
    group.addMember(ownerId);

    // Ajouter les membres initiaux
    for (qint64 memberId : initialMembers) {
        if (memberId != ownerId) {
            group.addMember(memberId);
        }
    }

    // Sauvegarder les membres dans la table GroupMembers
    for (qint64 memberId : group.memberIds()) {
        QSqlQuery memberQuery(db);
        const QString memberQueryString = QStringLiteral(
            "INSERT INTO GroupMembers (group_id, user_id) "
            "VALUES (%1, %2)"
        ).arg(groupId).arg(memberId);

        if (!memberQuery.exec(memberQueryString)) {
            qWarning() << "Failed to add member to group:" << memberQuery.lastError().text();
        }
    }

    emit groupCreated(group);
    return group;
}

bool GroupManager::addMember(qint64 groupId, qint64 memberId, qint64 requesterId)
{
    if (!m_dbManager) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return false;
    }

    // Verifier que le demandeur est le propriétaire
    const auto group = getGroup(groupId);
    if (!group.has_value()) {
        m_lastError = GroupManagerError::InvalidGroup;
        m_lastErrorString = QStringLiteral("Group not found");
        return false;
    }

    if (group->ownerId() != requesterId) {
        m_lastError = GroupManagerError::NotOwner;
        m_lastErrorString = QStringLiteral("Only the owner can add members");
        return false;
    }

    // Verifier que le membre n'est pas déjà dans le groupe
    if (group->memberIds().contains(memberId)) {
        return true;  // Déjà membre
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "INSERT INTO GroupMembers (group_id, user_id) "
        "VALUES (%1, %2)"
    ).arg(groupId).arg(memberId);

    if (!query.exec(queryString)) {
        qWarning() << "Failed to add member to group:" << query.lastError().text();
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = query.lastError().text();
        return false;
    }

    emit memberAdded(groupId, memberId);
    return true;
}

bool GroupManager::removeMember(qint64 groupId, qint64 memberId, qint64 requesterId)
{
    if (!m_dbManager) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return false;
    }

    // Verifier que le demandeur est le propriétaire
    const auto group = getGroup(groupId);
    if (!group.has_value()) {
        m_lastError = GroupManagerError::InvalidGroup;
        m_lastErrorString = QStringLiteral("Group not found");
        return false;
    }

    if (group->ownerId() != requesterId) {
        m_lastError = GroupManagerError::NotOwner;
        m_lastErrorString = QStringLiteral("Only the owner can remove members");
        return false;
    }

    // On ne peut pas retirer le propriétaire
    if (memberId == group->ownerId()) {
        m_lastError = GroupManagerError::InvalidUser;
        m_lastErrorString = QStringLiteral("Cannot remove the group owner");
        return false;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "DELETE FROM GroupMembers "
        "WHERE group_id = %1 AND user_id = %2"
    ).arg(groupId).arg(memberId);

    if (!query.exec(queryString)) {
        qWarning() << "Failed to remove member from group:" << query.lastError().text();
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = query.lastError().text();
        return false;
    }

    emit memberRemoved(groupId, memberId);
    return true;
}

QVector<models::Group> GroupManager::getUserGroups(qint64 userId)
{
    QVector<models::Group> groups;

    if (!m_dbManager) {
        return groups;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "SELECT g.id, g.name, g.owner_id, g.conversation_id "
        "FROM Groups g "
        "INNER JOIN GroupMembers gm ON g.id = gm.group_id "
        "WHERE gm.user_id = %1"
    ).arg(userId);

    if (query.exec(queryString)) {
        while (query.next()) {
            models::Group group(
                query.value(0).toLongLong(),
                query.value(1).toString()
            );
            group.setOwnerId(query.value(2).toLongLong());
            group.setConversationId(query.value(3).toLongLong());

            // Charger les membres
            QSqlQuery memberQuery(db);
            const QString memberQueryString = QStringLiteral(
                "SELECT user_id FROM GroupMembers WHERE group_id = %1"
            ).arg(group.id());

            if (memberQuery.exec(memberQueryString)) {
                while (memberQuery.next()) {
                    group.addMember(memberQuery.value(0).toLongLong());
                }
            }

            groups.append(group);
        }
    }

    return groups;
}

std::optional<models::Group> GroupManager::getGroup(qint64 groupId)
{
    if (!m_dbManager) {
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "SELECT id, name, owner_id, conversation_id FROM Groups WHERE id = %1"
    ).arg(groupId);

    if (query.exec(queryString) && query.next()) {
        models::Group group(
            query.value(0).toLongLong(),
            query.value(1).toString()
        );
        group.setOwnerId(query.value(2).toLongLong());
        group.setConversationId(query.value(3).toLongLong());

        // Charger les membres
        QSqlQuery memberQuery(db);
        const QString memberQueryString = QStringLiteral(
            "SELECT user_id FROM GroupMembers WHERE group_id = %1"
        ).arg(groupId);

        if (memberQuery.exec(memberQueryString)) {
            while (memberQuery.next()) {
                group.addMember(memberQuery.value(0).toLongLong());
            }
        }

        return group;
    }

    return std::nullopt;
}

} // namespace core
