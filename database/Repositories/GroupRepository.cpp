#include "GroupRepository.h"

#include "DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QDebug>

namespace database {

GroupRepository::GroupRepository(DatabaseManager *dbManager)
    : m_dbManager(dbManager)
{
}

GroupRepository::~GroupRepository()
{
}

std::optional<models::Group> GroupRepository::insert(const models::Group &group)
{
    if (!m_dbManager) {
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "INSERT INTO Groups (name, owner_id) "
        "VALUES ('%1', %2)"
    ).arg(group.name()).arg(group.ownerId());

    if (!query.exec(queryString)) {
        qWarning() << "Failed to insert group:" << query.lastError().text();
        return std::nullopt;
    }

    const qint64 groupId = query.lastInsertId().toLongLong();
    models::Group insertedGroup(group);
    insertedGroup.setId(groupId);

    // Insert members
    for (qint64 memberId : group.memberIds()) {
        addMember(groupId, memberId);
    }

    return insertedGroup;
}

bool GroupRepository::update(const models::Group &group)
{
    if (!m_dbManager) {
        return false;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "UPDATE Groups SET name = '%1' WHERE id = %2"
    ).arg(group.name()).arg(group.id());

    if (!query.exec(queryString)) {
        qWarning() << "Failed to update group:" << query.lastError().text();
        return false;
    }

    // Update members: remove all and re-add
    QSqlQuery deleteQuery(db);
    const QString deleteQueryString = QStringLiteral(
        "DELETE FROM GroupMembers WHERE group_id = %1"
    ).arg(group.id());
    deleteQuery.exec(deleteQueryString);

    for (qint64 memberId : group.memberIds()) {
        addMember(group.id(), memberId);
    }

    return true;
}

bool GroupRepository::remove(qint64 groupId)
{
    if (!m_dbManager) {
        return false;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    // Delete members first
    const QString deleteMembersQuery = QStringLiteral(
        "DELETE FROM GroupMembers WHERE group_id = %1"
    ).arg(groupId);
    query.exec(deleteMembersQuery);

    // Delete group
    const QString deleteGroupQuery = QStringLiteral(
        "DELETE FROM Groups WHERE id = %1"
    ).arg(groupId);

    return query.exec(deleteGroupQuery);
}

std::optional<models::Group> GroupRepository::getById(qint64 groupId)
{
    if (!m_dbManager) {
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "SELECT id, name, owner_id FROM Groups WHERE id = %1"
    ).arg(groupId);

    if (query.exec(queryString) && query.next()) {
        models::Group group(
            query.value(0).toLongLong(),
            query.value(1).toString()
        );
        group.setOwnerId(query.value(2).toLongLong());

        // Load members
        const QVector<qint64> members = getGroupMembers(groupId);
        for (qint64 memberId : members) {
            group.addMember(memberId);
        }

        return group;
    }

    return std::nullopt;
}

QVector<models::Group> GroupRepository::getByUserId(qint64 userId)
{
    QVector<models::Group> groups;

    if (!m_dbManager) {
        return groups;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "SELECT g.id, g.name, g.owner_id "
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

            // Load members
            const QVector<qint64> members = getGroupMembers(group.id());
            for (qint64 memberId : members) {
                group.addMember(memberId);
            }

            groups.append(group);
        }
    }

    return groups;
}

bool GroupRepository::addMember(qint64 groupId, qint64 userId)
{
    if (!m_dbManager) {
        return false;
    }

    // Check if already a member
    if (isMember(groupId, userId)) {
        return true;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "INSERT INTO GroupMembers (group_id, user_id) "
        "VALUES (%1, %2)"
    ).arg(groupId).arg(userId);

    if (!query.exec(queryString)) {
        qWarning() << "Failed to add member to group:" << query.lastError().text();
        return false;
    }

    return true;
}

bool GroupRepository::removeMember(qint64 groupId, qint64 userId)
{
    if (!m_dbManager) {
        return false;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "DELETE FROM GroupMembers "
        "WHERE group_id = %1 AND user_id = %2"
    ).arg(groupId).arg(userId);

    return query.exec(queryString);
}

QVector<qint64> GroupRepository::getGroupMembers(qint64 groupId)
{
    QVector<qint64> members;

    if (!m_dbManager) {
        return members;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "SELECT user_id FROM GroupMembers WHERE group_id = %1"
    ).arg(groupId);

    if (query.exec(queryString)) {
        while (query.next()) {
            members.append(query.value(0).toLongLong());
        }
    }

    return members;
}

bool GroupRepository::isMember(qint64 groupId, qint64 userId)
{
    if (!m_dbManager) {
        return false;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "SELECT COUNT(*) FROM GroupMembers "
        "WHERE group_id = %1 AND user_id = %2"
    ).arg(groupId).arg(userId);

    if (query.exec(queryString) && query.next()) {
        return query.value(0).toInt() > 0;
    }

    return false;
}

} // namespace database
