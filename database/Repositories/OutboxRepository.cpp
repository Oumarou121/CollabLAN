#include "OutboxRepository.h"

#include <QJsonDocument>
#include <QSqlError>
#include <QSqlQuery>
#include <QUuid>
#include <QDebug>

namespace database {

OutboxRepository::OutboxRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

QString OutboxRepository::enqueue(const QString &userUuid, QJsonObject payload, bool requiresOfficial)
{
    const QString changeId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    payload.insert(QStringLiteral("changeId"), changeId);

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO Outbox (change_id, user_uuid, payload_json, requires_official) VALUES (:id, :user, :payload, :official)"));
    query.bindValue(QStringLiteral(":id"), changeId);
    query.bindValue(QStringLiteral(":user"), userUuid);
    query.bindValue(QStringLiteral(":payload"), QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
    query.bindValue(QStringLiteral(":official"), requiresOfficial ? 1 : 0);
    if (!query.exec()) {
        qWarning() << "OutboxRepository::enqueue:" << query.lastError().text();
        return QString();
    }
    return changeId;
}

QVector<OutboxChange> OutboxRepository::pending(const QString &userUuid) const
{
    QVector<OutboxChange> changes;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT change_id, user_uuid, payload_json, requires_official FROM Outbox "
        "WHERE :user = '' OR user_uuid = :user ORDER BY id ASC"));
    query.bindValue(QStringLiteral(":user"), userUuid);
    if (!query.exec()) {
        qWarning() << "OutboxRepository::pending:" << query.lastError().text();
        return changes;
    }
    while (query.next()) {
        changes.append({query.value(0).toString(), query.value(1).toString(),
                        QJsonDocument::fromJson(query.value(2).toString().toUtf8()).object(),
                        query.value(3).toInt() != 0});
    }
    return changes;
}

bool OutboxRepository::remove(const QString &changeId)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM Outbox WHERE change_id = :id"));
    query.bindValue(QStringLiteral(":id"), changeId);
    return query.exec() && query.numRowsAffected() > 0;
}

int OutboxRepository::count() const
{
    QSqlQuery query(m_db);
    return query.exec(QStringLiteral("SELECT COUNT(*) FROM Outbox")) && query.next() ? query.value(0).toInt() : 0;
}

} // namespace database
