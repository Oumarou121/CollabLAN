#include "MessageRepository.h"

#include "DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
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

    const QString timestamp = message.timestamp().toString(Qt::ISODate);
    const QString queryString = QStringLiteral(
        "INSERT INTO Messages (conversationId, senderId, content, timestamp, is_read) "
        "VALUES (%1, %2, '%3', '%4', %5)"
    ).arg(message.conversationId())
     .arg(message.senderId())
     .arg(message.content())
     .arg(timestamp)
     .arg(message.isRead() ? 1 : 0);

    if (!query.exec(queryString)) {
        qWarning() << "Failed to insert message:" << query.lastError().text();
        return std::nullopt;
    }

    const qint64 messageId = query.lastInsertId().toLongLong();
    models::Message insertedMessage(message);
    insertedMessage.setId(messageId);
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
        "SELECT id, conversationId, senderId, content, timestamp, is_read "
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

} // namespace database
