#include "SyncLogRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>
#include <QVariant>
#include <QDateTime>
#include <QUuid>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <QHash>
#include <QSet>
#include <QTimeZone>
#include <limits>

#include "UserRepository.h"

namespace database {

SyncLogRepository::SyncLogRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

SyncLogRepository::~SyncLogRepository() = default;

bool SyncLogRepository::append(const models::SyncLogEntry &entry)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO SyncLog (entry_uuid, table_name, record_uuid, operation, payload_json, "
        "lamport_clock, epoch, origin_machine_id, updated_at) "
        "VALUES (:entry_uuid, :table_name, :record_uuid, :operation, :payload, "
        ":lamport, :epoch, :origin, :updated_at)"));

    const QString entryUuid = entry.entryUuid().isEmpty()
        ? QUuid::createUuid().toString(QUuid::WithoutBraces)
        : entry.entryUuid();

    query.bindValue(QStringLiteral(":entry_uuid"), entryUuid);
    query.bindValue(QStringLiteral(":table_name"), entry.tableName());
    query.bindValue(QStringLiteral(":record_uuid"), entry.recordUuid());
    query.bindValue(QStringLiteral(":operation"), entry.operation());
    query.bindValue(QStringLiteral(":payload"),
                     entry.payloadJson().isNull() ? QVariant(QVariant::String) : entry.payloadJson());
    query.bindValue(QStringLiteral(":lamport"), entry.lamportClock());
    query.bindValue(QStringLiteral(":epoch"), entry.epoch());
    query.bindValue(QStringLiteral(":origin"), entry.originMachineId());
    query.bindValue(QStringLiteral(":updated_at"),
                     entry.updatedAt().isValid()
                         ? entry.updatedAt().toString(Qt::ISODate)
                         : QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

models::SyncLogEntry SyncLogRepository::entryFromQuery(const QSqlQuery &query) const
{
    // Enregistrement lu une fois par ligne : value(nom) le reconstruisait a chaque colonne.
    const QSqlRecord rec = query.record();
    models::SyncLogEntry entry;
    entry.setEntryUuid(query.value(rec.indexOf(QLatin1String("entry_uuid"))).toString());
    entry.setTableName(query.value(rec.indexOf(QLatin1String("table_name"))).toString());
    entry.setRecordUuid(query.value(rec.indexOf(QLatin1String("record_uuid"))).toString());
    entry.setOperation(query.value(rec.indexOf(QLatin1String("operation"))).toString());
    entry.setPayloadJson(query.value(rec.indexOf(QLatin1String("payload_json"))).toString());
    entry.setLamportClock(query.value(rec.indexOf(QLatin1String("lamport_clock"))).toLongLong());
    entry.setEpoch(query.value(rec.indexOf(QLatin1String("epoch"))).toInt());
    entry.setOriginMachineId(query.value(rec.indexOf(QLatin1String("origin_machine_id"))).toString());
    entry.setUpdatedAt(QDateTime::fromString(query.value(rec.indexOf(QLatin1String("updated_at"))).toString(), Qt::ISODate));
    return entry;
}

std::vector<models::SyncLogEntry> SyncLogRepository::entriesSinceEpoch(int fromEpoch) const
{
    std::vector<models::SyncLogEntry> entries;

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM SyncLog WHERE epoch >= :from_epoch ORDER BY lamport_clock ASC, id ASC"));
    query.bindValue(QStringLiteral(":from_epoch"), fromEpoch);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return entries;
    }
    while (query.next()) {
        entries.push_back(entryFromQuery(query));
    }
    return entries;
}

std::vector<models::SyncLogEntry> SyncLogRepository::entriesAfterId(qint64 afterId) const
{
    std::vector<models::SyncLogEntry> entries;

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM SyncLog WHERE id > :after ORDER BY id ASC"));
    query.bindValue(QStringLiteral(":after"), afterId);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return entries;
    }
    while (query.next()) {
        entries.push_back(entryFromQuery(query));
    }
    return entries;
}

qint64 SyncLogRepository::maxEntryId() const
{
    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT COALESCE(MAX(id), 0) FROM SyncLog"))) {
        m_lastError = query.lastError().text();
        return 0;
    }
    return query.next() ? query.value(0).toLongLong() : 0;
}

bool SyncLogRepository::hasRecord(const QString &tableName, const QString &recordUuid) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT 1 FROM SyncLog WHERE table_name = :table AND record_uuid = :uuid LIMIT 1"));
    query.bindValue(QStringLiteral(":table"), tableName);
    query.bindValue(QStringLiteral(":uuid"), recordUuid);
    return query.exec() && query.next();
}

qint64 SyncLogRepository::syncCursor(const QString &serverKey, const QString &userUuid) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT last_log_id FROM SyncCursors WHERE server_key = :server AND user_uuid = :user"));
    query.bindValue(QStringLiteral(":server"), serverKey);
    query.bindValue(QStringLiteral(":user"), userUuid);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return 0;
    }
    return query.next() ? query.value(0).toLongLong() : 0;
}

bool SyncLogRepository::setSyncCursor(const QString &serverKey, const QString &userUuid, qint64 lastLogId)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO SyncCursors (server_key, user_uuid, last_log_id, updated_at) "
        "VALUES (:server, :user, :id, datetime('now')) "
        "ON CONFLICT(server_key, user_uuid) DO UPDATE SET last_log_id = :id, updated_at = datetime('now')"));
    query.bindValue(QStringLiteral(":server"), serverKey);
    query.bindValue(QStringLiteral(":user"), userUuid);
    query.bindValue(QStringLiteral(":id"), lastLogId);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

std::optional<models::SyncLogEntry> SyncLogRepository::restrictUserEntry(const models::SyncLogEntry &entry)
{
    if (entry.tableName() != QStringLiteral("Users"))
        return entry;
    if (entry.operation() == models::SyncOperation::Delete)
        return std::nullopt;

    QJsonObject payload = QJsonDocument::fromJson(entry.payloadJson().toUtf8()).object();
    if (entry.operation() == models::SyncOperation::Insert) {
        // Nouveau compte accepte, mais jamais administrateur. Une creation ne peut
        // pas detourner un compte existant (uuid deja connu : sans effet).
        payload.insert(QStringLiteral("role"), QStringLiteral("user"));
    } else {
        // Mise a jour : ni role ni mot de passe (applyUserEntry garde alors
        // les valeurs locales).
        payload.remove(QStringLiteral("role"));
        payload.remove(QStringLiteral("passwordHash"));
        payload.remove(QStringLiteral("passwordSalt"));
    }
    models::SyncLogEntry restricted = entry;
    restricted.setPayloadJson(QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
    return restricted;
}

std::vector<models::SyncLogEntry> SyncLogRepository::restrictUserEntries(const std::vector<models::SyncLogEntry> &entries)
{
    std::vector<models::SyncLogEntry> out;
    out.reserve(entries.size());
    for (const auto &entry : entries) {
        if (auto restricted = restrictUserEntry(entry))
            out.push_back(*restricted);
    }
    return out;
}

int SyncLogRepository::applyBatch(const std::vector<models::SyncLogEntry> &batch)
{
    int inserted = 0;
    m_lastBatchPending = 0;
    // Une seule transaction pour tout le lot : bien plus rapide qu'une ecriture
    // disque par entree. Si une transaction est deja ouverte, on s'y inscrit.
    const bool ownTransaction = m_db.transaction();

    // CORRECTIF (retry des entrees differees) : le batch recu n'est PAS
    // garanti d'etre trie par dependance (Users avant Groups avant
    // GroupMembers/Messages) -- il est trie par lamport_clock, cf. le
    // commentaire d'appelant. Une premiere passe suffit donc rarement a
    // tout appliquer : un Groupe dont l'owner arrive plus tard DANS CE
    // MEME BATCH echouait jusqu'ici definitivement (aucune deuxieme passe),
    // et restait "differe" sans qu'aucune reconciliation ulterieure ne le
    // rejoue jamais vraiment (fromEpoch=0 n'est redemande qu'une seule
    // fois, a la connexion initiale). On boucle donc sur les entrees
    // encore en echec jusqu'a ce qu'une passe complete n'apporte plus
    // aucun progres (borne naturelle : au plus batch.size() passes).
    std::vector<models::SyncLogEntry> pending;
    pending.reserve(batch.size());

    for (const auto &entry : batch) {
        QSqlQuery check(m_db);
        check.prepare(QStringLiteral("SELECT 1 FROM SyncLog WHERE entry_uuid = :uuid"));
        check.bindValue(QStringLiteral(":uuid"), entry.entryUuid());
        if (!check.exec()) { m_lastError = check.lastError().text(); continue; }
        if (check.next()) continue; // déjà journalisée ET déjà appliquée

        pending.push_back(entry);
    }

    bool progressed = true;
    while (progressed && !pending.empty()) {
        progressed = false;
        std::vector<models::SyncLogEntry> stillPending;
        stillPending.reserve(pending.size());

        for (const auto &entry : pending) {
            if (!applyDomainEntry(entry)) {
                // échec (dépendance pas encore connue) : on NE journalise
                // PAS, pour retenter cette meme entree a la passe suivante
                // (si une autre entree du batch resout la dependance) ou,
                // a defaut, lors d'une prochaine reconciliation complete.
                stillPending.push_back(entry);
                continue;
            }
            if (append(entry)) {
                ++inserted;
                progressed = true;
                qInfo() << "SyncLogRepository::applyBatch: entree" << entry.tableName()
                        << entry.recordUuid() << "rejouee avec succes apres resolution de sa dependance"
                        << "(entry_uuid=" << entry.entryUuid() << ")";
            }
        }
        pending.swap(stillPending);
    }

    if (!pending.empty()) {
        qWarning() << "SyncLogRepository::applyBatch:" << pending.size()
                   << "entree(s) toujours differee(s) apres ce batch (dependance introuvable localement),"
                   << "en attente d'une prochaine reconciliation";
    }
    m_lastBatchPending = static_cast<int>(pending.size());

    if (ownTransaction && !m_db.commit()) {
        m_lastError = m_db.lastError().text();
        m_db.rollback();
        m_lastBatchPending = static_cast<int>(batch.size()); // rien d'acquis
        return 0;
    }
    return inserted;
}

qint64 SyncLogRepository::highestLamportClock() const
{
    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT MAX(lamport_clock) FROM SyncLog"))) {
        m_lastError = query.lastError().text();
        return 0;
    }
    if (query.next()) {
        return query.value(0).toLongLong();
    }
    return 0;
}

bool SyncLogRepository::markPeerSynced(const QString &machineUuid, int epoch)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO PeerSyncState (machine_uuid, last_synced_epoch, last_synced_at) "
        "VALUES (:uuid, :epoch, :now) "
        "ON CONFLICT(machine_uuid) DO UPDATE SET last_synced_epoch = :epoch, last_synced_at = :now"));
    query.bindValue(QStringLiteral(":uuid"), machineUuid);
    query.bindValue(QStringLiteral(":epoch"), epoch);
    query.bindValue(QStringLiteral(":now"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

int SyncLogRepository::lastSyncedEpoch(const QString &machineUuid) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT last_synced_epoch FROM PeerSyncState WHERE machine_uuid = :uuid"));
    query.bindValue(QStringLiteral(":uuid"), machineUuid);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return 0;
    }
    if (query.next()) {
        return query.value(0).toInt();
    }
    return 0;
}


bool SyncLogRepository::applyDomainEntry(const models::SyncLogEntry &entry)
{
    if (entry.tableName() == QStringLiteral("Messages")) {
        return applyMessageEntry(entry);
    }
    if (entry.tableName() == QStringLiteral("Groups")) {
        return applyGroupEntry(entry);
    }
    if (entry.tableName() == QStringLiteral("GroupMembers")) {
        return applyGroupMemberEntry(entry);
    }
    if (entry.tableName() == QStringLiteral("Users")) {
        return applyUserEntry(entry);
    }
    if (entry.tableName() == QStringLiteral("MessageReceipts")) {
        return applyReceiptEntry(entry);
    }

    // Les tables non encore supportees restent au moins fusionnees dans SyncLog.
    return true;
}

qint64 SyncLogRepository::ensureConversationByUuid(const QString &conversationUuid, const QString &type, const QString &name,
                                                     qint64 participant1Id, qint64 participant2Id)
{
    if (conversationUuid.isEmpty()) {
        return -1;
    }

    QSqlQuery findQuery(m_db);
    findQuery.prepare(QStringLiteral(
        "SELECT id, participant1_id, participant2_id, type FROM Conversations WHERE uuid = :uuid"));
    findQuery.bindValue(QStringLiteral(":uuid"), conversationUuid);
    if (!findQuery.exec()) {
        m_lastError = findQuery.lastError().text();
        return -1;
    }
    if (findQuery.next()) {
        const qint64 conversationId = findQuery.value(0).toLongLong();
        // Conversation creee a tort en "individuelle" par un message de groupe
        // arrive avant son groupe (ancienne version) : corrigee quand le groupe arrive.
        if (type == QStringLiteral("group") && findQuery.value(3).toString() != type) {
            QSqlQuery fixType(m_db);
            fixType.prepare(QStringLiteral("UPDATE Conversations SET type = 'group', name = :name WHERE id = :id"));
            fixType.bindValue(QStringLiteral(":name"), name.isEmpty() ? QStringLiteral("Conversation") : name);
            fixType.bindValue(QStringLiteral(":id"), conversationId);
            if (!fixType.exec())
                m_lastError = fixType.lastError().text(); // non bloquant
        }
        // Backfill : une conversation deja creee ici par un appel anterieur
        // (avant ce correctif, ou parce que l'appelant ne connaissait pas
        // encore les deux participants) peut avoir participant1_id/
        // participant2_id a NULL. Si l'appelant les connait maintenant, on
        // les renseigne pour que la conversation redevienne visible dans
        // MessagingManager::getUserConversations().
        if (participant1Id > 0 && participant2Id > 0
            && (findQuery.value(1).isNull() || findQuery.value(2).isNull())) {
            QSqlQuery backfillQuery(m_db);
            backfillQuery.prepare(QStringLiteral(
                "UPDATE Conversations SET participant1_id = :p1, participant2_id = :p2 "
                "WHERE id = :id AND (participant1_id IS NULL OR participant2_id IS NULL)"));
            backfillQuery.bindValue(QStringLiteral(":p1"), participant1Id);
            backfillQuery.bindValue(QStringLiteral(":p2"), participant2Id);
            backfillQuery.bindValue(QStringLiteral(":id"), conversationId);
            if (!backfillQuery.exec()) {
                m_lastError = backfillQuery.lastError().text();
                // Non bloquant : la conversation existe deja et reste utilisable.
            }
        }
        return conversationId;
    }

    // Pas encore connue localement : on la cree avec un NOUVEL id local
    // (AUTOINCREMENT), jamais celui de la machine d'origine - seul l'uuid
    // est une reference valable inter-postes. participant1_id/participant2_id
    // sont renseignes quand l'appelant les connait (conversation
    // individuelle) : sans eux la conversation resterait a jamais invisible
    // dans MessagingManager::getUserConversations(), qui filtre dessus.
    QSqlQuery insertQuery(m_db);
    insertQuery.prepare(QStringLiteral(
        "INSERT INTO Conversations (type, name, uuid, participant1_id, participant2_id) "
        "VALUES (:type, :name, :uuid, :p1, :p2)"));
    insertQuery.bindValue(QStringLiteral(":type"), type.isEmpty() ? QStringLiteral("individual") : type);
    insertQuery.bindValue(QStringLiteral(":name"), name.isEmpty() ? QStringLiteral("Conversation") : name);
    insertQuery.bindValue(QStringLiteral(":uuid"), conversationUuid);
    if (participant1Id > 0) {
        insertQuery.bindValue(QStringLiteral(":p1"), participant1Id);
    } else {
        insertQuery.bindValue(QStringLiteral(":p1"), QVariant(QMetaType(QMetaType::LongLong)));
    }
    if (participant2Id > 0) {
        insertQuery.bindValue(QStringLiteral(":p2"), participant2Id);
    } else {
        insertQuery.bindValue(QStringLiteral(":p2"), QVariant(QMetaType(QMetaType::LongLong)));
    }
    if (!insertQuery.exec()) {
        m_lastError = insertQuery.lastError().text();
        return -1;
    }
    return insertQuery.lastInsertId().toLongLong();
}

bool SyncLogRepository::applyMessageChange(const models::SyncLogEntry &entry)
{
    const QJsonObject obj = QJsonDocument::fromJson(entry.payloadJson().toUtf8()).object();
    QSqlQuery current(m_db);
    current.prepare(QStringLiteral(
        "SELECT u.uuid FROM Messages m JOIN Users u ON u.id = m.senderId WHERE m.uuid = :uuid"));
    current.bindValue(QStringLiteral(":uuid"), entry.recordUuid());
    // Message absent ici (pas encore recu, ou hors de nos conversations) : rien a faire.
    if (!current.exec() || !current.next())
        return true;
    // Seul l'auteur modifie ou supprime son message.
    if (current.value(0).toString() != obj.value(QStringLiteral("senderUuid")).toString())
        return true;

    QSqlQuery query(m_db);
    if (entry.operation() == models::SyncOperation::Delete) {
        query.prepare(QStringLiteral(
            "UPDATE Messages SET content = '', deleted_at = :at WHERE uuid = :uuid AND deleted_at IS NULL"));
        query.bindValue(QStringLiteral(":at"), obj.value(QStringLiteral("deletedAt")).toString(
                                                   QDateTime::currentDateTimeUtc().toString(Qt::ISODate)));
    } else {
        // Modifications concurrentes : la plus recente gagne.
        query.prepare(QStringLiteral(
            "UPDATE Messages SET content = :content, edited_at = :at WHERE uuid = :uuid AND deleted_at IS NULL "
            "AND (edited_at IS NULL OR datetime(edited_at) < datetime(:at))"));
        query.bindValue(QStringLiteral(":content"), obj.value(QStringLiteral("content")).toString());
        query.bindValue(QStringLiteral(":at"), obj.value(QStringLiteral("editedAt")).toString(
                                                   QDateTime::currentDateTimeUtc().toString(Qt::ISODate)));
    }
    query.bindValue(QStringLiteral(":uuid"), entry.recordUuid());
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool SyncLogRepository::applyReceiptEntry(const models::SyncLogEntry &entry)
{
    const QJsonObject obj = QJsonDocument::fromJson(entry.payloadJson().toUtf8()).object();
    const QString messageUuid = obj.value(QStringLiteral("messageUuid")).toString();
    const QString userUuid = obj.value(QStringLiteral("userUuid")).toString();
    if (messageUuid.isEmpty() || userUuid.isEmpty() || userUuid == QStringLiteral("*"))
        return true;
    QString deliveredAt = obj.value(QStringLiteral("deliveredAt")).toString();
    const QString readAt = obj.value(QStringLiteral("readAt")).toString();
    if (deliveredAt.isEmpty())
        deliveredAt = readAt;
    if (deliveredAt.isEmpty())
        return true;

    // Les heures deja connues ici sont gardees ; l'accuse produit ici n'est plus
    // a transmettre si le serveur le connait deja en entier.
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO MessageReceipts (message_uuid, user_uuid, delivered_at, read_at, pending_send) "
        "VALUES (:m, :u, :d, NULLIF(:r, ''), 0) "
        "ON CONFLICT(message_uuid, user_uuid) DO UPDATE SET "
        "  pending_send = CASE WHEN (read_at IS NULL OR NULLIF(:r, '') IS NOT NULL) THEN 0 ELSE pending_send END, "
        "  delivered_at = COALESCE(delivered_at, :d), "
        "  read_at = COALESCE(read_at, NULLIF(:r, ''))"));
    query.bindValue(QStringLiteral(":m"), messageUuid);
    query.bindValue(QStringLiteral(":u"), userUuid);
    query.bindValue(QStringLiteral(":d"), deliveredAt);
    query.bindValue(QStringLiteral(":r"), readAt);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    if (!m_touchedReceiptMessages.contains(messageUuid))
        m_touchedReceiptMessages << messageUuid;
    return true;
}

QStringList SyncLogRepository::takeTouchedReceiptMessages()
{
    QStringList out;
    out.swap(m_touchedReceiptMessages);
    return out;
}

std::optional<QJsonObject> SyncLogRepository::messageInsertPayload(const QString &messageUuid) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT payload_json FROM SyncLog WHERE table_name = 'Messages' AND record_uuid = :uuid "
        "AND operation = :op ORDER BY id ASC LIMIT 1"));
    query.bindValue(QStringLiteral(":uuid"), messageUuid);
    query.bindValue(QStringLiteral(":op"), models::SyncOperation::Insert);
    if (!query.exec() || !query.next())
        return std::nullopt;
    return QJsonDocument::fromJson(query.value(0).toString().toUtf8()).object();
}

int SyncLogRepository::compact()
{
    struct Row { qint64 id; QString record; QString op; QString payload; };
    const auto rowsOf = [this](const QString &table) {
        std::vector<Row> rows;
        QSqlQuery query(m_db);
        query.prepare(QStringLiteral(
            "SELECT id, record_uuid, operation, payload_json FROM SyncLog WHERE table_name = :t ORDER BY id ASC"));
        query.bindValue(QStringLiteral(":t"), table);
        if (query.exec()) {
            while (query.next())
                rows.push_back({query.value(0).toLongLong(), query.value(1).toString(),
                                query.value(2).toString(), query.value(3).toString()});
        }
        return rows;
    };

    QList<qint64> toRemove;
    // Accuses et membres de groupe : chaque entree porte l'etat complet, seule
    // la derniere par enregistrement compte.
    for (const QString &table : {QStringLiteral("MessageReceipts"), QStringLiteral("GroupMembers")}) {
        QHash<QString, qint64> latest;
        const auto rows = rowsOf(table);
        for (const Row &row : rows)
            latest.insert(row.record, row.id);
        for (const Row &row : rows)
            if (latest.value(row.record) != row.id) toRemove << row.id;
    }
    // Comptes : la version la plus recente (updatedAt, puis ordre d'ecriture),
    // qu'applyUserEntry applique aussi en creation si le compte est inconnu.
    {
        QHash<QString, std::pair<QDateTime, qint64>> best;
        const auto rows = rowsOf(QStringLiteral("Users"));
        for (const Row &row : rows) {
            const QDateTime at = row.op == models::SyncOperation::Delete
                ? QDateTime::fromSecsSinceEpoch(std::numeric_limits<qint32>::max(), QTimeZone::UTC)
                : QDateTime::fromString(QJsonDocument::fromJson(row.payload.toUtf8()).object()
                                            .value(QStringLiteral("updatedAt")).toString(), Qt::ISODate);
            const auto it = best.constFind(row.record);
            if (it == best.constEnd() || at > it->first || (at == it->first && row.id > it->second))
                best.insert(row.record, {at, row.id});
        }
        for (const Row &row : rows)
            if (best.value(row.record).second != row.id) toRemove << row.id;
    }
    // Messages et groupes : la creation reste ; seule la derniere modification
    // compte, et aucune apres une suppression.
    QStringList deletedMessages;
    for (const QString &table : {QStringLiteral("Messages"), QStringLiteral("Groups")}) {
        QHash<QString, qint64> lastUpdate;
        QSet<QString> deleted;
        const auto rows = rowsOf(table);
        for (const Row &row : rows) {
            if (row.op == models::SyncOperation::Update) lastUpdate.insert(row.record, row.id);
            if (row.op == models::SyncOperation::Delete) deleted.insert(row.record);
        }
        for (const Row &row : rows) {
            if (row.op == models::SyncOperation::Update
                && (deleted.contains(row.record) || lastUpdate.value(row.record) != row.id))
                toRemove << row.id;
        }
        if (table == QStringLiteral("Messages"))
            deletedMessages = deleted.values();
    }

    const bool ownTransaction = m_db.transaction();
    int removed = 0;
    for (qint64 id : std::as_const(toRemove)) {
        QSqlQuery del(m_db);
        del.prepare(QStringLiteral("DELETE FROM SyncLog WHERE id = :id"));
        del.bindValue(QStringLiteral(":id"), id);
        if (del.exec())
            removed += del.numRowsAffected();
    }
    // Le texte d'un message supprime ne reste pas dans le journal du serveur.
    for (const QString &uuid : std::as_const(deletedMessages)) {
        QSqlQuery read(m_db);
        read.prepare(QStringLiteral(
            "SELECT id, payload_json FROM SyncLog WHERE table_name = 'Messages' AND record_uuid = :uuid AND operation = :op"));
        read.bindValue(QStringLiteral(":uuid"), uuid);
        read.bindValue(QStringLiteral(":op"), models::SyncOperation::Insert);
        if (!read.exec() || !read.next())
            continue;
        QJsonObject payload = QJsonDocument::fromJson(read.value(1).toString().toUtf8()).object();
        if (payload.value(QStringLiteral("content")).toString().isEmpty())
            continue;
        payload.insert(QStringLiteral("content"), QString());
        QSqlQuery write(m_db);
        write.prepare(QStringLiteral("UPDATE SyncLog SET payload_json = :p WHERE id = :id"));
        write.bindValue(QStringLiteral(":p"), QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
        write.bindValue(QStringLiteral(":id"), read.value(0).toLongLong());
        write.exec();
    }
    if (ownTransaction && !m_db.commit()) {
        m_lastError = m_db.lastError().text();
        m_db.rollback();
        return 0;
    }
    return removed;
}

bool SyncLogRepository::applyMessageEntry(const models::SyncLogEntry &entry)
{
    if (entry.operation() != models::SyncOperation::Insert) {
        return applyMessageChange(entry);
    }

    // Deja connu localement (rejeu d'un sync_batch) : l'uuid du message
    // (entry.recordUuid()) est la seule cle de dedup valable, l'id local
    // AUTOINCREMENT de la machine d'origine n'ayant aucune raison de
    // coincider avec le notre (cf. migration 011).
    QSqlQuery existsQuery(m_db);
    existsQuery.prepare(QStringLiteral("SELECT 1 FROM Messages WHERE uuid = :uuid"));
    existsQuery.bindValue(QStringLiteral(":uuid"), entry.recordUuid());
    if (existsQuery.exec() && existsQuery.next()) {
        return true;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(entry.payloadJson().toUtf8());
    if (!doc.isObject()) {
        m_lastError = QStringLiteral("Payload Messages invalide");
        return false;
    }
    const QJsonObject obj = doc.object();
    const QString senderUuid = obj.value(QStringLiteral("senderUuid")).toString();
    const QString conversationUuid = obj.value(QStringLiteral("conversationUuid")).toString();
    const QString participant1Uuid = obj.value(QStringLiteral("participant1Uuid")).toString();
    const QString participant2Uuid = obj.value(QStringLiteral("participant2Uuid")).toString();
    const QString content = obj.value(QStringLiteral("content")).toString();
    const QString timestamp = obj.value(QStringLiteral("timestamp")).toString(QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    const bool isRead = obj.value(QStringLiteral("isRead")).toBool(false);

    UserRepository users(m_db);
    const auto sender = users.findByUuid(senderUuid);
    if (!sender.has_value()) {
        // L'utilisateur emetteur n'est pas encore connu localement (Users
        // pas encore reconcilie) : on ne peut pas inserer ce message
        // correctement, il sera rejoue lors d'un prochain sync_batch.
        m_lastError = QStringLiteral("Sender inconnu (uuid=%1), message differe").arg(senderUuid);
        return false;
    }

    // Ids locaux des deux participants, si deja connus (cf. commentaire de
    // ensureConversationByUuid ci-dessus) : sans eux, une conversation
    // individuelle reconciliee ici resterait invisible dans
    // MessagingManager::getUserConversations().
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

    // Type et nom transmis par l'emetteur : un message de groupe applique avant
    // l'entree Groups creait sinon une conversation "individuelle" definitive.
    const QString conversationType = obj.value(QStringLiteral("conversationType")).toString(QStringLiteral("individual"));
    const QString conversationName = obj.value(QStringLiteral("conversationName")).toString(QStringLiteral("Conversation"));
    const qint64 conversationId = ensureConversationByUuid(conversationUuid, conversationType, conversationName,
                                                            participant1Id, participant2Id);
    if (conversationId < 0) {
        return false;
    }

    // id local laisse a l'AUTOINCREMENT : seul entry.recordUuid() (uuid du
    // message) est une reference stable inter-postes.
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO Messages (conversationId, senderId, content, timestamp, is_read, uuid) "
        "VALUES (:conversationId, :senderId, :content, :timestamp, :isRead, :uuid)"));
    query.bindValue(QStringLiteral(":conversationId"), conversationId);
    query.bindValue(QStringLiteral(":senderId"), sender->id());
    query.bindValue(QStringLiteral(":content"), content);
    query.bindValue(QStringLiteral(":timestamp"), timestamp);
    query.bindValue(QStringLiteral(":isRead"), isRead ? 1 : 0);
    query.bindValue(QStringLiteral(":uuid"), entry.recordUuid());
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool SyncLogRepository::deleteGroupByUuid(QSqlDatabase db, const QString &groupUuid, QString *error)
{
    QSqlQuery find(db);
    find.prepare(QStringLiteral("SELECT id, conversation_id FROM Groups WHERE uuid = :uuid"));
    find.bindValue(QStringLiteral(":uuid"), groupUuid);
    if (!find.exec() || !find.next())
        return true; // deja absent : idempotent
    const qint64 groupId = find.value(0).toLongLong();
    const QVariant conversationId = find.value(1);

    // Fil du groupe, membres, groupe, puis conversation (cles etrangeres).
    const QStringList statements = {
        QStringLiteral("DELETE FROM MessageReceipts WHERE message_uuid IN (SELECT uuid FROM Messages WHERE conversationId = :conv)"),
        QStringLiteral("DELETE FROM Messages WHERE conversationId = :conv"),
        QStringLiteral("DELETE FROM GroupMembers WHERE group_id = :group"),
        QStringLiteral("DELETE FROM Groups WHERE id = :group"),
        QStringLiteral("DELETE FROM Conversations WHERE id = :conv"),
    };
    for (const QString &sql : statements) {
        QSqlQuery query(db);
        query.prepare(sql);
        if (sql.contains(QStringLiteral(":conv")))
            query.bindValue(QStringLiteral(":conv"), conversationId);
        if (sql.contains(QStringLiteral(":group")))
            query.bindValue(QStringLiteral(":group"), groupId);
        if (!query.exec()) {
            if (error) *error = query.lastError().text();
            return false;
        }
    }
    return true;
}

bool SyncLogRepository::applyGroupEntry(const models::SyncLogEntry &entry)
{
    if (entry.operation() == models::SyncOperation::Update) {
        // Renommage (seule modification d'un groupe journalisee).
        const QString name = QJsonDocument::fromJson(entry.payloadJson().toUtf8()).object()
                                 .value(QStringLiteral("name")).toString().trimmed();
        if (name.isEmpty())
            return true;
        QSqlQuery query(m_db);
        query.prepare(QStringLiteral("UPDATE Groups SET name = :name WHERE uuid = :uuid"));
        query.bindValue(QStringLiteral(":name"), name);
        query.bindValue(QStringLiteral(":uuid"), entry.recordUuid());
        if (!query.exec()) {
            m_lastError = query.lastError().text();
            return false;
        }
        QSqlQuery conv(m_db);
        conv.prepare(QStringLiteral(
            "UPDATE Conversations SET name = :name WHERE id = (SELECT conversation_id FROM Groups WHERE uuid = :uuid)"));
        conv.bindValue(QStringLiteral(":name"), name);
        conv.bindValue(QStringLiteral(":uuid"), entry.recordUuid());
        conv.exec();
        return true;
    }
    if (entry.operation() == models::SyncOperation::Delete) {
        return deleteGroupByUuid(m_db, entry.recordUuid(), &m_lastError);
    }
    if (entry.operation() != models::SyncOperation::Insert) {
        return true;
    }

    // Deja connu localement (rejeu d'un sync_batch) : entry.recordUuid() est
    // l'uuid propre du groupe (cf. Application::appendGroupSyncLog), seule
    // cle de dedup valable inter-postes (cf. migration 011).
    QSqlQuery existsQuery(m_db);
    existsQuery.prepare(QStringLiteral("SELECT 1 FROM Groups WHERE uuid = :uuid"));
    existsQuery.bindValue(QStringLiteral(":uuid"), entry.recordUuid());
    if (existsQuery.exec() && existsQuery.next()) {
        return true;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(entry.payloadJson().toUtf8());
    if (!doc.isObject()) {
        m_lastError = QStringLiteral("Payload Groups invalide");
        return false;
    }
    const QJsonObject obj = doc.object();
    const QString name = obj.value(QStringLiteral("name")).toString();
    const QString ownerUuid = obj.value(QStringLiteral("ownerUuid")).toString();
    const QString conversationUuid = obj.value(QStringLiteral("conversationUuid")).toString();
    const QJsonArray memberUuids = obj.value(QStringLiteral("memberUuids")).toArray();

    UserRepository users(m_db);
    const auto owner = users.findByUuid(ownerUuid);
    if (!owner.has_value()) {
        // Meme logique que applyMessageEntry : l'owner doit deja etre connu
        // localement (Users reconcilie avant Groups), sinon on differe.
        m_lastError = QStringLiteral("Owner inconnu (uuid=%1), groupe differe").arg(ownerUuid);
        qWarning() << "SyncLogRepository::applyGroupEntry: owner inconnu (uuid=" << ownerUuid << "), groupe differe pour prochaine reconciliation";
        return false;
    }

    const qint64 conversationId = ensureConversationByUuid(conversationUuid, QStringLiteral("group"), name);
    if (conversationId < 0) {
        return false;
    }

    QSqlQuery groupQuery(m_db);
    groupQuery.prepare(QStringLiteral(
        "INSERT INTO Groups (name, owner_id, conversation_id, uuid) "
        "VALUES (:name, :ownerId, :conversationId, :uuid)"));
    groupQuery.bindValue(QStringLiteral(":name"), name);
    groupQuery.bindValue(QStringLiteral(":ownerId"), owner->id());
    groupQuery.bindValue(QStringLiteral(":conversationId"), conversationId);
    groupQuery.bindValue(QStringLiteral(":uuid"), entry.recordUuid());
    if (!groupQuery.exec()) {
        m_lastError = groupQuery.lastError().text();
        return false;
    }
    const qint64 groupId = groupQuery.lastInsertId().toLongLong();

    for (const QJsonValue &value : memberUuids) {
        const auto member = users.findByUuid(value.toString());
        if (!member.has_value()) {
            // Membre pas encore connu localement : on ne bloque pas la
            // creation du groupe pour autant, il rejoindra via un futur
            // sync_batch GroupMembers (applyGroupMemberEntry est idempotent).
            continue;
        }
        QSqlQuery memberQuery(m_db);
        memberQuery.prepare(QStringLiteral(
            "INSERT OR IGNORE INTO GroupMembers (group_id, user_id) VALUES (:groupId, :userId)"));
        memberQuery.bindValue(QStringLiteral(":groupId"), groupId);
        memberQuery.bindValue(QStringLiteral(":userId"), member->id());
        if (!memberQuery.exec()) {
            m_lastError = memberQuery.lastError().text();
            return false;
        }
    }
    return true;
}

bool SyncLogRepository::applyGroupMemberEntry(const models::SyncLogEntry &entry)
{
    const QJsonDocument doc = QJsonDocument::fromJson(entry.payloadJson().toUtf8());
    if (!doc.isObject()) {
        m_lastError = QStringLiteral("Payload GroupMembers invalide");
        return false;
    }
    const QJsonObject obj = doc.object();
    const QString groupUuid = obj.value(QStringLiteral("groupUuid")).toString();
    const QString memberUuid = obj.value(QStringLiteral("memberUuid")).toString();

    QSqlQuery groupIdQuery(m_db);
    groupIdQuery.prepare(QStringLiteral("SELECT id FROM Groups WHERE uuid = :uuid"));
    groupIdQuery.bindValue(QStringLiteral(":uuid"), groupUuid);
    if (!groupIdQuery.exec() || !groupIdQuery.next()) {
        // Le groupe n'est pas encore connu localement : on differe, un
        // sync_batch ulterieur (contenant l'entree Groups correspondante)
        // permettra de rejouer celle-ci.
        m_lastError = QStringLiteral("Groupe inconnu (uuid=%1), membre differe").arg(groupUuid);
        qWarning() << "SyncLogRepository::applyGroupMemberEntry: groupe inconnu (uuid=" << groupUuid << "), membre differe pour prochaine reconciliation";
        return false;
    }
    const qint64 groupId = groupIdQuery.value(0).toLongLong();

    UserRepository users(m_db);
    const auto member = users.findByUuid(memberUuid);
    if (!member.has_value()) {
        m_lastError = QStringLiteral("Membre inconnu (uuid=%1), entree differee").arg(memberUuid);
        qWarning() << "SyncLogRepository::applyGroupMemberEntry: membre inconnu (uuid=" << memberUuid << "), entree differee pour prochaine reconciliation";
        return false;
    }
    const qint64 memberId = member->id();

    if (entry.operation() == models::SyncOperation::Delete) {
        QSqlQuery query(m_db);
        query.prepare(QStringLiteral("DELETE FROM GroupMembers WHERE group_id = :groupId AND user_id = :userId"));
        query.bindValue(QStringLiteral(":groupId"), groupId);
        query.bindValue(QStringLiteral(":userId"), memberId);
        if (!query.exec()) {
            m_lastError = query.lastError().text();
            return false;
        }
        return true;
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT OR IGNORE INTO GroupMembers (group_id, user_id) VALUES (:groupId, :userId)"));
    query.bindValue(QStringLiteral(":groupId"), groupId);
    query.bindValue(QStringLiteral(":userId"), memberId);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool SyncLogRepository::applyUserEntry(const models::SyncLogEntry &entry)
{
    // Cf. la note de reconciliation Users : contrairement a Messages/Groups
    // (INSERT OR IGNORE, "premier arrive premier servi"), Users a besoin d'un
    // vrai LWW car un role ou un mot de passe modifie pendant la panne doit
    // pouvoir ecraser (ou etre ecrase par) une modif faite cote SERVER officiel
    // entre-temps. LWW ligne entiere en v1 (limite connue documentee : une
    // edition concurrente de deux champs differents sur le meme compte peut
    // faire perdre silencieusement l'un des deux changements).
    UserRepository users(m_db);

    // Garde-fou : le reseau ne doit jamais pouvoir laisser ce poste sans aucun administrateur.
    const auto adminCount = [&users]() {
        int count = 0;
        for (const auto &u : users.findAll())
            if (u.isAdmin()) ++count;
        return count;
    };

    if (entry.operation() == models::SyncOperation::Delete) {
        const auto existing = users.findByUuid(entry.recordUuid());
        if (!existing) {
            return true; // deja absent localement : idempotent
        }
        if (existing->isAdmin() && adminCount() <= 1) {
            m_lastError = QStringLiteral("Suppression refusee : dernier compte administrateur");
            return false;
        }
        if (!users.remove(existing->id())) {
            m_lastError = users.lastError();
            return false;
        }
        return true;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(entry.payloadJson().toUtf8());
    if (!doc.isObject()) {
        m_lastError = QStringLiteral("Payload Users invalide");
        return false;
    }
    const QJsonObject obj = doc.object();

    const QString name = obj.value(QStringLiteral("name")).toString();
    const QString ipAddress = obj.value(QStringLiteral("ipAddress")).toString();
    const models::UserStatus status = models::userStatusFromString(obj.value(QStringLiteral("status")).toString());
    // Role absent ou illisible : jamais de retrogradation implicite (cf. Update ci-dessous).
    const auto parsedRole = models::stringToUserRole(obj.value(QStringLiteral("role")).toString());
    const models::UserRole role = parsedRole.value_or(models::UserRole::User);
    const QString passwordHash = obj.value(QStringLiteral("passwordHash")).toString();
    const QString passwordSalt = obj.value(QStringLiteral("passwordSalt")).toString();
    QDateTime payloadUpdatedAt = QDateTime::fromString(
        obj.value(QStringLiteral("updatedAt")).toString(), Qt::ISODate);
    // Une date dans le futur gagnerait toutes les reconciliations "dernier ecrit gagne" a venir :
    // au-dela d'une petite tolerance d'horloge, on la ramene a maintenant.
    const QDateTime nowUtc = QDateTime::currentDateTimeUtc();
    if (payloadUpdatedAt.isValid() && payloadUpdatedAt > nowUtc.addSecs(300))
        payloadUpdatedAt = nowUtc;

    const auto existing = users.findByUuid(entry.recordUuid());

    if (entry.operation() == models::SyncOperation::Insert) {
        if (existing) {
            return true; // deja connu (rejeu d'un sync_batch) : idempotent
        }

        QString finalName = name;
        if (users.existsByName(finalName)) {
            // Collision de login : deux comptes crees sous le meme nom pendant
            // la panne (typiquement TEMP_SERVER et SERVER officiel via un acces
            // admin des deux cotes). On renomme automatiquement pour ne pas
            // bloquer la reconciliation, et on journalise pour arbitrage manuel.
            finalName = QStringLiteral("%1*conflict*%2").arg(name, entry.recordUuid().left(8));

            QSqlQuery logQuery(m_db);
            logQuery.prepare(QStringLiteral(
                "INSERT INTO ServerElectionLog (event, epoch, machine_uuid) "
                "VALUES (:event, :epoch, :machine)"));
            logQuery.bindValue(QStringLiteral(":event"), QStringLiteral("USER_NAME_CONFLICT"));
            logQuery.bindValue(QStringLiteral(":epoch"), entry.epoch());
            logQuery.bindValue(QStringLiteral(":machine"), entry.originMachineId());
            if (!logQuery.exec()) {
                // Non bloquant : le compte est tout de meme cree, seule la
                // trace d'audit manque pour signaler l'arbitrage a l'admin.
                m_lastError = logQuery.lastError().text();
            }
        }

        models::User user;
        user.setUuid(entry.recordUuid());
        user.setName(finalName);
        user.setIpAddress(ipAddress);
        user.setStatus(status);
        user.setRole(role);
        user.setPasswordHash(passwordHash);
        user.setPasswordSalt(passwordSalt);
        user.setUpdatedAt(payloadUpdatedAt.isValid() ? payloadUpdatedAt : QDateTime::currentDateTimeUtc());

        if (users.create(user) < 0) {
            m_lastError = users.lastError();
            return false;
        }
        return true;
    }

    if (entry.operation() == models::SyncOperation::Update) {
        if (!existing) {
            // UPDATE recu avant l'INSERT correspondant (ordre lamport pas
            // garanti en cas de batch partiel) -> traiter comme un INSERT.
            models::SyncLogEntry asInsert = entry;
            asInsert.setOperation(models::SyncOperation::Insert);
            return applyUserEntry(asInsert);
        }

        if (!payloadUpdatedAt.isValid() || payloadUpdatedAt <= existing->updatedAt()) {
            // Notre version locale est plus recente ou egale : on garde la
            // notre (LWW). Le retour reste "true" : l'entree est bien traitee,
            // simplement sans effet applicatif.
            return true;
        }

        models::User updated = *existing;
        updated.setName(name.isEmpty() ? existing->name() : name);
        updated.setIpAddress(ipAddress);
        updated.setStatus(status);
        models::UserRole newRole = parsedRole.value_or(existing->role());
        if (existing->isAdmin() && newRole != models::UserRole::Admin && adminCount() <= 1)
            newRole = models::UserRole::Admin; // dernier administrateur : jamais retrograde
        updated.setRole(newRole);
        updated.setPasswordHash(passwordHash.isEmpty() ? existing->passwordHash() : passwordHash);
        updated.setPasswordSalt(passwordSalt.isEmpty() ? existing->passwordSalt() : passwordSalt);
        updated.setUpdatedAt(payloadUpdatedAt);

        if (!users.update(updated)) {
            m_lastError = users.lastError();
            return false;
        }
        return true;
    }

    // Operation inconnue : on ne bloque pas la fusion du journal lui-meme.
    return true;
}

QString SyncLogRepository::lastError() const
{
    return m_lastError;
}

} // namespace database