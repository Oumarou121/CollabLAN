#include "AuditLogRepository.h"

#include "DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QDebug>
#include <QStringList>
#include <QVariant>

namespace database {

namespace {
constexpr const char *kIsoFormat = "yyyy-MM-ddTHH:mm:ss.zzzZ";
}

AuditLogRepository::AuditLogRepository(DatabaseManager *dbManager)
    : m_dbManager(dbManager)
{
}

AuditLogRepository::~AuditLogRepository()
{
}

std::optional<models::AuditLog> AuditLogRepository::insert(const models::AuditLog &entry)
{
    if (!m_dbManager) {
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    query.prepare(QStringLiteral(
        "INSERT INTO AuditLogs (event_type, description, user_id, actor_label, created_at) "
        "VALUES (:eventType, :description, :userId, :actorLabel, :createdAt)"
    ));
    query.bindValue(QStringLiteral(":eventType"), entry.eventType());
    query.bindValue(QStringLiteral(":description"), entry.description());
    if (entry.userId().has_value()) {
        query.bindValue(QStringLiteral(":userId"), *entry.userId());
    } else {
        query.bindValue(QStringLiteral(":userId"), QVariant(QMetaType(QMetaType::LongLong)));
    }
    query.bindValue(QStringLiteral(":actorLabel"),
                     entry.actorLabel().isEmpty() ? QVariant(QMetaType(QMetaType::QString)) : entry.actorLabel());
    const QDateTime timestamp = entry.timestamp().isValid() ? entry.timestamp() : QDateTime::currentDateTimeUtc();
    query.bindValue(QStringLiteral(":createdAt"), timestamp.toUTC().toString(Qt::ISODateWithMs));

    if (!query.exec()) {
        qWarning() << "AuditLogRepository: echec insertion -" << query.lastError().text();
        return std::nullopt;
    }

    models::AuditLog inserted(entry);
    inserted.setId(query.lastInsertId().toLongLong());
    inserted.setTimestamp(timestamp);
    return inserted;
}

models::AuditLog AuditLogRepository::fromRecord(const QSqlQuery &query)
{
    models::AuditLog entry;
    entry.setId(query.value(QStringLiteral("id")).toLongLong());
    entry.setEventType(query.value(QStringLiteral("event_type")).toString());
    entry.setDescription(query.value(QStringLiteral("description")).toString());

    const QVariant userIdValue = query.value(QStringLiteral("user_id"));
    if (userIdValue.isValid() && !userIdValue.isNull()) {
        entry.setUserId(userIdValue.toLongLong());
    } else {
        entry.setUserId(std::nullopt);
    }

    entry.setActorLabel(query.value(QStringLiteral("actor_label")).toString());

    QDateTime timestamp = QDateTime::fromString(query.value(QStringLiteral("created_at")).toString(), Qt::ISODateWithMs);
    if (!timestamp.isValid()) {
        // Compatibilite avec les entrees ecrites via datetime('now') par
        // SQLite (format "yyyy-MM-dd HH:mm:ss", sans le 'T' ISO).
        timestamp = QDateTime::fromString(query.value(QStringLiteral("created_at")).toString(),
                                           QStringLiteral("yyyy-MM-dd HH:mm:ss"));
        timestamp.setTimeSpec(Qt::UTC);
    }
    entry.setTimestamp(timestamp);

    return entry;
}

QVector<models::AuditLog> AuditLogRepository::find(const AuditLogFilter &filter)
{
    QVector<models::AuditLog> results;
    if (!m_dbManager) {
        return results;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    QStringList conditions;
    if (filter.eventType.has_value()) {
        conditions << QStringLiteral("event_type = :eventType");
    }
    if (filter.userId.has_value()) {
        conditions << QStringLiteral("user_id = :userId");
    }
    if (filter.from.has_value()) {
        conditions << QStringLiteral("created_at >= :fromDate");
    }
    if (filter.to.has_value()) {
        conditions << QStringLiteral("created_at <= :toDate");
    }

    QString sql = QStringLiteral("SELECT id, event_type, description, user_id, actor_label, created_at FROM AuditLogs");
    if (!conditions.isEmpty()) {
        sql += QStringLiteral(" WHERE ") + conditions.join(QStringLiteral(" AND "));
    }
    sql += QStringLiteral(" ORDER BY created_at DESC, id DESC LIMIT :limit OFFSET :offset");

    query.prepare(sql);
    if (filter.eventType.has_value()) {
        query.bindValue(QStringLiteral(":eventType"), *filter.eventType);
    }
    if (filter.userId.has_value()) {
        query.bindValue(QStringLiteral(":userId"), *filter.userId);
    }
    if (filter.from.has_value()) {
        query.bindValue(QStringLiteral(":fromDate"), filter.from->toUTC().toString(Qt::ISODateWithMs));
    }
    if (filter.to.has_value()) {
        query.bindValue(QStringLiteral(":toDate"), filter.to->toUTC().toString(Qt::ISODateWithMs));
    }
    query.bindValue(QStringLiteral(":limit"), filter.limit);
    query.bindValue(QStringLiteral(":offset"), filter.offset);

    if (!query.exec()) {
        qWarning() << "AuditLogRepository: echec lecture filtree -" << query.lastError().text();
        return results;
    }

    while (query.next()) {
        results.append(fromRecord(query));
    }
    return results;
}

std::optional<models::AuditLog> AuditLogRepository::getById(qint64 id)
{
    if (!m_dbManager) {
        return std::nullopt;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT id, event_type, description, user_id, actor_label, created_at "
        "FROM AuditLogs WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec() || !query.next()) {
        return std::nullopt;
    }
    return fromRecord(query);
}

int AuditLogRepository::count(const AuditLogFilter &filter)
{
    if (!m_dbManager) {
        return 0;
    }

    QSqlDatabase db = m_dbManager->database();
    QSqlQuery query(db);

    QStringList conditions;
    if (filter.eventType.has_value()) {
        conditions << QStringLiteral("event_type = :eventType");
    }
    if (filter.userId.has_value()) {
        conditions << QStringLiteral("user_id = :userId");
    }
    if (filter.from.has_value()) {
        conditions << QStringLiteral("created_at >= :fromDate");
    }
    if (filter.to.has_value()) {
        conditions << QStringLiteral("created_at <= :toDate");
    }

    QString sql = QStringLiteral("SELECT COUNT(*) FROM AuditLogs");
    if (!conditions.isEmpty()) {
        sql += QStringLiteral(" WHERE ") + conditions.join(QStringLiteral(" AND "));
    }

    query.prepare(sql);
    if (filter.eventType.has_value()) {
        query.bindValue(QStringLiteral(":eventType"), *filter.eventType);
    }
    if (filter.userId.has_value()) {
        query.bindValue(QStringLiteral(":userId"), *filter.userId);
    }
    if (filter.from.has_value()) {
        query.bindValue(QStringLiteral(":fromDate"), filter.from->toUTC().toString(Qt::ISODateWithMs));
    }
    if (filter.to.has_value()) {
        query.bindValue(QStringLiteral(":toDate"), filter.to->toUTC().toString(Qt::ISODateWithMs));
    }

    if (!query.exec() || !query.next()) {
        return 0;
    }
    return query.value(0).toInt();
}

} // namespace database
