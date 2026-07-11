#include "MessagingManager.h"

#include "DatabaseManager.h"
#include "Messaging/MessagingService.h"
#include "Messaging/MessagingServer.h"
#include "NotificationManager.h"
#include "database/Repositories/UserRepository.h"
#include "database/Repositories/SyncLogRepository.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QUuid>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QDebug>

namespace core {

MessagingManager::MessagingManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
    , m_repository(dbManager)
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
        "SELECT id, type, name, participant1_id, participant2_id, uuid "
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
        conv.setUuid(query.value(5).toString());
        return conv;
    }

    // Creer une nouvelle conversation. uuid : identifiant stable
    // inter-postes indispensable a la reconciliation (cf. migration 011,
    // SyncLogRepository::ensureConversationByUuid).
    const QString conversationUuid = QUuid::createUuid().toString(QUuid::WithoutBraces);
    query.prepare(QStringLiteral(
        "INSERT INTO Conversations (type, name, participant1_id, participant2_id, uuid) "
        "VALUES ('individual', ?, ?, ?, ?)"
    ));
    query.addBindValue(QStringLiteral("Conversation"));
    query.addBindValue(userId1);
    query.addBindValue(userId2);
    query.addBindValue(conversationUuid);

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
    conv.setUuid(conversationUuid);
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

    // uuid stable du message, genere ici (et non dans le repository) afin
    // qu'il soit identique en base locale ET dans le payload reseau : sans
    // cela, le destinataire ne pourrait jamais dedupliquer ce message lors
    // d'une reconciliation ulterieure (cf. SyncLogRepository::applyMessageEntry).
    const QString messageUuid = QUuid::createUuid().toString(QUuid::WithoutBraces);

    // Inserer le message en base de donnees via le repository (requetes
    // preparees en interne : evite toute injection SQL et les erreurs de
    // syntaxe si `content` contient une apostrophe, ex. "l'ami" ou "it's").
    models::Message draft(0, conversationId, senderId, content);
    draft.setTimestamp(QDateTime::currentDateTime());
    draft.setRead(false);
    draft.setUuid(messageUuid);

    const auto inserted = m_repository.insert(draft);
    if (!inserted.has_value()) {
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Failed to persist message");
        return std::nullopt;
    }

    const models::Message message = *inserted;

    // Resoudre les uuids stables (conversation + expediteur) : conversationId
    // et senderId sont des id locaux AUTOINCREMENT qui n'ont aucune raison de
    // coincider avec ceux du poste destinataire (chaque machine a sa propre
    // base SQLite, cf. migration 011). Envoyer ces id bruts sur le reseau
    // provoquait un "FOREIGN KEY constraint failed" cote destinataire des
    // que ses id locaux divergeaient des notres (groupe cree ailleurs,
    // utilisateurs crees dans un ordre different, etc.) : on envoie donc les
    // uuids stables en plus, pour que receiveMessage() puisse retrouver ou
    // creer les lignes correspondantes localement avant l'insertion.
    QString conversationUuid;
    QString conversationType = QStringLiteral("individual");
    QString conversationName = QStringLiteral("Conversation");
    {
        QSqlDatabase db = m_dbManager->database();
        QSqlQuery convQuery(db);
        convQuery.prepare(QStringLiteral(
            "SELECT uuid, type, name FROM Conversations WHERE id = :id"));
        convQuery.bindValue(QStringLiteral(":id"), conversationId);
        if (convQuery.exec() && convQuery.next()) {
            conversationUuid = convQuery.value(0).toString();
            conversationType = convQuery.value(1).toString();
            conversationName = convQuery.value(2).toString();
        }
    }

    QString senderUuid;
    {
        database::UserRepository users(m_dbManager->database());
        const auto sender = users.findById(static_cast<int>(senderId));
        if (sender.has_value()) {
            senderUuid = sender->uuid();
        }
    }

    // Payload reseau, envoye via MessagingService (connexion sortante,
    // point-a-point) et/ou diffuse via MessagingServer (connexions
    // entrantes) ci-dessous.
    QJsonObject payload;
    payload.insert(QStringLiteral("type"), QStringLiteral("message"));
    payload.insert(QStringLiteral("conversationId"), conversationId);
    payload.insert(QStringLiteral("senderId"), senderId);
    payload.insert(QStringLiteral("content"), content);
    payload.insert(QStringLiteral("messageUuid"), messageUuid);
    payload.insert(QStringLiteral("conversationUuid"), conversationUuid);
    payload.insert(QStringLiteral("conversationType"), conversationType);
    payload.insert(QStringLiteral("conversationName"), conversationName);
    payload.insert(QStringLiteral("senderUuid"), senderUuid);
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

    // conversationId/senderId bruts du payload sont les id LOCAUX de la
    // machine emettrice : ils ne veulent rien dire ici (chaque poste a sa
    // propre base SQLite avec son propre AUTOINCREMENT, cf. migration 011).
    // On les garde comme repli (compatibilite / anciens postes), mais on
    // privilegie systematiquement la resolution par uuid ci-dessous, seule
    // reference stable inter-postes : les utiliser directement provoquait
    // un "FOREIGN KEY constraint failed" a l'insertion des que nos id
    // locaux divergeaient de ceux de l'emetteur.
    qint64 conversationId = static_cast<qint64>(obj.value(QStringLiteral("conversationId")).toDouble());
    qint64 senderId = static_cast<qint64>(obj.value(QStringLiteral("senderId")).toDouble());
    const QString content = obj.value(QStringLiteral("content")).toString();
    const QString messageUuid = obj.value(QStringLiteral("messageUuid")).toString();
    const QString conversationUuid = obj.value(QStringLiteral("conversationUuid")).toString();
    const QString conversationType = obj.value(QStringLiteral("conversationType")).toString(QStringLiteral("individual"));
    const QString conversationName = obj.value(QStringLiteral("conversationName")).toString(QStringLiteral("Conversation"));
    const QString senderUuid = obj.value(QStringLiteral("senderUuid")).toString();

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

    // Deduplication : si ce message (par son uuid stable) a deja ete recu
    // - par exemple rejoue ensuite via une reconciliation SyncLog - on ne
    // le reinsere pas une seconde fois.
    if (!messageUuid.isEmpty()) {
        const auto existing = m_repository.findByUuid(messageUuid);
        if (existing.has_value()) {
            return existing;
        }
    }

    // Resoudre la conversation locale via son uuid stable : la cree si
    // necessaire (ex. groupe cree sur un autre poste, jamais vu ici).
    if (!conversationUuid.isEmpty()) {
        database::SyncLogRepository syncRepo(m_dbManager->database());
        const qint64 resolvedConversationId = syncRepo.ensureConversationByUuid(
            conversationUuid, conversationType, conversationName);
        if (resolvedConversationId > 0) {
            conversationId = resolvedConversationId;
        }
    }

    // Resoudre l'expediteur local via son uuid stable.
    if (!senderUuid.isEmpty()) {
        database::UserRepository users(m_dbManager->database());
        const auto sender = users.findByUuid(senderUuid);
        if (sender.has_value()) {
            senderId = sender->id();
        } else {
            // Utilisateur emetteur pas encore connu localement (Users pas
            // encore reconcilie) : impossible d'inserer sans violer la FK,
            // on abandonne plutot que de planter avec un id invalide.
            m_lastError = MessagingManagerError::DatabaseError;
            m_lastErrorString = QStringLiteral("Sender inconnu (uuid=%1), message ignore").arg(senderUuid);
            qWarning() << m_lastErrorString;
            return std::nullopt;
        }
    }

    // Persiste le message recu du reseau (pas de renvoi reseau, contrairement
    // a sendMessage : on ne fait qu'ecrire en base et notifier l'UI).
    models::Message draft(0, conversationId, senderId, content);
    draft.setTimestamp(QDateTime::currentDateTime());
    draft.setRead(false);
    draft.setUuid(messageUuid);

    const auto inserted = m_repository.insert(draft);
    if (!inserted.has_value()) {
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Failed to persist received message");
        return std::nullopt;
    }

    const models::Message message = *inserted;

    emit messageReceived(message);
    return message;
}

QVector<models::Message> MessagingManager::getMessages(qint64 conversationId, int limit)
{
    if (!m_dbManager) {
        return {};
    }

    return m_repository.getMessages(conversationId, limit);
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
        "SELECT id, type, name, participant1_id, participant2_id, uuid "
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
            conv.setUuid(query.value(5).toString());
            conversations.append(conv);
        }
    }

    return conversations;
}

} // namespace core