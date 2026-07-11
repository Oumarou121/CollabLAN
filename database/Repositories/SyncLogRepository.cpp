#include "SyncLogRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>
#include <QDateTime>
#include <QUuid>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>

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
    models::SyncLogEntry entry;
    entry.setEntryUuid(query.value(QStringLiteral("entry_uuid")).toString());
    entry.setTableName(query.value(QStringLiteral("table_name")).toString());
    entry.setRecordUuid(query.value(QStringLiteral("record_uuid")).toString());
    entry.setOperation(query.value(QStringLiteral("operation")).toString());
    entry.setPayloadJson(query.value(QStringLiteral("payload_json")).toString());
    entry.setLamportClock(query.value(QStringLiteral("lamport_clock")).toLongLong());
    entry.setEpoch(query.value(QStringLiteral("epoch")).toInt());
    entry.setOriginMachineId(query.value(QStringLiteral("origin_machine_id")).toString());
    entry.setUpdatedAt(QDateTime::fromString(query.value(QStringLiteral("updated_at")).toString(), Qt::ISODate));
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

int SyncLogRepository::applyBatch(const std::vector<models::SyncLogEntry> &batch)
{
    int inserted = 0;
    for (const auto &entry : batch) {
        QSqlQuery check(m_db);
        check.prepare(QStringLiteral("SELECT 1 FROM SyncLog WHERE entry_uuid = :uuid"));
        check.bindValue(QStringLiteral(":uuid"), entry.entryUuid());
        if (!check.exec()) {
            m_lastError = check.lastError().text();
            continue;
        }
        if (check.next()) {
            continue; // deja connue : sync_batch idempotent, on ignore le doublon
        }
        if (append(entry)) {
            if (!applyDomainEntry(entry)) {
                continue;
            }
            ++inserted;
        }
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

    // Les tables non encore supportees restent au moins fusionnees dans SyncLog.
    return true;
}

bool SyncLogRepository::ensureConversation(qint64 conversationId, const QString &type, const QString &name)
{
    if (conversationId <= 0) {
        return true;
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT OR IGNORE INTO Conversations (id, type, name) VALUES (:id, :type, :name)"));
    query.bindValue(QStringLiteral(":id"), conversationId);
    query.bindValue(QStringLiteral(":type"), type.isEmpty() ? QStringLiteral("individual") : type);
    query.bindValue(QStringLiteral(":name"), name.isEmpty() ? QStringLiteral("Conversation") : name);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool SyncLogRepository::applyMessageEntry(const models::SyncLogEntry &entry)
{
    if (entry.operation() != models::SyncOperation::Insert) {
        return true;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(entry.payloadJson().toUtf8());
    if (!doc.isObject()) {
        m_lastError = QStringLiteral("Payload Messages invalide");
        return false;
    }
    const QJsonObject obj = doc.object();
    const qint64 id = obj.value(QStringLiteral("id")).toString(entry.recordUuid()).toLongLong();
    const qint64 conversationId = obj.value(QStringLiteral("conversationId")).toString().toLongLong();
    const qint64 senderId = obj.value(QStringLiteral("senderId")).toString().toLongLong();
    const QString content = obj.value(QStringLiteral("content")).toString();
    const QString timestamp = obj.value(QStringLiteral("timestamp")).toString(QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    const bool isRead = obj.value(QStringLiteral("isRead")).toBool(false);

    if (!ensureConversation(conversationId, QStringLiteral("individual"), QStringLiteral("Conversation"))) {
        return false;
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT OR IGNORE INTO Messages (id, conversationId, senderId, content, timestamp, is_read) "
        "VALUES (:id, :conversationId, :senderId, :content, :timestamp, :isRead)"));
    query.bindValue(QStringLiteral(":id"), id);
    query.bindValue(QStringLiteral(":conversationId"), conversationId);
    query.bindValue(QStringLiteral(":senderId"), senderId);
    query.bindValue(QStringLiteral(":content"), content);
    query.bindValue(QStringLiteral(":timestamp"), timestamp);
    query.bindValue(QStringLiteral(":isRead"), isRead ? 1 : 0);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool SyncLogRepository::applyGroupEntry(const models::SyncLogEntry &entry)
{
    if (entry.operation() != models::SyncOperation::Insert) {
        return true;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(entry.payloadJson().toUtf8());
    if (!doc.isObject()) {
        m_lastError = QStringLiteral("Payload Groups invalide");
        return false;
    }
    const QJsonObject obj = doc.object();
    const qint64 id = obj.value(QStringLiteral("id")).toString(entry.recordUuid()).toLongLong();
    const QString name = obj.value(QStringLiteral("name")).toString();
    const qint64 ownerId = obj.value(QStringLiteral("ownerId")).toString().toLongLong();
    const qint64 conversationId = obj.value(QStringLiteral("conversationId")).toString().toLongLong();

    if (!ensureConversation(conversationId, QStringLiteral("group"), name)) {
        return false;
    }

    QSqlQuery groupQuery(m_db);
    groupQuery.prepare(QStringLiteral(
        "INSERT OR IGNORE INTO Groups (id, name, owner_id, conversation_id) "
        "VALUES (:id, :name, :ownerId, :conversationId)"));
    groupQuery.bindValue(QStringLiteral(":id"), id);
    groupQuery.bindValue(QStringLiteral(":name"), name);
    groupQuery.bindValue(QStringLiteral(":ownerId"), ownerId);
    groupQuery.bindValue(QStringLiteral(":conversationId"), conversationId > 0 ? QVariant(conversationId) : QVariant(QVariant::LongLong));
    if (!groupQuery.exec()) {
        m_lastError = groupQuery.lastError().text();
        return false;
    }

    const QJsonArray members = obj.value(QStringLiteral("memberIds")).toArray();
    for (const QJsonValue &value : members) {
        QSqlQuery memberQuery(m_db);
        memberQuery.prepare(QStringLiteral(
            "INSERT OR IGNORE INTO GroupMembers (group_id, user_id) VALUES (:groupId, :userId)"));
        memberQuery.bindValue(QStringLiteral(":groupId"), id);
        memberQuery.bindValue(QStringLiteral(":userId"), value.toString().toLongLong());
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
    const qint64 groupId = obj.value(QStringLiteral("groupId")).toString().toLongLong();
    const qint64 memberId = obj.value(QStringLiteral("memberId")).toString().toLongLong();

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

    if (entry.operation() == models::SyncOperation::Delete) {
        const auto existing = users.findByUuid(entry.recordUuid());
        if (!existing) {
            return true; // deja absent localement : idempotent
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
    const models::UserRole role = models::stringToUserRole(obj.value(QStringLiteral("role")).toString())
                                       .value_or(models::UserRole::User);
    const QString passwordHash = obj.value(QStringLiteral("passwordHash")).toString();
    const QString passwordSalt = obj.value(QStringLiteral("passwordSalt")).toString();
    const QDateTime payloadUpdatedAt = QDateTime::fromString(
        obj.value(QStringLiteral("updatedAt")).toString(), Qt::ISODate);

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
        updated.setRole(role);
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