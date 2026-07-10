#include "SyncLogRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>
#include <QDateTime>
#include <QUuid>

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

QString SyncLogRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
