#include "SessionRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>
#include <QVariant>

namespace database {

SessionRepository::SessionRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

SessionRepository::~SessionRepository() = default;

models::UserSession SessionRepository::sessionFromQuery(const QSqlQuery &query) const
{
    // Enregistrement lu une fois par ligne : value(nom) le reconstruisait a chaque colonne.
    const QSqlRecord rec = query.record();
    models::UserSession session;
    session.setId(query.value(rec.indexOf(QLatin1String("id"))).toInt());
    session.setUserId(query.value(rec.indexOf(QLatin1String("user_id"))).toInt());
    session.setTokenHash(query.value(rec.indexOf(QLatin1String("token_hash"))).toString());
    session.setDeviceLabel(query.value(rec.indexOf(QLatin1String("device_label"))).toString());
    session.setCreatedAt(QDateTime::fromString(query.value(rec.indexOf(QLatin1String("created_at"))).toString(), Qt::ISODate));
    session.setExpiresAt(QDateTime::fromString(query.value(rec.indexOf(QLatin1String("expires_at"))).toString(), Qt::ISODate));
    return session;
}

int SessionRepository::create(int userId,
                               const QString &tokenHash,
                               const QDateTime &expiresAt,
                               const QString &deviceLabel)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO UserSessions (user_id, token_hash, device_label, expires_at) "
        "VALUES (:user_id, :token_hash, :device_label, :expires_at)"));
    query.bindValue(QStringLiteral(":user_id"), userId);
    query.bindValue(QStringLiteral(":token_hash"), tokenHash);
    query.bindValue(QStringLiteral(":device_label"),
                     deviceLabel.isEmpty() ? QVariant(QVariant::String) : QVariant(deviceLabel));
    query.bindValue(QStringLiteral(":expires_at"), expiresAt.toUTC().toString(Qt::ISODate));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return -1;
    }
    return query.lastInsertId().toInt();
}

std::optional<models::UserSession> SessionRepository::findByTokenHash(const QString &tokenHash) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM UserSessions WHERE token_hash = :token_hash"));
    query.bindValue(QStringLiteral(":token_hash"), tokenHash);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return sessionFromQuery(query);
}

bool SessionRepository::remove(int id)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM UserSessions WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool SessionRepository::removeByTokenHash(const QString &tokenHash)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM UserSessions WHERE token_hash = :token_hash"));
    query.bindValue(QStringLiteral(":token_hash"), tokenHash);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool SessionRepository::removeAllForUser(int userId)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM UserSessions WHERE user_id = :user_id"));
    query.bindValue(QStringLiteral(":user_id"), userId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

bool SessionRepository::removeExpired()
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM UserSessions WHERE expires_at <= :now"));
    query.bindValue(QStringLiteral(":now"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

QString SessionRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
