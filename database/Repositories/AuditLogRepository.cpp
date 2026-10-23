#include "AuditLogRepository.h"

#include "DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlRecord>
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
        "INSERT INTO AuditLogs (event_uuid, event_type, description, user_id, actor_label, created_at) "
        "VALUES (:eventUuid, :eventType, :description, :userId, :actorLabel, :createdAt)"
    ));
    query.bindValue(QStringLiteral(":eventUuid"), entry.eventUuid());
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
    // Enregistrement lu une fois par ligne : value(nom) le reconstruisait a chaque colonne.
    const QSqlRecord rec = query.record();
    models::AuditLog entry;
    entry.setId(query.value(rec.indexOf(QLatin1String("id"))).toLongLong());
    entry.setEventUuid(query.value(rec.indexOf(QLatin1String("event_uuid"))).toString());
    entry.setEventType(query.value(rec.indexOf(QLatin1String("event_type"))).toString());
    entry.setDescription(query.value(rec.indexOf(QLatin1String("description"))).toString());

    const QVariant userIdValue = query.value(rec.indexOf(QLatin1String("user_id")));
    if (userIdValue.isValid() && !userIdValue.isNull()) {
        entry.setUserId(userIdValue.toLongLong());
    } else {
        entry.setUserId(std::nullopt);
    }

    entry.setActorLabel(query.value(rec.indexOf(QLatin1String("actor_label"))).toString());

    QDateTime timestamp = QDateTime::fromString(query.value(rec.indexOf(QLatin1String("created_at"))).toString(), Qt::ISODateWithMs);
    if (!timestamp.isValid()) {
        // Compatibilite avec les entrees ecrites via datetime('now') par
        // SQLite (format "yyyy-MM-dd HH:mm:ss", sans le 'T' ISO).
        timestamp = QDateTime::fromString(query.value(rec.indexOf(QLatin1String("created_at"))).toString(),
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

    QString sql = QStringLiteral("SELECT id, event_uuid, event_type, description, user_id, actor_label, created_at FROM AuditLogs");
    if (!conditions.isEmpty()) {
        sql += QStringLiteral(" WHERE ") + conditions.join(QStringLiteral(" AND "));
    }
    // LIMIT/OFFSET sont interpoles directement plutot que lies via des
    // placeholders nommes (:limit/:offset) : le driver QSQLITE de Qt
    // decompte parfois mal le nombre de parametres attendus quand des
    // placeholders nommes suivent LIMIT/OFFSET, d'ou l'erreur "Parameter
    // count mismatch" observee malgre un nombre de bindValue() corrects
    // (issue #63bis). Sans risque d'injection ici : filter.limit/offset
    // sont de simples int, jamais des chaines fournies par l'UI.
    sql += QStringLiteral(" ORDER BY created_at DESC, id DESC LIMIT %1 OFFSET %2")
               .arg(filter.limit)
               .arg(filter.offset);

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
        "SELECT id, event_uuid, event_type, description, user_id, actor_label, created_at "
        "FROM AuditLogs WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec() || !query.next()) {
        return std::nullopt;
    }
    return fromRecord(query);
}

std::optional<models::AuditLog> AuditLogRepository::getByEventUuid(const QString &eventUuid)
{
    if (!m_dbManager || eventUuid.isEmpty()) return std::nullopt;
    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral(
        "SELECT id, event_uuid, event_type, description, user_id, actor_label, created_at "
        "FROM AuditLogs WHERE event_uuid = :eventUuid"));
    query.bindValue(QStringLiteral(":eventUuid"), eventUuid);
    if (!query.exec() || !query.next()) return std::nullopt;
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
