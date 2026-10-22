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
#include <QCryptographicHash>

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

    // Creer une nouvelle conversation. Son UUID doit etre le meme sur tous
    // les postes pour cette paire d'utilisateurs : un UUID aleatoire creait
    // deux conversations distinctes si les deux personnes ouvraient leur
    // discussion avant la premiere synchronisation.
    database::UserRepository users(db);
    const auto firstUser = users.findById(static_cast<int>(userId1));
    const auto secondUser = users.findById(static_cast<int>(userId2));
    QString conversationUuid;
    if (firstUser.has_value() && secondUser.has_value()
        && !firstUser->uuid().isEmpty() && !secondUser->uuid().isEmpty()) {
        QStringList participantUuids{firstUser->uuid(), secondUser->uuid()};
        participantUuids.sort();
        conversationUuid = QString::fromLatin1(
            QCryptographicHash::hash(participantUuids.join(QLatin1Char(':')).toUtf8(),
                                     QCryptographicHash::Sha256).toHex());
    } else {
        // Repli de compatibilite pour une base legacy sans UUID utilisateur.
        conversationUuid = QUuid::createUuid().toString(QUuid::WithoutBraces);
    }
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

MessagingManager::OutgoingMessage MessagingManager::buildOutgoing(const models::Message &message) const
{
    OutgoingMessage out;
    if (!m_dbManager)
        return out;

    // Resoudre les uuids stables (conversation + expediteur) : conversationId
    // et senderId sont des id locaux AUTOINCREMENT qui n'ont aucune raison de
    // coincider avec ceux du poste destinataire (chaque machine a sa propre
    // base SQLite, cf. migration 011). Envoyer ces id bruts sur le reseau
    // provoquait un "FOREIGN KEY constraint failed" cote destinataire des
    // que ses id locaux divergeaient des notres (groupe cree ailleurs,
    // utilisateurs crees dans un ordre different, etc.) : on envoie donc les
    // uuids stables, pour que receiveMessage() puisse retrouver ou creer les
    // lignes correspondantes localement avant l'insertion.
    QString conversationUuid;
    QString conversationType = QStringLiteral("individual");
    QString conversationName = QStringLiteral("Conversation");
    qint64 participant1Id = 0;
    qint64 participant2Id = 0;
    {
        QSqlQuery convQuery(m_dbManager->database());
        convQuery.prepare(QStringLiteral(
            "SELECT uuid, type, name, participant1_id, participant2_id FROM Conversations WHERE id = :id"));
        convQuery.bindValue(QStringLiteral(":id"), message.conversationId());
        if (convQuery.exec() && convQuery.next()) {
            conversationUuid = convQuery.value(0).toString();
            conversationType = convQuery.value(1).toString();
            conversationName = convQuery.value(2).toString();
            participant1Id = convQuery.value(3).toLongLong();
            participant2Id = convQuery.value(4).toLongLong();
        }
    }

    // uuids stables des DEUX participants de la conversation (et non
    // seulement de l'expediteur) : sans le uuid de l'autre participant, le
    // destinataire ne peut pas renseigner participant1_id/participant2_id
    // en creant la conversation localement (cf. ensureConversationByUuid),
    // et celle-ci reste alors invisible pour toujours dans
    // getUserConversations() meme si le message lui-meme est bien insere.
    QString senderUuid;
    QString participant1Uuid;
    QString participant2Uuid;
    {
        database::UserRepository users(m_dbManager->database());
        if (const auto sender = users.findById(static_cast<int>(message.senderId())); sender.has_value())
            senderUuid = sender->uuid();
        if (participant1Id > 0) {
            if (const auto p1 = users.findById(static_cast<int>(participant1Id)); p1.has_value())
                participant1Uuid = p1->uuid();
        }
        if (participant2Id > 0) {
            if (const auto p2 = users.findById(static_cast<int>(participant2Id)); p2.has_value())
                participant2Uuid = p2->uuid();
        }
    }

    QJsonObject payload;
    payload.insert(QStringLiteral("type"), QStringLiteral("message"));
    payload.insert(QStringLiteral("content"), message.content());
    payload.insert(QStringLiteral("messageUuid"), message.uuid());
    payload.insert(QStringLiteral("conversationUuid"), conversationUuid);
    payload.insert(QStringLiteral("conversationType"), conversationType);
    payload.insert(QStringLiteral("conversationName"), conversationName);
    payload.insert(QStringLiteral("senderUuid"), senderUuid);
    payload.insert(QStringLiteral("participant1Uuid"), participant1Uuid);
    payload.insert(QStringLiteral("participant2Uuid"), participant2Uuid);
    // Heure d'ENVOI (UTC) : un message remis en retard (file d'envoi,
    // rattrapage) garde son heure reelle chez le destinataire.
    payload.insert(QStringLiteral("timestamp"),
                   (message.timestamp().isValid() ? message.timestamp() : QDateTime::currentDateTimeUtc())
                       .toUTC().toString(Qt::ISODate));
    out.payload = payload;
    out.json = QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));

    if (!participant1Uuid.isEmpty()) out.targetUuids << participant1Uuid;
    if (!participant2Uuid.isEmpty()) out.targetUuids << participant2Uuid;
    if (conversationType == QStringLiteral("group"))
        out.targetUuids << resolveGroupMemberUuids(message.conversationId());
    out.targetUuids.removeDuplicates();
    return out;
}

std::optional<models::Message> MessagingManager::sendMessage(qint64 conversationId, qint64 senderId, const QString &content)
{
    if (!m_dbManager) {
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        emit messageSendFailed(conversationId, m_lastErrorString);
        return std::nullopt;
    }

    if (content.trimmed().isEmpty()) {
        m_lastError = MessagingManagerError::InvalidContent;
        m_lastErrorString = QStringLiteral("Message content cannot be empty");
        emit messageSendFailed(conversationId, m_lastErrorString);
        return std::nullopt;
    }

    // Ce poste est lui-meme le serveur (serveur de messagerie actif) : le
    // message est conserve ici, dans le journal, et servi aux destinataires
    // absents a leur retour. Sinon il reste "en attente" jusqu'a l'accuse de
    // reception du serveur (file d'envoi, cf. resendPendingMessages).
    const bool storedHere = m_messagingServer && m_messagingServer->isRunning();

    // uuid stable du message, genere ici (et non dans le repository) afin
    // qu'il soit identique en base locale ET dans le payload reseau : sans
    // cela, le destinataire ne pourrait jamais dedupliquer ce message lors
    // d'une reconciliation ulterieure (cf. SyncLogRepository::applyMessageEntry).
    const QString messageUuid = QUuid::createUuid().toString(QUuid::WithoutBraces);

    // Inserer le message en base de donnees via le repository (requetes
    // preparees en interne : evite toute injection SQL et les erreurs de
    // syntaxe si `content` contient une apostrophe, ex. "l'ami" ou "it's").
    models::Message draft(0, conversationId, senderId, content);
    draft.setTimestamp(QDateTime::currentDateTimeUtc());
    draft.setRead(false);
    draft.setUuid(messageUuid);
    draft.setDeliveryStatus(storedHere ? models::Message::Sent : models::Message::Pending);

    const auto inserted = m_repository.insert(draft);
    if (!inserted.has_value()) {
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Failed to persist message");
        emit messageSendFailed(conversationId, m_lastErrorString);
        return std::nullopt;
    }

    const models::Message message = *inserted;
    const OutgoingMessage outgoing = buildOutgoing(message);

    // Diffuse aux clients connectes a notre serveur, mais UNIQUEMENT ceux qui
    // sont participants de la conversation (issue #2 : broadcastMessage()
    // envoyait ce message a TOUS les clients connectes). Les absents le
    // recevront par synchronisation.
    if (storedHere) {
        if (!outgoing.targetUuids.isEmpty()) {
            m_messagingServer->sendToUuids(outgoing.json, outgoing.targetUuids);
        } else {
            // Repli de securite : si on n'a pas pu resoudre le moindre
            // destinataire (donnee manquante, groupe introuvable...), on
            // garde l'ancien comportement plutot que de perdre le message
            // silencieusement.
            qWarning() << "sendMessage: aucun destinataire resolu pour la conversation" << conversationId
                       << "- repli sur broadcastMessage()";
            m_messagingServer->broadcastMessage(outgoing.json);
        }
    }

    // Envoyer aussi via la connexion sortante si ce poste est client.
    if (m_messagingService && m_messagingService->isConnected()) {
        if (!m_messagingService->sendMessage(outgoing.json)) {
            qWarning() << "Failed to send message via network";
            emit messageQueued(conversationId);
        }
    } else if (!storedHere) {
        // Pas un echec : le message est garde et partira a la reconnexion.
        qWarning() << "sendMessage: pas de connexion au serveur, message mis en attente" << conversationId;
        emit messageQueued(conversationId);
    }

    emit messageSent(message);
    return message;
}

int MessagingManager::resendPendingMessages(qint64 senderId)
{
    if (!m_dbManager || !m_messagingService || !m_messagingService->isConnected())
        return 0;

    int resent = 0;
    for (const models::Message &message : m_repository.pendingMessages(senderId)) {
        if (!m_messagingService->sendMessage(buildOutgoing(message).json))
            break; // connexion perdue : le reste attendra la prochaine
        ++resent;
    }
    if (resent > 0)
        qInfo() << "File d'envoi :" << resent << "message(s) renvoye(s) au serveur";
    return resent;
}

bool MessagingManager::markMessageSent(const QString &messageUuid)
{
    if (!m_repository.setDeliveryStatus(messageUuid, models::Message::Sent))
        return false;
    emit messageDeliveryChanged(messageUuid, models::Message::Sent);
    return true;
}

QVector<models::Message> MessagingManager::takeOverPendingMessages()
{
    const QVector<models::Message> pending = m_repository.allPendingMessages();
    for (const models::Message &message : pending)
        markMessageSent(message.uuid());
    return pending;
}

void MessagingManager::notifySynchronized(int mergedEntryCount)
{
    emit messagesSynchronized(mergedEntryCount);
}

QString MessagingManager::localUserUuid() const
{
    if (!m_dbManager || !m_userManager)
        return QString();
    const auto id = m_userManager->currentUserId();
    if (!id.has_value())
        return QString();
    database::UserRepository users(m_dbManager->database());
    const auto user = users.findById(static_cast<int>(*id));
    return user.has_value() ? user->uuid() : QString();
}

QStringList MessagingManager::recipientUuids(const models::Message &message) const
{
    return buildOutgoing(message).targetUuids;
}

QJsonObject MessagingManager::messageUpdatePayload(const models::Message &message) const
{
    // Memes champs d'adressage que le message (visibilite dans le journal,
    // destinataires du relais), plus le changement.
    QJsonObject payload = buildOutgoing(message).payload;
    payload.insert(QStringLiteral("type"), QStringLiteral("message_update"));
    payload.remove(QStringLiteral("timestamp"));
    if (message.isDeleted()) {
        payload.insert(QStringLiteral("action"), QStringLiteral("delete"));
        payload.insert(QStringLiteral("content"), QString());
        payload.insert(QStringLiteral("deletedAt"), message.deletedAt().toUTC().toString(Qt::ISODate));
    } else {
        payload.insert(QStringLiteral("action"), QStringLiteral("edit"));
        payload.insert(QStringLiteral("editedAt"), message.editedAt().toUTC().toString(Qt::ISODate));
    }
    return payload;
}

namespace {
bool isAuthorOf(const std::optional<models::Message> &message, qint64 requesterId)
{
    return message.has_value() && message->senderId() == requesterId && !message->isDeleted();
}
} // namespace

bool MessagingManager::editMessage(const QString &messageUuid, const QString &newContent, qint64 requesterId)
{
    const QString content = newContent.trimmed();
    const auto message = m_repository.findByUuid(messageUuid);
    if (!isAuthorOf(message, requesterId) || content.isEmpty()) {
        m_lastError = MessagingManagerError::InvalidContent;
        m_lastErrorString = QStringLiteral("Seul l'auteur peut modifier ce message");
        return false;
    }
    if (content == message->content())
        return true;
    if (!m_repository.updateContent(messageUuid, content, QDateTime::currentDateTimeUtc()))
        return false;
    const auto updated = m_repository.findByUuid(messageUuid);
    // Encore en attente (jamais parti) : le renvoi portera le nouveau texte.
    if (!updated->isPending())
        emit messageChangeOutgoing(messageUpdatePayload(*updated));
    emit messageUpdated(*updated);
    return true;
}

bool MessagingManager::deleteMessage(const QString &messageUuid, qint64 requesterId)
{
    const auto message = m_repository.findByUuid(messageUuid);
    if (!isAuthorOf(message, requesterId)) {
        m_lastError = MessagingManagerError::InvalidContent;
        m_lastErrorString = QStringLiteral("Seul l'auteur peut supprimer ce message");
        return false;
    }
    // Jamais parti : personne d'autre ne l'a, il est simplement retire.
    if (message->isPending()) {
        if (!m_repository.removePending(messageUuid))
            return false;
        emit messageRemoved(*message);
        return true;
    }
    // Adressage releve avant l'effacement du texte.
    if (!m_repository.markDeleted(messageUuid, QDateTime::currentDateTimeUtc()))
        return false;
    const auto updated = m_repository.findByUuid(messageUuid);
    emit messageChangeOutgoing(messageUpdatePayload(*updated));
    emit messageUpdated(*updated);
    return true;
}

void MessagingManager::notifyActionRefused(const QString &reason)
{
    emit actionRefused(reason);
}
bool MessagingManager::receiveMessageUpdate(const QJsonObject &payload)
{
    const QString messageUuid = payload.value(QStringLiteral("messageUuid")).toString();
    const auto message = m_repository.findByUuid(messageUuid);
    if (!message || !m_dbManager)
        return false;
    // Seul l'auteur du message peut le modifier.
    database::UserRepository users(m_dbManager->database());
    const auto sender = users.findById(static_cast<int>(message->senderId()));
    if (!sender || sender->uuid() != payload.value(QStringLiteral("senderUuid")).toString())
        return false;

    bool changed = false;
    if (payload.value(QStringLiteral("action")).toString() == QStringLiteral("delete")) {
        changed = m_repository.markDeleted(messageUuid, QDateTime::fromString(
            payload.value(QStringLiteral("deletedAt")).toString(), Qt::ISODate));
    } else {
        changed = m_repository.updateContent(messageUuid, payload.value(QStringLiteral("content")).toString(),
                                             QDateTime::fromString(payload.value(QStringLiteral("editedAt")).toString(), Qt::ISODate));
    }
    if (changed) {
        if (const auto updated = m_repository.findByUuid(messageUuid))
            emit messageUpdated(*updated);
    }
    return changed;
}

void MessagingManager::recordDeliveredFor(qint64 userId)
{
    if (!m_dbManager)
        return;
    database::UserRepository users(m_dbManager->database());
    const auto user = users.findById(static_cast<int>(userId));
    if (!user || user->uuid().isEmpty())
        return;
    bool any = false;
    const QDateTime now = QDateTime::currentDateTimeUtc();
    for (const QString &uuid : m_repository.undeliveredMessageUuids(userId))
        any = m_repository.upsertReceipt({uuid, user->uuid(), now, {}}, true) || any;
    if (any)
        emit receiptsPending();
}

QVector<database::MessageReceipt> MessagingManager::pendingReceipts() const
{
    return m_repository.pendingReceipts();
}

void MessagingManager::clearPendingReceipt(const QString &messageUuid, const QString &userUuid)
{
    m_repository.clearPendingReceipt(messageUuid, userUuid);
}

void MessagingManager::applyReceipts(const QVector<database::MessageReceipt> &receipts)
{
    QStringList touched;
    for (const database::MessageReceipt &receipt : receipts) {
        if (receipt.userUuid == QStringLiteral("*"))
            continue;
        if (m_repository.upsertReceipt(receipt, false) && !touched.contains(receipt.messageUuid))
            touched << receipt.messageUuid;
    }
    refreshDeliveryStatuses(touched);
}

void MessagingManager::refreshDeliveryStatuses(const QStringList &messageUuids)
{
    for (const QString &uuid : messageUuids) {
        if (const auto status = m_repository.refreshDeliveryStatus(uuid))
            emit messageDeliveryChanged(uuid, *status);
    }
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
    if (!obj.contains(QStringLiteral("conversationUuid"))
        || !obj.contains(QStringLiteral("senderUuid"))
        || !obj.contains(QStringLiteral("messageUuid"))
        || !obj.contains(QStringLiteral("content"))) {
        m_lastError = MessagingManagerError::InvalidContent;
        m_lastErrorString = QStringLiteral("Missing fields in message payload");
        return std::nullopt;
    }

    const QString content = obj.value(QStringLiteral("content")).toString();
    const QString messageUuid = obj.value(QStringLiteral("messageUuid")).toString();
    const QString conversationUuid = obj.value(QStringLiteral("conversationUuid")).toString();
    const QString conversationType = obj.value(QStringLiteral("conversationType")).toString(QStringLiteral("individual"));
    const QString conversationName = obj.value(QStringLiteral("conversationName")).toString(QStringLiteral("Conversation"));
    const QString senderUuid = obj.value(QStringLiteral("senderUuid")).toString();
    const QString participant1Uuid = obj.value(QStringLiteral("participant1Uuid")).toString();
    const QString participant2Uuid = obj.value(QStringLiteral("participant2Uuid")).toString();

    // Les identifiants entiers sont locaux a la base de l'emetteur. Ils ne
    // traversent jamais le reseau : ils seront resolus ci-dessous dans la
    // base locale du destinataire a partir des UUID stables.
    qint64 conversationId = -1;
    qint64 senderId = -1;

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

    if (conversationId <= 0) {
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Conversation inconnue (uuid=%1)").arg(conversationUuid);
        qWarning() << m_lastErrorString;
        return std::nullopt;
    }

    // Resoudre l'expediteur local via son uuid stable.
    if (!senderUuid.isEmpty()) {
        const auto sender = users.findByUuid(senderUuid);
        if (sender.has_value()) {
            senderId = sender->id();
        } else {
            // Utilisateur emetteur pas encore connu localement (Users pas
            // encore reconcilie) : impossible d'inserer sans violer la FK.
            // CORRECTIF : on n'abandonne plus silencieusement -- on emet
            // unresolvedSenderMessage pour que l'appelant (Application)
            // puisse declencher une reconciliation et rejouer ce meme
            // jsonPayload une fois senderUuid connu localement, au lieu de
            // perdre le message pour de bon.
            m_lastError = MessagingManagerError::DatabaseError;
            m_lastErrorString = QStringLiteral("Sender inconnu (uuid=%1), message en attente de reconciliation").arg(senderUuid);
            qWarning() << m_lastErrorString;
            emit unresolvedSenderMessage(senderUuid, jsonPayload);
            return std::nullopt;
        }
    }

    if (senderId <= 0) {
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Expediteur sans identifiant local (uuid=%1)").arg(senderUuid);
        return std::nullopt;
    }

    // Persiste le message recu du reseau (pas de renvoi reseau, contrairement
    // a sendMessage : on ne fait qu'ecrire en base et notifier l'UI).
    // Heure d'envoi transmise par l'emetteur (UTC) ; heure de reception a
    // defaut (ancien emetteur). Une heure trop en avance sur la notre est
    // ramenee a maintenant : elle placerait le message apres tous les suivants.
    const QDateTime nowUtc = QDateTime::currentDateTimeUtc();
    QDateTime sentAt = QDateTime::fromString(obj.value(QStringLiteral("timestamp")).toString(), Qt::ISODate);
    if (!sentAt.isValid() || sentAt > nowUtc.addSecs(300))
        sentAt = nowUtc;

    models::Message draft(0, conversationId, senderId, content);
    draft.setTimestamp(sentAt);
    draft.setRead(false);
    draft.setUuid(messageUuid);

    const auto inserted = m_repository.insert(draft);
    if (!inserted.has_value()) {
        m_lastError = MessagingManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Failed to persist received message");
        return std::nullopt;
    }

    const models::Message message = *inserted;

    // Accuse "remis" pour l'utilisateur de ce poste (transmis a l'expediteur).
    const QString localUuid = localUserUuid();
    if (!localUuid.isEmpty() && localUuid != senderUuid
        && m_repository.upsertReceipt({messageUuid, localUuid, QDateTime::currentDateTimeUtc(), {}}, true)) {
        emit receiptsPending();
    }

    emit messageReceived(message);
    return message;
}

QVector<models::Message> MessagingManager::getMessages(qint64 conversationId, int limit)
{
    if (!m_dbManager) {
        return {};
    }

    // isRead : lu par l'utilisateur connecte (accuses), pas par un autre
    // utilisateur du meme poste.
    qint64 viewer = 0;
    if (m_userManager) {
        if (const auto id = m_userManager->currentUserId(); id.has_value())
            viewer = *id;
    }
    return m_repository.getMessages(conversationId, limit, 0, viewer);
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

    const bool hadUnread = !m_repository.unreadMessageUuids(conversationId, userId).isEmpty();
    const bool ok = m_repository.markConversationAsRead(conversationId, userId);
    // Accuses "lu" a transmettre aux expediteurs.
    if (ok && hadUnread)
        emit receiptsPending();
    return ok;
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

bool MessagingManager::isLocalUserParticipant(const QString &jsonPayload) const
{
    if (!m_userManager) {
        // Sans UserManager, on ne peut pas verifier : on accepte par defaut
        // pour ne pas casser le comportement existant.
        return true;
    }

    const auto localUserId = m_userManager->currentUserId();
    if (!localUserId.has_value()) {
        // Pas d'utilisateur connecte localement : on ne persiste pas
        return false;
    }

    database::UserRepository users(m_dbManager ? m_dbManager->database() : QSqlDatabase());
    const auto localUser = users.findById(static_cast<int>(localUserId.value()));
    if (!localUser.has_value()) {
        return false;
    }
    const QString localUserUuid = localUser->uuid();

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(jsonPayload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        return false;
    }
    const QJsonObject obj = doc.object();
    if (obj.value(QStringLiteral("type")).toString() != QStringLiteral("message")) {
        return false;
    }

    const QString senderUuid = obj.value(QStringLiteral("senderUuid")).toString();
    const QString participant1Uuid = obj.value(QStringLiteral("participant1Uuid")).toString();
    const QString participant2Uuid = obj.value(QStringLiteral("participant2Uuid")).toString();
    const QString conversationType = obj.value(QStringLiteral("conversationType")).toString(QStringLiteral("individual"));

    // Pour une conversation individuelle : l'utilisateur local doit etre
    // l'expediteur ou l'un des deux participants.
    if (conversationType == QStringLiteral("individual")) {
        return (localUserUuid == senderUuid ||
                localUserUuid == participant1Uuid ||
                localUserUuid == participant2Uuid);
    }

    // Pour une conversation de groupe : verifier si l'utilisateur local
    // est membre du groupe via conversationUuid.
    if (conversationType == QStringLiteral("group") && m_dbManager) {
        const QString conversationUuid = obj.value(QStringLiteral("conversationUuid")).toString();
        if (!conversationUuid.isEmpty()) {
            QSqlQuery convQuery(m_dbManager->database());
            convQuery.prepare(QStringLiteral("SELECT id FROM Conversations WHERE uuid = :uuid"));
            convQuery.bindValue(QStringLiteral(":uuid"), conversationUuid);
            if (convQuery.exec() && convQuery.next()) {
                const qint64 localConversationId = convQuery.value(0).toLongLong();
                const QStringList memberUuids = resolveGroupMemberUuids(localConversationId);
                return memberUuids.contains(localUserUuid);
            }
        }
    }

    return false;
}

} // namespace core
