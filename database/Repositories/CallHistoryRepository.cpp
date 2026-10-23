#include "CallHistoryRepository.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QVariant>

namespace database {

namespace {

QVariant dateTimeToVariant(const QDateTime &dt)
{
    if (!dt.isValid())
        return QVariant(QMetaType(QMetaType::QString));
    return dt.toUTC().toString(Qt::ISODateWithMs);
}

QDateTime variantToDateTime(const QVariant &value)
{
    if (!value.isValid() || value.isNull())
        return QDateTime();
    QDateTime dt = QDateTime::fromString(value.toString(), Qt::ISODateWithMs);
    if (!dt.isValid()) {
        // Compatibilite avec datetime('now') de SQLite (sans le 'T' ISO).
        dt = QDateTime::fromString(value.toString(), QStringLiteral("yyyy-MM-dd HH:mm:ss"));
        dt.setTimeSpec(Qt::UTC);
    }
    return dt;
}
}

CallHistoryRepository::CallHistoryRepository(QSqlDatabase database)
    : m_db(database)
{
}

CallHistoryRepository::~CallHistoryRepository() = default;

int CallHistoryRepository::create(const models::CallHistoryEntry &entry)
{
    if (!m_db.isOpen()) {
        m_lastError = QStringLiteral("Base de donnees non ouverte");
        return -1;
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO CallHistory (call_uuid, local_user_id, direction, peer_address, peer_name, "
        "status, started_at) "
        "VALUES (:callUuid, :localUserId, :direction, :peerAddress, :peerName, :status, :startedAt)"));

    query.bindValue(QStringLiteral(":callUuid"),
                     entry.callUuid().isNull() ? QString(QLatin1String("")) : entry.callUuid());
    if (entry.localUserId() > 0) {
        query.bindValue(QStringLiteral(":localUserId"), entry.localUserId());
    } else {
        query.bindValue(QStringLiteral(":localUserId"), QVariant(QMetaType(QMetaType::Int)));
    }
    query.bindValue(QStringLiteral(":direction"), models::callDirectionToString(entry.direction()));
    query.bindValue(QStringLiteral(":peerAddress"), entry.peerAddress());
    query.bindValue(QStringLiteral(":peerName"),
                     entry.peerName().isEmpty() ? QVariant(QMetaType(QMetaType::QString)) : entry.peerName());
    query.bindValue(QStringLiteral(":status"), models::callStatusToString(entry.status()));
    const QDateTime startedAt = entry.startedAt().isValid() ? entry.startedAt() : QDateTime::currentDateTimeUtc();
    query.bindValue(QStringLiteral(":startedAt"), dateTimeToVariant(startedAt));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return -1;
    }

    return query.lastInsertId().toInt();
}

models::CallHistoryEntry CallHistoryRepository::entryFromQuery(const QSqlQuery &query) const
{
    // Enregistrement lu une fois par ligne : value(nom) le reconstruisait a chaque colonne.
    const QSqlRecord rec = query.record();
    models::CallHistoryEntry entry;
    entry.setId(query.value(rec.indexOf(QLatin1String("id"))).toInt());
    entry.setCallUuid(query.value(rec.indexOf(QLatin1String("call_uuid"))).toString());

    const QVariant localUserIdValue = query.value(rec.indexOf(QLatin1String("local_user_id")));
    entry.setLocalUserId(localUserIdValue.isValid() && !localUserIdValue.isNull()
                              ? localUserIdValue.toInt() : -1);

    entry.setDirection(models::callDirectionFromString(query.value(rec.indexOf(QLatin1String("direction"))).toString()));
    entry.setPeerAddress(query.value(rec.indexOf(QLatin1String("peer_address"))).toString());
    entry.setPeerName(query.value(rec.indexOf(QLatin1String("peer_name"))).toString());
    entry.setStatus(models::callStatusFromString(query.value(rec.indexOf(QLatin1String("status"))).toString()));
    entry.setStartedAt(variantToDateTime(query.value(rec.indexOf(QLatin1String("started_at")))));
    entry.setConnectedAt(variantToDateTime(query.value(rec.indexOf(QLatin1String("connected_at")))));
    entry.setEndedAt(variantToDateTime(query.value(rec.indexOf(QLatin1String("ended_at")))));

    const QVariant durationValue = query.value(rec.indexOf(QLatin1String("duration_seconds")));
    entry.setDurationSeconds(durationValue.isValid() && !durationValue.isNull() ? durationValue.toInt() : -1);

    return entry;
}

std::optional<models::CallHistoryEntry> CallHistoryRepository::findById(int id) const
{
    if (!m_db.isOpen())
        return std::nullopt;

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT id, call_uuid, local_user_id, direction, peer_address, peer_name, status, "
        "started_at, connected_at, ended_at, duration_seconds FROM CallHistory WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec() || !query.next()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    return entryFromQuery(query);
}

std::vector<models::CallHistoryEntry> CallHistoryRepository::findAll(int limit, int offset) const
{
    std::vector<models::CallHistoryEntry> results;
    if (!m_db.isOpen())
        return results;

    QSqlQuery query(m_db);
    // LIMIT/OFFSET interpoles directement (entiers de code, jamais fournis
    // par l'UI) : voir la note equivalente dans AuditLogRepository::find(),
    // le driver QSQLITE decompte parfois mal les parametres nommes situes
    // apres LIMIT/OFFSET.
    query.prepare(QStringLiteral(
        "SELECT id, call_uuid, local_user_id, direction, peer_address, peer_name, status, "
        "started_at, connected_at, ended_at, duration_seconds FROM CallHistory "
        "ORDER BY started_at DESC, id DESC LIMIT %1 OFFSET %2").arg(limit).arg(offset));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return results;
    }
    while (query.next()) {
        results.push_back(entryFromQuery(query));
    }
    return results;
}

std::vector<models::CallHistoryEntry> CallHistoryRepository::findByUser(int userId, int limit, int offset) const
{
    std::vector<models::CallHistoryEntry> results;
    if (!m_db.isOpen())
        return results;

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT id, call_uuid, local_user_id, direction, peer_address, peer_name, status, "
        "started_at, connected_at, ended_at, duration_seconds FROM CallHistory "
        "WHERE local_user_id = :userId "
        "ORDER BY started_at DESC, id DESC LIMIT %1 OFFSET %2").arg(limit).arg(offset));
    query.bindValue(QStringLiteral(":userId"), userId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return results;
    }
    while (query.next()) {
        results.push_back(entryFromQuery(query));
    }
    return results;
}

bool CallHistoryRepository::markConnected(int id, const QDateTime &connectedAt)
{
    if (!m_db.isOpen())
        return false;

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("UPDATE CallHistory SET connected_at = :connectedAt WHERE id = :id"));
    query.bindValue(QStringLiteral(":connectedAt"), dateTimeToVariant(connectedAt));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool CallHistoryRepository::markEnded(int id, models::CallStatus status, const QDateTime &endedAt,
                                       std::optional<int> durationSeconds)
{
    if (!m_db.isOpen())
        return false;

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE CallHistory SET status = :status, ended_at = :endedAt, duration_seconds = :duration "
        "WHERE id = :id"));
    query.bindValue(QStringLiteral(":status"), models::callStatusToString(status));
    query.bindValue(QStringLiteral(":endedAt"), dateTimeToVariant(endedAt));
    if (durationSeconds.has_value()) {
        query.bindValue(QStringLiteral(":duration"), *durationSeconds);
    } else {
        query.bindValue(QStringLiteral(":duration"), QVariant(QMetaType(QMetaType::Int)));
    }
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool CallHistoryRepository::remove(int id)
{
    if (!m_db.isOpen())
        return false;

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM CallHistory WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

QString CallHistoryRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
