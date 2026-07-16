#include "GroupRepository.h"

#include "DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QVariant>
#include <QUuid>
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

    // uuid : identifiant stable inter-postes (independant de l'id local
    // AUTOINCREMENT), utilise comme record_uuid par SyncLogRepository lors
    // de la reconciliation post-panne. Jamais force depuis l'exterieur : on
    // en genere un nouveau si absent, comme UserRepository::create().
    const QString uuid = group.uuid().isEmpty()
        ? QUuid::createUuid().toString(QUuid::WithoutBraces)
        : group.uuid();

    query.prepare(QStringLiteral(
        "INSERT INTO Groups (name, owner_id, conversation_id, uuid) "
        "VALUES (:name, :owner_id, :conversation_id, :uuid)"));
    query.bindValue(QStringLiteral(":name"), group.name());
    query.bindValue(QStringLiteral(":owner_id"), group.ownerId());
    if (group.conversationId() != 0) {
        query.bindValue(QStringLiteral(":conversation_id"), group.conversationId());
    } else {
        query.bindValue(QStringLiteral(":conversation_id"), QVariant(QMetaType(QMetaType::LongLong)));
    }
    query.bindValue(QStringLiteral(":uuid"), uuid);

    if (!query.exec()) {
        qWarning() << "Failed to insert group:" << query.lastError().text();
        return std::nullopt;
    }

    const qint64 groupId = query.lastInsertId().toLongLong();
    models::Group insertedGroup(group);
    insertedGroup.setId(groupId);
    insertedGroup.setUuid(uuid);

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

    query.prepare(QStringLiteral(
        "UPDATE Groups SET name = :name, conversation_id = :conversation_id WHERE id = :id"));
    query.bindValue(QStringLiteral(":name"), group.name());
    if (group.conversationId() != 0) {
        query.bindValue(QStringLiteral(":conversation_id"), group.conversationId());
    } else {
        query.bindValue(QStringLiteral(":conversation_id"), QVariant(QMetaType(QMetaType::LongLong)));
    }
    query.bindValue(QStringLiteral(":id"), group.id());

    if (!query.exec()) {
        qWarning() << "Failed to update group:" << query.lastError().text();
        return false;
    }

    // Update members: remove all and re-add
    QSqlQuery deleteQuery(db);
    deleteQuery.prepare(QStringLiteral("DELETE FROM GroupMembers WHERE group_id = :group_id"));
    deleteQuery.bindValue(QStringLiteral(":group_id"), group.id());
    deleteQuery.exec();

    for (qint64 memberId : group.memberIds()) {
        addMember(group.id(), memberId);
    }

    return true;
}

bool GroupRepository::setConversationId(qint64 groupId, qint64 conversationId)
{
    if (!m_dbManager) {
        return false;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    query.prepare(QStringLiteral("UPDATE Groups SET conversation_id = :conversation_id WHERE id = :id"));
    query.bindValue(QStringLiteral(":conversation_id"), conversationId);
    query.bindValue(QStringLiteral(":id"), groupId);

    if (!query.exec()) {
        qWarning() << "Failed to link group to conversation:" << query.lastError().text();
        return false;
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
    QSqlQuery deleteMembers(db);
    deleteMembers.prepare(QStringLiteral("DELETE FROM GroupMembers WHERE group_id = :group_id"));
    deleteMembers.bindValue(QStringLiteral(":group_id"), groupId);
    deleteMembers.exec();

    // Delete group
    query.prepare(QStringLiteral("DELETE FROM Groups WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), groupId);
    return query.exec();
}

std::optional<models::Group> GroupRepository::getById(qint64 groupId)
{
    if (!m_dbManager) {
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "SELECT id, name, owner_id, conversation_id, uuid FROM Groups WHERE id = :id");
    query.prepare(queryString);
    query.bindValue(QStringLiteral(":id"), groupId);

    if (query.exec() && query.next()) {
        models::Group group(
            query.value(0).toLongLong(),
            query.value(1).toString()
        );
        group.setOwnerId(query.value(2).toLongLong());
        group.setConversationId(query.value(3).toLongLong());
        group.setUuid(query.value(4).toString());

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
        "SELECT g.id, g.name, g.owner_id, g.conversation_id, g.uuid "
        "FROM Groups g "
        "INNER JOIN GroupMembers gm ON g.id = gm.group_id "
        "WHERE gm.user_id = :user_id");
    query.prepare(queryString);
    query.bindValue(QStringLiteral(":user_id"), userId);

    if (query.exec()) {
        while (query.next()) {
            models::Group group(
                query.value(0).toLongLong(),
                query.value(1).toString()
            );
            group.setOwnerId(query.value(2).toLongLong());
            group.setConversationId(query.value(3).toLongLong());
            group.setUuid(query.value(4).toString());

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
        "VALUES (:group_id, :user_id)");
    query.prepare(queryString);
    query.bindValue(QStringLiteral(":group_id"), groupId);
    query.bindValue(QStringLiteral(":user_id"), userId);

    if (!query.exec()) {
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
        "WHERE group_id = :group_id AND user_id = :user_id");
    query.prepare(queryString);
    query.bindValue(QStringLiteral(":group_id"), groupId);
    query.bindValue(QStringLiteral(":user_id"), userId);

    return query.exec();
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
        "SELECT user_id FROM GroupMembers WHERE group_id = :group_id");
    query.prepare(queryString);
    query.bindValue(QStringLiteral(":group_id"), groupId);

    if (query.exec()) {
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
        "WHERE group_id = :group_id AND user_id = :user_id");
    query.prepare(queryString);
    query.bindValue(QStringLiteral(":group_id"), groupId);
    query.bindValue(QStringLiteral(":user_id"), userId);

    if (query.exec() && query.next()) {
        return query.value(0).toInt() > 0;
    }

    return false;
}

std::optional<models::Group> GroupRepository::findByUuid(const QString &uuid)
{
    if (!m_dbManager || uuid.isEmpty()) {
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT id, name, owner_id, conversation_id, uuid FROM Groups WHERE uuid = :uuid"));
    query.bindValue(QStringLiteral(":uuid"), uuid);

    if (!query.exec() || !query.next()) {
        return std::nullopt;
    }

    models::Group group(
        query.value(0).toLongLong(),
        query.value(1).toString()
    );
    group.setOwnerId(query.value(2).toLongLong());
    group.setConversationId(query.value(3).toLongLong());
    group.setUuid(query.value(4).toString());

    const qint64 groupId = group.id();
    const QVector<qint64> members = getGroupMembers(groupId);
    for (qint64 memberId : members) {
        group.addMember(memberId);
    }

    return group;
}

} // namespace database