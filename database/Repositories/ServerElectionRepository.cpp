#include "ServerElectionRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>
#include <QDateTime>
#include <QUuid>

namespace database {

ServerElectionRepository::ServerElectionRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

ServerElectionRepository::~ServerElectionRepository() = default;

void ServerElectionRepository::ensureSingletonRow() const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT OR IGNORE INTO ServerElection (id, current_role, epoch, priority_weight) "
        "VALUES (1, 'CLIENT', 0, 100)"));
    if (!query.exec()) {
        m_lastError = query.lastError().text();
    }
}

models::ServerElection ServerElectionRepository::current() const
{
    ensureSingletonRow();

    models::ServerElection state;

    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT * FROM ServerElection WHERE id = 1"))) {
        m_lastError = query.lastError().text();
        return state;
    }
    if (!query.next()) {
        return state;
    }

    state.setCurrentRole(models::serverRoleFromString(query.value(QStringLiteral("current_role")).toString()));
    state.setEpoch(query.value(QStringLiteral("epoch")).toInt());
    state.setActiveServerIp(query.value(QStringLiteral("active_server_ip")).toString());
    state.setActiveServerUuid(query.value(QStringLiteral("active_server_uuid")).toString());
    state.setPriorityWeight(query.value(QStringLiteral("priority_weight")).toInt());

    const QString heartbeat = query.value(QStringLiteral("last_heartbeat_seen")).toString();
    if (!heartbeat.isEmpty()) {
        state.setLastHeartbeatSeen(QDateTime::fromString(heartbeat, Qt::ISODate));
    }

    return state;
}

bool ServerElectionRepository::save(const models::ServerElection &state)
{
    ensureSingletonRow();

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE ServerElection SET current_role = :role, epoch = :epoch, "
        "active_server_ip = :ip, active_server_uuid = :uuid, priority_weight = :weight, "
        "last_heartbeat_seen = :heartbeat WHERE id = 1"));
    query.bindValue(QStringLiteral(":role"), models::serverRoleToString(state.currentRole()));
    query.bindValue(QStringLiteral(":epoch"), state.epoch());
    query.bindValue(QStringLiteral(":ip"), state.activeServerIp());
    query.bindValue(QStringLiteral(":uuid"), state.activeServerUuid());
    query.bindValue(QStringLiteral(":weight"), state.priorityWeight());
    query.bindValue(QStringLiteral(":heartbeat"),
                     state.lastHeartbeatSeen().isValid()
                         ? state.lastHeartbeatSeen().toString(Qt::ISODate)
                         : QVariant(QVariant::String));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool ServerElectionRepository::updateRoleAndEpoch(models::ServerRole role, int epoch)
{
    ensureSingletonRow();

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE ServerElection SET current_role = :role, epoch = :epoch WHERE id = 1"));
    query.bindValue(QStringLiteral(":role"), models::serverRoleToString(role));
    query.bindValue(QStringLiteral(":epoch"), epoch);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool ServerElectionRepository::updateActiveServer(const QString &ip, const QString &uuid, const QDateTime &heartbeatSeenAt)
{
    ensureSingletonRow();

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE ServerElection SET active_server_ip = :ip, active_server_uuid = :uuid, "
        "last_heartbeat_seen = :heartbeat WHERE id = 1"));
    query.bindValue(QStringLiteral(":ip"), ip);
    query.bindValue(QStringLiteral(":uuid"), uuid);
    query.bindValue(QStringLiteral(":heartbeat"),
                     heartbeatSeenAt.isValid() ? heartbeatSeenAt.toString(Qt::ISODate) : QVariant(QVariant::String));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool ServerElectionRepository::updatePriorityWeight(int weight)
{
    ensureSingletonRow();

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("UPDATE ServerElection SET priority_weight = :weight WHERE id = 1"));
    query.bindValue(QStringLiteral(":weight"), weight);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool ServerElectionRepository::appendLogEntry(const QString &event, int epoch, const QString &machineUuid,
                                              QString *outLogUuid)
{
    const QString logUuid = QUuid::createUuid().toString(QUuid::WithoutBraces);

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO ServerElectionLog (event, epoch, machine_uuid, log_uuid) VALUES (:event, :epoch, :uuid, :logUuid)"));
    query.bindValue(QStringLiteral(":event"), event);
    query.bindValue(QStringLiteral(":epoch"), epoch);
    query.bindValue(QStringLiteral(":uuid"), machineUuid);
    query.bindValue(QStringLiteral(":logUuid"), logUuid);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    if (outLogUuid) {
        *outLogUuid = logUuid;
    }
    return true;
}

bool ServerElectionRepository::applyRemoteLogEntry(const models::ServerElectionLogEntry &entry)
{
    if (entry.logUuid().isEmpty()) {
        m_lastError = QStringLiteral("applyRemoteLogEntry: log_uuid manquant");
        return false;
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT OR IGNORE INTO ServerElectionLog (event, epoch, machine_uuid, log_uuid, created_at) "
        "VALUES (:event, :epoch, :uuid, :logUuid, :createdAt)"));
    query.bindValue(QStringLiteral(":event"), entry.event());
    query.bindValue(QStringLiteral(":epoch"), entry.epoch());
    query.bindValue(QStringLiteral(":uuid"), entry.machineUuid());
    query.bindValue(QStringLiteral(":logUuid"), entry.logUuid());
    query.bindValue(QStringLiteral(":createdAt"),
                     entry.createdAt().isValid()
                         ? entry.createdAt().toUTC().toString(Qt::ISODate)
                         : QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    // Meme si INSERT OR IGNORE n'a rien insere (entree deja connue), l'etat
    // est bien celui attendu par l'appelant : ce n'est pas une erreur.
    return true;
}

bool ServerElectionRepository::bumpEpochIfNewer(int remoteEpoch)
{
    ensureSingletonRow();

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE ServerElection SET epoch = :epoch WHERE id = 1 AND epoch < :epoch"));
    query.bindValue(QStringLiteral(":epoch"), remoteEpoch);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

models::ServerElectionLogEntry ServerElectionRepository::logEntryFromQuery(const QSqlQuery &query) const
{
    models::ServerElectionLogEntry entry;
    entry.setId(query.value(QStringLiteral("id")).toInt());
    entry.setEvent(query.value(QStringLiteral("event")).toString());
    entry.setEpoch(query.value(QStringLiteral("epoch")).toInt());
    entry.setMachineUuid(query.value(QStringLiteral("machine_uuid")).toString());
    entry.setCreatedAt(QDateTime::fromString(query.value(QStringLiteral("created_at")).toString(), Qt::ISODate));
    entry.setLogUuid(query.value(QStringLiteral("log_uuid")).toString());
    return entry;
}

std::vector<models::ServerElectionLogEntry> ServerElectionRepository::logHistory(int limit) const
{
    std::vector<models::ServerElectionLogEntry> entries;

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM ServerElectionLog ORDER BY created_at DESC, id DESC LIMIT :limit"));
    query.bindValue(QStringLiteral(":limit"), limit);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return entries;
    }
    while (query.next()) {
        entries.push_back(logEntryFromQuery(query));
    }
    return entries;
}

std::vector<models::ServerElectionLogEntry> ServerElectionRepository::entriesSinceEpoch(int fromEpoch) const
{
    std::vector<models::ServerElectionLogEntry> entries;

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM ServerElectionLog WHERE epoch >= :fromEpoch ORDER BY id ASC"));
    query.bindValue(QStringLiteral(":fromEpoch"), fromEpoch);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return entries;
    }
    while (query.next()) {
        entries.push_back(logEntryFromQuery(query));
    }
    return entries;
}

QString ServerElectionRepository::lastError() const
{
    return m_lastError;
}

} // namespace database