#include "MessageRepository.h"

#include "DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QUuid>
#include <QDebug>

namespace database {

namespace {

// Colonnes lues par messageFromQuery, dans cet ordre. %1 : expression de
// l'indicateur "lu" (colonne is_read, ou accuses du lecteur).
constexpr const char *kColumnsTemplate =
    "id, conversationId, senderId, content, timestamp, %1, uuid, delivery_status, edited_at, deleted_at";

// Lu par le lecteur :viewer (ses propres messages comptent comme lus), d'apres
// ses accuses ou ceux de la migration ('*' = lu par tous).
constexpr const char *kReadByViewer =
    "(senderId = :viewer OR EXISTS (SELECT 1 FROM MessageReceipts r WHERE r.message_uuid = Messages.uuid "
    "AND r.read_at IS NOT NULL AND r.user_uuid IN ('*', (SELECT uuid FROM Users WHERE id = :viewer))))";

// Ordre chronologique : heure d'envoi (stockee en UTC, cf. insert), puis ordre
// d'arrivee a egalite. datetime() normalise aussi les anciennes valeurs
// (ISO sans fuseau ou "AAAA-MM-JJ HH:MM:SS"). Trier par id seul affichait un
// message recu en retard (rattrapage) apres des messages plus recents.
constexpr const char *kChronological = "datetime(timestamp) ASC, id ASC";
constexpr const char *kReverseChronological = "datetime(timestamp) DESC, id DESC";

QString columns(bool perViewer = false)
{
    return QString::fromLatin1(kColumnsTemplate).arg(perViewer ? QLatin1String(kReadByViewer) : QLatin1String("is_read"));
}

int statusRank(const QString &status)
{
    if (status == models::Message::Pending) return 0;
    if (status == models::Message::Delivered) return 2;
    if (status == models::Message::Read) return 3;
    return 1; // sent (ou valeur inconnue)
}

QVariant isoOrNullVariant(const QDateTime &at)
{
    return at.isValid() ? QVariant(at.toUTC().toString(Qt::ISODate)) : QVariant(QMetaType(QMetaType::QString));
}

models::Message messageFromQuery(const QSqlQuery &query)
{
    models::Message msg(
        query.value(0).toLongLong(),
        query.value(1).toLongLong(),
        query.value(2).toLongLong(),
        query.value(3).toString()
    );
    msg.setTimestamp(QDateTime::fromString(query.value(4).toString(), Qt::ISODate));
    msg.setRead(query.value(5).toBool());
    msg.setUuid(query.value(6).toString());
    const QString status = query.value(7).toString();
    msg.setDeliveryStatus(status.isEmpty() ? models::Message::Sent : status);
    msg.setEditedAt(QDateTime::fromString(query.value(8).toString(), Qt::ISODate));
    msg.setDeletedAt(QDateTime::fromString(query.value(9).toString(), Qt::ISODate));
    return msg;
}

} // namespace

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

    // Toujours en UTC : une heure locale sans fuseau ne se compare pas a
    // l'heure UTC recue d'un autre poste.
    const QDateTime when = message.timestamp().isValid() ? message.timestamp() : QDateTime::currentDateTimeUtc();
    const QString timestamp = when.toUTC().toString(Qt::ISODate);
    query.prepare(QStringLiteral(
        "INSERT INTO Messages (conversationId, senderId, content, timestamp, is_read, uuid, delivery_status) "
        "VALUES (:conversationId, :senderId, :content, :timestamp, :isRead, :uuid, :status)"
    ));
    query.bindValue(QStringLiteral(":conversationId"), message.conversationId());
    query.bindValue(QStringLiteral(":senderId"), message.senderId());
    query.bindValue(QStringLiteral(":content"), message.content());
    query.bindValue(QStringLiteral(":timestamp"), timestamp);
    query.bindValue(QStringLiteral(":isRead"), message.isRead() ? 1 : 0);
    query.bindValue(QStringLiteral(":uuid"), uuid);
    query.bindValue(QStringLiteral(":status"),
                    message.deliveryStatus().isEmpty() ? models::Message::Sent : message.deliveryStatus());

    if (!query.exec()) {
        qWarning() << "Failed to insert message:" << query.lastError().text();
        return std::nullopt;
    }

    const qint64 messageId = query.lastInsertId().toLongLong();
    models::Message insertedMessage(message);
    insertedMessage.setId(messageId);
    insertedMessage.setUuid(uuid);
    insertedMessage.setTimestamp(when.toUTC());
    return insertedMessage;
}

QVector<models::Message> MessageRepository::getMessages(qint64 conversationId, int limit, int offset,
                                                        qint64 viewerUserId)
{
    QVector<models::Message> messages;

    if (!m_dbManager) {
        return messages;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    // Les `limit` messages les plus RECENTS (offset compte depuis le plus
    // recent), rendus du plus ancien au plus recent. Prendre les premiers par
    // id cachait les nouveaux messages des qu'une conversation depassait la
    // limite.
    query.prepare(QStringLiteral(
        "SELECT * FROM ("
        "  SELECT %1 FROM Messages WHERE conversationId = :conversationId "
        "  ORDER BY %2 LIMIT :limit OFFSET :offset"
        ") ORDER BY %3").arg(columns(viewerUserId > 0), QLatin1String(kReverseChronological),
                             QLatin1String(kChronological)));
    query.bindValue(QStringLiteral(":conversationId"), conversationId);
    query.bindValue(QStringLiteral(":limit"), limit);
    query.bindValue(QStringLiteral(":offset"), offset);
    if (viewerUserId > 0)
        query.bindValue(QStringLiteral(":viewer"), viewerUserId);

    if (query.exec()) {
        while (query.next()) {
            messages.append(messageFromQuery(query));
        }
    } else {
        qWarning() << "getMessages:" << query.lastError().text();
    }

    return messages;
}

std::optional<models::Message> MessageRepository::getLastMessage(qint64 conversationId)
{
    if (!m_dbManager) {
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    query.prepare(QStringLiteral(
        "SELECT %1 FROM Messages WHERE conversationId = :conversationId ORDER BY %2 LIMIT 1")
                      .arg(columns(), QLatin1String(kReverseChronological)));
    query.bindValue(QStringLiteral(":conversationId"), conversationId);

    if (!query.exec() || !query.next()) {
        return std::nullopt;
    }
    return messageFromQuery(query);
}

int MessageRepository::getMessageCount(qint64 conversationId)
{
    if (!m_dbManager) {
        return 0;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    query.prepare(QStringLiteral(
        "SELECT COUNT(*) FROM Messages WHERE conversationId = :conversationId"));
    query.bindValue(QStringLiteral(":conversationId"), conversationId);

    if (query.exec() && query.next()) {
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

    query.prepare(QStringLiteral("UPDATE Messages SET is_read = 1 WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), messageId);
    if (!query.exec())
        return false;

    QSqlQuery receiptQuery(db);
    receiptQuery.prepare(QStringLiteral(
        "INSERT OR IGNORE INTO MessageReceipts (message_uuid, user_uuid, delivered_at, read_at, pending_send) "
        "SELECT uuid, '*', timestamp, :now, 0 FROM Messages WHERE id = :id AND uuid IS NOT NULL AND uuid <> ''"));
    receiptQuery.bindValue(QStringLiteral(":now"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    receiptQuery.bindValue(QStringLiteral(":id"), messageId);
    receiptQuery.exec();
    return true;
}

QStringList MessageRepository::unreadMessageUuids(qint64 conversationId, qint64 userId) const
{
    QStringList uuids;
    if (!m_dbManager)
        return uuids;

    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral(
        "SELECT uuid FROM Messages WHERE conversationId = :conversationId AND senderId != :viewer "
        "AND uuid IS NOT NULL AND uuid <> '' AND NOT %1").arg(QLatin1String(kReadByViewer)));
    query.bindValue(QStringLiteral(":conversationId"), conversationId);
    query.bindValue(QStringLiteral(":viewer"), userId);
    if (!query.exec()) {
        qWarning() << "unreadMessageUuids:" << query.lastError().text();
        return uuids;
    }
    while (query.next())
        uuids << query.value(0).toString();
    return uuids;
}

bool MessageRepository::markConversationAsRead(qint64 conversationId, qint64 userId)
{
    if (!m_dbManager) {
        return false;
    }

    QSqlDatabase db = m_dbManager->database();

    // Accuses "lu" de cet utilisateur (etat propre a chacun).
    const QString now = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    QSqlQuery userQuery(db);
    userQuery.prepare(QStringLiteral("SELECT uuid FROM Users WHERE id = :id"));
    userQuery.bindValue(QStringLiteral(":id"), userId);
    const QString userUuid = userQuery.exec() && userQuery.next() ? userQuery.value(0).toString() : QString();
    if (!userUuid.isEmpty()) {
        for (const QString &uuid : unreadMessageUuids(conversationId, userId)) {
            upsertReceipt({uuid, userUuid, QDateTime::fromString(now, Qt::ISODate),
                           QDateTime::fromString(now, Qt::ISODate)}, true);
        }
    }

    // Ancien indicateur par poste, garde pour compatibilite.
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "UPDATE Messages SET is_read = 1 "
        "WHERE conversationId = :conversationId AND senderId != :userId"));
    query.bindValue(QStringLiteral(":conversationId"), conversationId);
    query.bindValue(QStringLiteral(":userId"), userId);

    return query.exec();
}

int MessageRepository::getUnreadCount(qint64 conversationId, qint64 userId)
{
    if (!m_dbManager) {
        return 0;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    // Ne compte que les messages recus (senderId != userId) et non supprimes,
    // que CET utilisateur n'a pas lus (accuses : un autre utilisateur du meme
    // poste qui lit la conversation ne les acquitte pas pour lui).
    query.prepare(QStringLiteral(
        "SELECT COUNT(*) FROM Messages "
        "WHERE conversationId = :conversationId AND senderId != :viewer AND deleted_at IS NULL AND NOT %1")
                      .arg(QLatin1String(kReadByViewer)));
    query.bindValue(QStringLiteral(":conversationId"), conversationId);
    query.bindValue(QStringLiteral(":viewer"), userId);

    if (query.exec() && query.next()) {
        return query.value(0).toInt();
    }

    return 0;
}

std::optional<models::Message> MessageRepository::findByUuid(const QString &uuid) const
{
    if (!m_dbManager || uuid.isEmpty()) {
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);
    query.prepare(QStringLiteral("SELECT %1 FROM Messages WHERE uuid = :uuid").arg(columns()));
    query.bindValue(QStringLiteral(":uuid"), uuid);

    if (!query.exec() || !query.next()) {
        return std::nullopt;
    }
    return messageFromQuery(query);
}

QVector<models::Message> MessageRepository::pendingMessages(qint64 senderId) const
{
    QVector<models::Message> messages;
    if (!m_dbManager) {
        return messages;
    }

    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral("SELECT %1 FROM Messages WHERE delivery_status = :status AND senderId = :senderId ORDER BY %2")
                      .arg(columns(), QLatin1String(kChronological)));
    query.bindValue(QStringLiteral(":status"), models::Message::Pending);
    query.bindValue(QStringLiteral(":senderId"), senderId);
    if (!query.exec()) {
        qWarning() << "pendingMessages:" << query.lastError().text();
        return messages;
    }
    while (query.next()) {
        messages.append(messageFromQuery(query));
    }
    return messages;
}

QVector<models::Message> MessageRepository::allPendingMessages() const
{
    QVector<models::Message> messages;
    if (!m_dbManager) {
        return messages;
    }

    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral("SELECT %1 FROM Messages WHERE delivery_status = :status ORDER BY %2")
                      .arg(columns(), QLatin1String(kChronological)));
    query.bindValue(QStringLiteral(":status"), models::Message::Pending);
    if (!query.exec()) {
        qWarning() << "allPendingMessages:" << query.lastError().text();
        return messages;
    }
    while (query.next()) {
        messages.append(messageFromQuery(query));
    }
    return messages;
}

bool MessageRepository::setDeliveryStatus(const QString &uuid, const QString &status)
{
    if (!m_dbManager || uuid.isEmpty()) {
        return false;
    }
    const auto current = findByUuid(uuid);
    if (!current || statusRank(status) <= statusRank(current->deliveryStatus()))
        return false;

    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral("UPDATE Messages SET delivery_status = :status WHERE uuid = :uuid"));
    query.bindValue(QStringLiteral(":status"), status);
    query.bindValue(QStringLiteral(":uuid"), uuid);
    return query.exec() && query.numRowsAffected() > 0;
}

bool MessageRepository::updateContent(const QString &uuid, const QString &content, const QDateTime &editedAt)
{
    const auto current = findByUuid(uuid);
    if (!m_dbManager || !current || current->isDeleted())
        return false;
    // Modifications concurrentes : la plus recente gagne.
    if (current->editedAt().isValid() && editedAt.isValid() && editedAt <= current->editedAt())
        return false;

    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral("UPDATE Messages SET content = :content, edited_at = :at WHERE uuid = :uuid"));
    query.bindValue(QStringLiteral(":content"), content);
    query.bindValue(QStringLiteral(":at"), isoOrNullVariant(editedAt.isValid() ? editedAt : QDateTime::currentDateTimeUtc()));
    query.bindValue(QStringLiteral(":uuid"), uuid);
    return query.exec() && query.numRowsAffected() > 0;
}

bool MessageRepository::markDeleted(const QString &uuid, const QDateTime &deletedAt)
{
    const auto current = findByUuid(uuid);
    if (!m_dbManager || !current || current->isDeleted())
        return false;

    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral("UPDATE Messages SET content = '', deleted_at = :at WHERE uuid = :uuid"));
    query.bindValue(QStringLiteral(":at"), isoOrNullVariant(deletedAt.isValid() ? deletedAt : QDateTime::currentDateTimeUtc()));
    query.bindValue(QStringLiteral(":uuid"), uuid);
    return query.exec() && query.numRowsAffected() > 0;
}

bool MessageRepository::removePending(const QString &uuid)
{
    if (!m_dbManager || uuid.isEmpty())
        return false;
    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral("DELETE FROM Messages WHERE uuid = :uuid AND delivery_status = :status"));
    query.bindValue(QStringLiteral(":uuid"), uuid);
    query.bindValue(QStringLiteral(":status"), models::Message::Pending);
    return query.exec() && query.numRowsAffected() > 0;
}

std::optional<MessageReceipt> MessageRepository::receipt(const QString &messageUuid, const QString &userUuid) const
{
    if (!m_dbManager)
        return std::nullopt;
    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral(
        "SELECT delivered_at, read_at FROM MessageReceipts WHERE message_uuid = :m AND user_uuid = :u"));
    query.bindValue(QStringLiteral(":m"), messageUuid);
    query.bindValue(QStringLiteral(":u"), userUuid);
    if (!query.exec() || !query.next())
        return std::nullopt;
    return MessageReceipt{messageUuid, userUuid,
                          QDateTime::fromString(query.value(0).toString(), Qt::ISODate),
                          QDateTime::fromString(query.value(1).toString(), Qt::ISODate)};
}

bool MessageRepository::upsertReceipt(const MessageReceipt &incoming, bool pendingSend)
{
    if (!m_dbManager || incoming.messageUuid.isEmpty() || incoming.userUuid.isEmpty())
        return false;

    // "Lu" implique "remis".
    MessageReceipt next = incoming;
    if (next.readAt.isValid() && !next.deliveredAt.isValid())
        next.deliveredAt = next.readAt;

    const auto current = receipt(incoming.messageUuid, incoming.userUuid);
    if (current) {
        // Les heures deja connues sont gardees : un accuse ne recule jamais.
        if (current->deliveredAt.isValid()) next.deliveredAt = current->deliveredAt;
        if (current->readAt.isValid()) next.readAt = current->readAt;
        if (next.deliveredAt == current->deliveredAt && next.readAt == current->readAt)
            return false;
    } else if (!next.deliveredAt.isValid() && !next.readAt.isValid()) {
        return false;
    }

    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral(
        "INSERT INTO MessageReceipts (message_uuid, user_uuid, delivered_at, read_at, pending_send) "
        "VALUES (:m, :u, :d, :r, :p) "
        "ON CONFLICT(message_uuid, user_uuid) DO UPDATE SET delivered_at = :d, read_at = :r, "
        "pending_send = MAX(pending_send, :p)"));
    query.bindValue(QStringLiteral(":m"), next.messageUuid);
    query.bindValue(QStringLiteral(":u"), next.userUuid);
    query.bindValue(QStringLiteral(":d"), isoOrNullVariant(next.deliveredAt));
    query.bindValue(QStringLiteral(":r"), isoOrNullVariant(next.readAt));
    query.bindValue(QStringLiteral(":p"), pendingSend ? 1 : 0);
    if (!query.exec()) {
        qWarning() << "upsertReceipt:" << query.lastError().text();
        return false;
    }
    return true;
}

QVector<MessageReceipt> MessageRepository::pendingReceipts() const
{
    QVector<MessageReceipt> receipts;
    if (!m_dbManager)
        return receipts;
    QSqlQuery query(m_dbManager->database());
    if (!query.exec(QStringLiteral(
            "SELECT message_uuid, user_uuid, delivered_at, read_at FROM MessageReceipts "
            "WHERE pending_send = 1 AND user_uuid <> '*'")))
        return receipts;
    while (query.next()) {
        receipts.append({query.value(0).toString(), query.value(1).toString(),
                         QDateTime::fromString(query.value(2).toString(), Qt::ISODate),
                         QDateTime::fromString(query.value(3).toString(), Qt::ISODate)});
    }
    return receipts;
}

void MessageRepository::clearPendingReceipt(const QString &messageUuid, const QString &userUuid)
{
    if (!m_dbManager)
        return;
    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral(
        "UPDATE MessageReceipts SET pending_send = 0 WHERE message_uuid = :m AND user_uuid = :u"));
    query.bindValue(QStringLiteral(":m"), messageUuid);
    query.bindValue(QStringLiteral(":u"), userUuid);
    query.exec();
}

std::optional<QString> MessageRepository::refreshDeliveryStatus(const QString &messageUuid)
{
    const auto message = findByUuid(messageUuid);
    if (!m_dbManager || !message || message->isPending())
        return std::nullopt;

    QSqlDatabase db = m_dbManager->database();
    // Destinataires : l'autre participant (conversation directe) ou les autres
    // membres du groupe.
    QSqlQuery recipients(db);
    recipients.prepare(QStringLiteral(
        "SELECT u.uuid FROM Conversations c JOIN Users u ON u.id IN (c.participant1_id, c.participant2_id) "
        "WHERE c.id = :conv AND c.type <> 'group' AND u.id <> :sender "
        "UNION "
        "SELECT u.uuid FROM Groups g JOIN GroupMembers gm ON gm.group_id = g.id JOIN Users u ON u.id = gm.user_id "
        "WHERE g.conversation_id = :conv AND u.id <> :sender"));
    recipients.bindValue(QStringLiteral(":conv"), message->conversationId());
    recipients.bindValue(QStringLiteral(":sender"), message->senderId());
    if (!recipients.exec())
        return std::nullopt;
    int total = 0, delivered = 0, read = 0;
    while (recipients.next()) {
        const QString uuid = recipients.value(0).toString();
        if (uuid.isEmpty())
            continue;
        ++total;
        if (const auto r = receipt(messageUuid, uuid)) {
            if (r->deliveredAt.isValid()) ++delivered;
            if (r->readAt.isValid()) ++read;
        }
    }
    if (total == 0)
        return std::nullopt;

    const QString status = read == total ? models::Message::Read
                         : delivered == total ? models::Message::Delivered
                                              : models::Message::Sent;
    if (!setDeliveryStatus(messageUuid, status))
        return std::nullopt;
    return status;
}

QStringList MessageRepository::undeliveredMessageUuids(qint64 userId) const
{
    QStringList uuids;
    if (!m_dbManager)
        return uuids;
    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral(
        "SELECT m.uuid FROM Messages m JOIN Conversations c ON c.id = m.conversationId "
        "WHERE m.senderId <> :u AND m.deleted_at IS NULL AND m.uuid IS NOT NULL AND m.uuid <> '' "
        "AND (c.participant1_id = :u OR c.participant2_id = :u OR c.id IN ("
        "     SELECT g.conversation_id FROM Groups g JOIN GroupMembers gm ON gm.group_id = g.id WHERE gm.user_id = :u)) "
        "AND NOT EXISTS (SELECT 1 FROM MessageReceipts r WHERE r.message_uuid = m.uuid "
        "     AND r.user_uuid = (SELECT uuid FROM Users WHERE id = :u) AND r.delivered_at IS NOT NULL)"));
    query.bindValue(QStringLiteral(":u"), userId);
    if (!query.exec()) {
        qWarning() << "undeliveredMessageUuids:" << query.lastError().text();
        return uuids;
    }
    while (query.next())
        uuids << query.value(0).toString();
    return uuids;
}

} // namespace database
