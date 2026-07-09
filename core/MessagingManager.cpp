#include "MessagingManager.h"

#include "DatabaseManager.h"
#include "Messaging/MessagingService.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QDebug>

namespace core {

MessagingManager::MessagingManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
{
}

MessagingManager::~MessagingManager()
{
}

void MessagingManager::setMessagingService(network::MessagingService *messagingService)
{
    m_messagingService = messagingService;
}

std::optional<models::Conversation> MessagingManager::getOrCreateConversation(qint64 userId1, qint64 userId2)
{
    if (!m_dbManager) {
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return std::nullopt;
    }

    if (userId1 == userId2) {
        m_lastError = MessagingManagerError::InvalidUser;
        m_lastErrorString = QStringLiteral("Cannot create conversation with same user");
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    // Chercher une conversation existante entre ces deux utilisateurs
    query.prepare(QStringLiteral(
        "SELECT id, type, name, participant1_id, participant2_id "
        "FROM Conversations "
        "WHERE type = 'individual' "
        "AND ((participant1_id = ? AND participant2_id = ?) "
        "OR (participant1_id = ? AND participant2_id = ?))"
    ));
    query.addBindValue(userId1);
    query.addBindValue(userId2);
    query.addBindValue(userId2);
    query.addBindValue(userId1);

    if (query.exec() && query.next()) {
        models::Conversation conv(
            query.value(0).toLongLong(),
            models::ConversationType::Individual,
            query.value(2).toString()
        );
        conv.setParticipant1Id(query.value(3).toLongLong());
        conv.setParticipant2Id(query.value(4).toLongLong());
        return conv;
    }

    // Creer une nouvelle conversation
    query.prepare(QStringLiteral(
        "INSERT INTO Conversations (type, name, participant1_id, participant2_id) "
        "VALUES ('individual', ?, ?, ?)"
    ));
    query.addBindValue(QStringLiteral("Conversation"));
    query.addBindValue(userId1);
    query.addBindValue(userId2);

    if (!query.exec()) {
        qWarning() << "Failed to create conversation:" << query.lastError().text();
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = query.lastError().text();
        return std::nullopt;
    }

    const qint64 conversationId = query.lastInsertId().toLongLong();
    models::Conversation conv(conversationId, models::ConversationType::Individual, QStringLiteral("Conversation"));
    conv.setParticipant1Id(userId1);
    conv.setParticipant2Id(userId2);
    return conv;
}

std::optional<models::Message> MessagingManager::sendMessage(qint64 conversationId, qint64 senderId, const QString &content)
{
    if (!m_dbManager) {
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return std::nullopt;
    }

    if (content.trimmed().isEmpty()) {
        m_lastError = MessagingManagerError::InvalidContent;
        m_lastErrorString = QStringLiteral("Message content cannot be empty");
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    // Inserer le message en base de donnees
    const QString timestamp = QDateTime::currentDateTime().toString(Qt::ISODate);
    const QString queryString = QStringLiteral(
        "INSERT INTO Messages (conversationId, senderId, content, timestamp, is_read) "
        "VALUES (%1, %2, '%3', '%4', 0)"
    ).arg(conversationId).arg(senderId).arg(content).arg(timestamp);

    if (!query.exec(queryString)) {
        qWarning() << "Failed to insert message:" << query.lastError().text();
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = query.lastError().text();
        return std::nullopt;
    }

    const qint64 messageId = query.lastInsertId().toLongLong();
    models::Message message(messageId, conversationId, senderId, content);

    // Envoyer le message via le reseau si le service est configure
    if (m_messagingService && m_messagingService->isConnected()) {
        // Pour simplifier, on envoie le contenu en JSON
        const QString jsonMessage = QStringLiteral("{\"type\":\"message\",\"conversationId\":%1,\"senderId\":%2,\"content\":\"%3\"}")
            .arg(conversationId)
            .arg(senderId)
            .arg(content);

        if (!m_messagingService->sendMessage(jsonMessage)) {
            qWarning() << "Failed to send message via network";
            // On ne retourne pas d'erreur ici car le message est deja en base
        }
    }

    emit messageSent(message);
    return message;
}

QVector<models::Message> MessagingManager::getMessages(qint64 conversationId, int limit)
{
    QVector<models::Message> messages;

    if (!m_dbManager) {
        return messages;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    query.prepare(QStringLiteral(
        "SELECT id, conversationId, senderId, content, timestamp, is_read "
        "FROM Messages "
        "WHERE conversationId = ? "
        "ORDER BY id ASC "
        "LIMIT ?"
    ));
    query.addBindValue(conversationId);
    query.addBindValue(limit);

    if (query.exec()) {
        while (query.next()) {
            models::Message msg(
                query.value(0).toLongLong(),
                query.value(1).toLongLong(),
                query.value(2).toLongLong(),
                query.value(3).toString()
            );
            msg.setTimestamp(query.value(4).toDateTime());
            msg.setRead(query.value(5).toBool());
            messages.append(msg);
        }
    }

    return messages;
}

QVector<models::Conversation> MessagingManager::getUserConversations(qint64 userId)
{
    QVector<models::Conversation> conversations;

    if (!m_dbManager) {
        return conversations;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    query.prepare(QStringLiteral(
        "SELECT id, type, name, participant1_id, participant2_id "
        "FROM Conversations "
        "WHERE participant1_id = ? OR participant2_id = ?"
    ));
    query.addBindValue(userId);
    query.addBindValue(userId);

    if (query.exec()) {
        while (query.next()) {
            models::Conversation conv(
                query.value(0).toLongLong(),
                models::ConversationType::Individual,
                query.value(2).toString()
            );
            conv.setParticipant1Id(query.value(3).toLongLong());
            conv.setParticipant2Id(query.value(4).toLongLong());
            conversations.append(conv);
        }
    }

    return conversations;
}

} // namespace core
