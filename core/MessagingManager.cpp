#include "MessagingManager.h"

#include "DatabaseManager.h"
#include "Messaging/MessagingService.h"
#include "Messaging/MessagingServer.h"
#include "NotificationManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
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

void MessagingManager::setNotificationManager(NotificationManager *notificationManager)
{
    m_notificationManager = notificationManager;

    // Connecter le signal messageReceived au slot du NotificationManager
    if (m_notificationManager) {
        connect(this, &MessagingManager::messageReceived,
                m_notificationManager, &NotificationManager::onMessageReceived);
    }
}

void MessagingManager::setMessagingServer(network::MessagingServer *messagingServer)
{
    m_messagingServer = messagingServer;
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

    // Inserer le message en base de donnees (requete preparee : evite toute
    // injection SQL et les erreurs de syntaxe si `content` contient une
    // apostrophe, ex. "l'ami" ou "it's").
    const QString timestamp = QDateTime::currentDateTime().toString(Qt::ISODate);
    query.prepare(QStringLiteral(
        "INSERT INTO Messages (conversationId, senderId, content, timestamp, is_read) "
        "VALUES (:conversationId, :senderId, :content, :timestamp, 0)"
    ));
    query.bindValue(QStringLiteral(":conversationId"), conversationId);
    query.bindValue(QStringLiteral(":senderId"), senderId);
    query.bindValue(QStringLiteral(":content"), content);
    query.bindValue(QStringLiteral(":timestamp"), timestamp);

    if (!query.exec()) {
        qWarning() << "Failed to insert message:" << query.lastError().text();
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = query.lastError().text();
        return std::nullopt;
    }

    const qint64 messageId = query.lastInsertId().toLongLong();
    models::Message message(messageId, conversationId, senderId, content);

    // Payload reseau, envoye via MessagingService (connexion sortante,
    // point-a-point) et/ou diffuse via MessagingServer (connexions
    // entrantes) ci-dessous.
    QJsonObject payload;
    payload.insert(QStringLiteral("type"), QStringLiteral("message"));
    payload.insert(QStringLiteral("conversationId"), conversationId);
    payload.insert(QStringLiteral("senderId"), senderId);
    payload.insert(QStringLiteral("content"), content);
    const QString jsonMessage = QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));

    // Envoyer le message via le reseau si le service est configure
    if (m_messagingService && m_messagingService->isConnected()) {
        if (!m_messagingService->sendMessage(jsonMessage)) {
            qWarning() << "Failed to send message via network";
            // On ne retourne pas d'erreur ici car le message est deja en base
        }
    }

    // Diffuse egalement a tous les clients connectes a notre serveur : pour
    // une conversation de groupe, chaque membre connecte a ce poste doit
    // recevoir le message (MessagingService ne gere qu'une connexion
    // sortante point-a-point, insuffisante des que le groupe compte plus
    // de 2 membres).
    if (m_messagingServer) {
        m_messagingServer->broadcastMessage(jsonMessage);
    }

    emit messageSent(message);
    return message;
}

std::optional<models::Message> MessagingManager::receiveMessage(const QString &jsonPayload)
{
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(jsonPayload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning() << "Message reseau invalide (JSON illisible) :" << parseError.errorString();
        m_lastError = MessagingManagerError::InvalidContent;
        m_lastErrorString = QStringLiteral("Invalid JSON payload");
        return std::nullopt;
    }

    const QJsonObject obj = doc.object();
    if (obj.value(QStringLiteral("type")).toString() != QStringLiteral("message")) {
        // Autre type de message reseau (futur usage) : on ignore silencieusement ici.
        return std::nullopt;
    }
    if (!obj.contains(QStringLiteral("conversationId")) || !obj.contains(QStringLiteral("senderId"))
        || !obj.contains(QStringLiteral("content"))) {
        m_lastError = MessagingManagerError::InvalidContent;
        m_lastErrorString = QStringLiteral("Missing fields in message payload");
        return std::nullopt;
    }

    const qint64 conversationId = static_cast<qint64>(obj.value(QStringLiteral("conversationId")).toDouble());
    const qint64 senderId = static_cast<qint64>(obj.value(QStringLiteral("senderId")).toDouble());
    const QString content = obj.value(QStringLiteral("content")).toString();

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

    // Persiste le message recu du reseau (pas de renvoi reseau, contrairement
    // a sendMessage : on ne fait qu'ecrire en base et notifier l'UI).
    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);
    const QString timestamp = QDateTime::currentDateTime().toString(Qt::ISODate);
    query.prepare(QStringLiteral(
        "INSERT INTO Messages (conversationId, senderId, content, timestamp, is_read) "
        "VALUES (:conversationId, :senderId, :content, :timestamp, 0)"
    ));
    query.bindValue(QStringLiteral(":conversationId"), conversationId);
    query.bindValue(QStringLiteral(":senderId"), senderId);
    query.bindValue(QStringLiteral(":content"), content);
    query.bindValue(QStringLiteral(":timestamp"), timestamp);

    if (!query.exec()) {
        qWarning() << "Failed to insert received message:" << query.lastError().text();
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = query.lastError().text();
        return std::nullopt;
    }

    const qint64 messageId = query.lastInsertId().toLongLong();
    models::Message message(messageId, conversationId, senderId, content);

    emit messageReceived(message);
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
