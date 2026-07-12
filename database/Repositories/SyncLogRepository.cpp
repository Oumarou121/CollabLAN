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

qint64 SyncLogRepository::ensureConversationByUuid(const QString &conversationUuid, const QString &type, const QString &name,
                                                     qint64 participant1Id, qint64 participant2Id)
{
    if (conversationUuid.isEmpty()) {
        return -1;
    }

    QSqlQuery findQuery(m_db);
    findQuery.prepare(QStringLiteral(
        "SELECT id, participant1_id, participant2_id FROM Conversations WHERE uuid = :uuid"));
    findQuery.bindValue(QStringLiteral(":uuid"), conversationUuid);
    if (!findQuery.exec()) {
        m_lastError = findQuery.lastError().text();
        return -1;
    }
    if (findQuery.next()) {
        const qint64 conversationId = findQuery.value(0).toLongLong();
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

bool SyncLogRepository::applyMessageEntry(const models::SyncLogEntry &entry)
{
    if (entry.operation() != models::SyncOperation::Insert) {
        return true;
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

    const qint64 conversationId = ensureConversationByUuid(conversationUuid, QStringLiteral("individual"), QStringLiteral("Conversation"),
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

bool SyncLogRepository::applyGroupEntry(const models::SyncLogEntry &entry)
{
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
        return false;
    }
    const qint64 groupId = groupIdQuery.value(0).toLongLong();

    UserRepository users(m_db);
    const auto member = users.findByUuid(memberUuid);
    if (!member.has_value()) {
        m_lastError = QStringLiteral("Membre inconnu (uuid=%1), entree differee").arg(memberUuid);
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