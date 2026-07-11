#include "MessageRepository.h"

#include "DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QUuid>
#include <QDebug>

namespace database {

MessageRepository::MessageRepository(DatabaseManager *dbManager)
    : m_dbManager(dbManager)
{
}

MessageRepository::~MessageRepository()
{
}

std::optional<models::Message> MessageRepository::insert(const models::Message &message)
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
    const QString uuid = message.uuid().isEmpty()
        ? QUuid::createUuid().toString(QUuid::WithoutBraces)
        : message.uuid();

    const QString timestamp = message.timestamp().toString(Qt::ISODate);
    query.prepare(QStringLiteral(
        "INSERT INTO Messages (conversationId, senderId, content, timestamp, is_read, uuid) "
        "VALUES (:conversationId, :senderId, :content, :timestamp, :isRead, :uuid)"
    ));
    query.bindValue(QStringLiteral(":conversationId"), message.conversationId());
    query.bindValue(QStringLiteral(":senderId"), message.senderId());
    query.bindValue(QStringLiteral(":content"), message.content());
    query.bindValue(QStringLiteral(":timestamp"), timestamp);
    query.bindValue(QStringLiteral(":isRead"), message.isRead() ? 1 : 0);
    query.bindValue(QStringLiteral(":uuid"), uuid);

    if (!query.exec()) {
        qWarning() << "Failed to insert message:" << query.lastError().text();
        return std::nullopt;
    }

    const qint64 messageId = query.lastInsertId().toLongLong();
    models::Message insertedMessage(message);
    insertedMessage.setId(messageId);
    insertedMessage.setUuid(uuid);
    return insertedMessage;
}

QVector<models::Message> MessageRepository::getMessages(qint64 conversationId, int limit, int offset)
{
    QVector<models::Message> messages;

    if (!m_dbManager) {
        return messages;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "SELECT id, conversationId, senderId, content, timestamp, is_read, uuid "
        "FROM Messages "
        "WHERE conversationId = %1 "
        "ORDER BY id ASC "
        "LIMIT %2 OFFSET %3"
    ).arg(conversationId).arg(limit).arg(offset);

    if (query.exec(queryString)) {
        while (query.next()) {
            models::Message msg(
                query.value(0).toLongLong(),
                query.value(1).toLongLong(),
                query.value(2).toLongLong(),
                query.value(3).toString()
            );
            msg.setTimestamp(QDateTime::fromString(query.value(4).toString(), Qt::ISODate));
            msg.setRead(query.value(5).toBool());
            msg.setUuid(query.value(6).toString());
            messages.append(msg);
        }
    }

    return messages;
}

int MessageRepository::getMessageCount(qint64 conversationId)
{
    if (!m_dbManager) {
        return 0;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "SELECT COUNT(*) FROM Messages WHERE conversationId = %1"
    ).arg(conversationId);

    if (query.exec(queryString) && query.next()) {
        return query.value(0).toInt();
    }

    return 0;
}

bool MessageRepository::markAsRead(qint64 messageId)
{
    if (!m_dbManager) {
        return false;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "UPDATE Messages SET is_read = 1 WHERE id = %1"
    ).arg(messageId);

    return query.exec(queryString);
}

bool MessageRepository::markConversationAsRead(qint64 conversationId, qint64 userId)
{
    if (!m_dbManager) {
        return false;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    const QString queryString = QStringLiteral(
        "UPDATE Messages SET is_read = 1 "
        "WHERE conversationId = %1 AND senderId != %2"
    ).arg(conversationId).arg(userId);

    return query.exec(queryString);
}

std::optional<models::Message> MessageRepository::findByUuid(const QString &uuid) const
{
    if (!m_dbManager || uuid.isEmpty()) {
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT id, conversationId, senderId, content, timestamp, is_read, uuid "
        "FROM Messages WHERE uuid = :uuid"));
    query.bindValue(QStringLiteral(":uuid"), uuid);

    if (!query.exec() || !query.next()) {
        return std::nullopt;
    }

    models::Message msg(
        query.value(0).toLongLong(),
        query.value(1).toLongLong(),
        query.value(2).toLongLong(),
        query.value(3).toString()
    );
    msg.setTimestamp(QDateTime::fromString(query.value(4).toString(), Qt::ISODate));
    msg.setRead(query.value(5).toBool());
    msg.setUuid(query.value(6).toString());
    return msg;
}

} // namespace database