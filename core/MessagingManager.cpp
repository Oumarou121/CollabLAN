#include "MessagingManager.h"

#include "DatabaseManager.h"
#include "Messaging/MessagingService.h"
#include "Messaging/MessagingServer.h"
#include "NotificationManager.h"
#include "UserManager.h"
#include "database/Repositories/UserRepository.h"
#include "database/Repositories/SyncLogRepository.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QStringList>
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

void MessagingManager::setUserManager(UserManager *userManager)
{
    m_userManager = userManager;
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
    qint64 participant1Id = 0;
    qint64 participant2Id = 0;
    {
        QSqlDatabase db = m_dbManager->database();
        QSqlQuery convQuery(db);
        convQuery.prepare(QStringLiteral(
            "SELECT uuid, type, name, participant1_id, participant2_id FROM Conversations WHERE id = :id"));
        convQuery.bindValue(QStringLiteral(":id"), conversationId);
        if (convQuery.exec() && convQuery.next()) {
            conversationUuid = convQuery.value(0).toString();
            conversationType = convQuery.value(1).toString();
            conversationName = convQuery.value(2).toString();
            participant1Id = convQuery.value(3).toLongLong();
            participant2Id = convQuery.value(4).toLongLong();
        }
    }

    QString senderUuid;
    // uuids stables des DEUX participants de la conversation (et non
    // seulement de l'expediteur) : sans le uuid de l'autre participant, le
    // destinataire ne peut pas renseigner participant1_id/participant2_id
    // en creant la conversation localement (cf. ensureConversationByUuid),
    // et celle-ci reste alors invisible pour toujours dans
    // getUserConversations() meme si le message lui-meme est bien insere.
    QString participant1Uuid;
    QString participant2Uuid;
    {
        database::UserRepository users(m_dbManager->database());
        const auto sender = users.findById(static_cast<int>(senderId));
        if (sender.has_value()) {
            senderUuid = sender->uuid();
        }
        if (participant1Id > 0) {
            const auto p1 = users.findById(static_cast<int>(participant1Id));
            if (p1.has_value()) {
                participant1Uuid = p1->uuid();
            }
        }
        if (participant2Id > 0) {
            const auto p2 = users.findById(static_cast<int>(participant2Id));
            if (p2.has_value()) {
                participant2Uuid = p2->uuid();
            }
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
    payload.insert(QStringLiteral("participant1Uuid"), participant1Uuid);
    payload.insert(QStringLiteral("participant2Uuid"), participant2Uuid);
    const QString jsonMessage = QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));

    // Envoyer le message via le reseau si le service est configure
    if (m_messagingService && m_messagingService->isConnected()) {
        if (!m_messagingService->sendMessage(jsonMessage)) {
            qWarning() << "Failed to send message via network";
            // On ne retourne pas d'erreur ici car le message est deja en base
        }
    }

    // Diffuse egalement aux clients connectes a notre serveur, mais
    // UNIQUEMENT ceux qui sont participants de la conversation (issue #2 :
    // broadcastMessage() envoyait ce message a TOUS les clients connectes,
    // y compris des tiers totalement etrangers a la conversation, qui le
    // persistaient silencieusement dans leur propre base). Pour une
    // conversation de groupe, participant1Uuid/participant2Uuid sont vides
    // (les Conversations de type 'group' n'utilisent pas ces colonnes) :
    // on resout alors les membres via resolveGroupMemberUuids().
    if (m_messagingServer) {
        QStringList targetUuids;
        if (!participant1Uuid.isEmpty()) targetUuids << participant1Uuid;
        if (!participant2Uuid.isEmpty()) targetUuids << participant2Uuid;

        if (conversationType == QStringLiteral("group")) {
            targetUuids << resolveGroupMemberUuids(conversationId);
        }

        targetUuids.removeDuplicates();
        if (!targetUuids.isEmpty()) {
            m_messagingServer->sendToUuids(jsonMessage, targetUuids);
        } else {
            // Repli de securite : si on n'a pas pu resoudre le moindre
            // destinataire (donnee manquante, groupe introuvable...), on
            // garde l'ancien comportement plutot que de perdre le message
            // silencieusement.
            qWarning() << "sendMessage: aucun destinataire resolu pour la conversation" << conversationId
                       << "- repli sur broadcastMessage()";
            m_messagingServer->broadcastMessage(jsonMessage);
        }
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
    const QString participant1Uuid = obj.value(QStringLiteral("participant1Uuid")).toString();
    const QString participant2Uuid = obj.value(QStringLiteral("participant2Uuid")).toString();

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

    // Resoudre l'expediteur local via son uuid stable, et si possible les
    // ids locaux des deux participants (pour ensureConversationByUuid
    // ci-dessous : sans eux, la conversation individuelle creee ici
    // resterait invisible dans getUserConversations()).
    database::UserRepository users(m_dbManager->database());
    qint64 participant1Id = -1;
    qint64 participant2Id = -1;
    if (!participant1Uuid.isEmpty()) {
        const auto p1 = users.findByUuid(participant1Uuid);
        if (p1.has_value()) {
            participant1Id = p1->id();
        }
    }
    if (!participant2Uuid.isEmpty()) {
        const auto p2 = users.findByUuid(participant2Uuid);
        if (p2.has_value()) {
            participant2Id = p2->id();
        }
    }

    // Repli sur notre identite locale (BUG : "message bien ecrit en base
    // mais discussion/messages invisibles cote destinataire, meme apres
    // redemarrage"). Pour une conversation individuelle, les deux seuls
    // participants possibles sont l'expediteur (deja resolu ci-dessus via
    // senderUuid, plus bas) et NOUS-MEMES. Si le uuid envoye par
    // l'expediteur pour "l'autre" participant ne correspond a AUCUN
    // utilisateur local - typiquement parce que notre compte local n'a
    // jamais ete synchronise avec cet uuid-la avant ce premier message -,
    // participant1Id/participant2Id restaient a -1 -> ensureConversationByUuid
    // inserait alors la conversation avec participant1_id/participant2_id a
    // NULL. Or MessagingManager::getUserConversations() filtre strictement
    // sur "participant1_id = ? OR participant2_id = ?" : une conversation
    // sans NOTRE id dans l'une de ces deux colonnes restait donc a jamais
    // invisible dans l'UI, meme apres redemarrage complet de l'application
    // (ce n'est pas un probleme de rafraichissement de signal QML, la
    // donnee en base elle-meme ne matchait plus jamais la requete).
    if (conversationType == QStringLiteral("individual") && m_userManager) {
        const auto localUserId = m_userManager->currentUserId();
        if (localUserId.has_value()) {
            if (participant1Id <= 0 && participant1Uuid != senderUuid) {
                participant1Id = localUserId.value();
            }
            if (participant2Id <= 0 && participant2Uuid != senderUuid) {
                participant2Id = localUserId.value();
            }
        }
    }

    // Resoudre la conversation locale via son uuid stable : la cree si
    // necessaire (ex. groupe cree sur un autre poste, jamais vu ici).
    if (!conversationUuid.isEmpty()) {
        database::SyncLogRepository syncRepo(m_dbManager->database());
        const qint64 resolvedConversationId = syncRepo.ensureConversationByUuid(
            conversationUuid, conversationType, conversationName, participant1Id, participant2Id);
        if (resolvedConversationId > 0) {
            conversationId = resolvedConversationId;
        }
    }

    // Resoudre l'expediteur local via son uuid stable.
    if (!senderUuid.isEmpty()) {
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

std::optional<models::Message> MessagingManager::getLastMessage(qint64 conversationId)
{
    if (!m_dbManager) {
        return std::nullopt;
    }

    return m_repository.getLastMessage(conversationId);
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

bool MessagingManager::markConversationAsRead(qint64 conversationId, qint64 userId)
{
    if (!m_dbManager) {
        return false;
    }

    return m_repository.markConversationAsRead(conversationId, userId);
}

int MessagingManager::getUnreadCount(qint64 conversationId, qint64 userId)
{
    if (!m_dbManager) {
        return 0;
    }

    return m_repository.getUnreadCount(conversationId, userId);
}

QStringList MessagingManager::resolveGroupMemberUuids(qint64 conversationId) const
{
    QStringList uuids;
    if (!m_dbManager) {
        return uuids;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery groupQuery(db);
    groupQuery.prepare(QStringLiteral("SELECT id FROM Groups WHERE conversation_id = :cid"));
    groupQuery.bindValue(QStringLiteral(":cid"), conversationId);
    if (!groupQuery.exec() || !groupQuery.next()) {
        return uuids;
    }
    const qint64 groupId = groupQuery.value(0).toLongLong();

    QSqlQuery membersQuery(db);
    membersQuery.prepare(QStringLiteral("SELECT user_id FROM GroupMembers WHERE group_id = :gid"));
    membersQuery.bindValue(QStringLiteral(":gid"), groupId);
    if (!membersQuery.exec()) {
        return uuids;
    }

    database::UserRepository users(db);
    while (membersQuery.next()) {
        const qint64 memberId = membersQuery.value(0).toLongLong();
        if (const auto member = users.findById(static_cast<int>(memberId)); member.has_value()) {
            uuids << member->uuid();
        }
    }
    return uuids;
}

QStringList MessagingManager::resolveTargetUuidsFromPayload(const QString &jsonPayload) const
{
    QStringList targetUuids;

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(jsonPayload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        return targetUuids;
    }
    const QJsonObject obj = doc.object();
    if (obj.value(QStringLiteral("type")).toString() != QStringLiteral("message")) {
        return targetUuids;
    }

    const QString participant1Uuid = obj.value(QStringLiteral("participant1Uuid")).toString();
    const QString participant2Uuid = obj.value(QStringLiteral("participant2Uuid")).toString();
    if (!participant1Uuid.isEmpty()) targetUuids << participant1Uuid;
    if (!participant2Uuid.isEmpty()) targetUuids << participant2Uuid;

    if (obj.value(QStringLiteral("conversationType")).toString() == QStringLiteral("group")) {
        // conversationId dans le payload est l'id LOCAL de l'expediteur,
        // qui n'a aucune raison de correspondre au notre (chaque poste a sa
        // propre base) : on doit d'abord retrouver notre propre id local
        // via conversationUuid, qui lui est stable inter-postes.
        const QString conversationUuid = obj.value(QStringLiteral("conversationUuid")).toString();
        if (!conversationUuid.isEmpty() && m_dbManager) {
            QSqlQuery convQuery(m_dbManager->database());
            convQuery.prepare(QStringLiteral("SELECT id FROM Conversations WHERE uuid = :uuid"));
            convQuery.bindValue(QStringLiteral(":uuid"), conversationUuid);
            if (convQuery.exec() && convQuery.next()) {
                const qint64 localConversationId = convQuery.value(0).toLongLong();
                targetUuids << resolveGroupMemberUuids(localConversationId);
            }
        }
    }

    targetUuids.removeDuplicates();
    return targetUuids;
}

} // namespace core