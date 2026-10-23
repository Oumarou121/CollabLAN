#include "UserRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>
#include <QVariant>
#include <QUuid>
#include <QDateTime>

namespace database {

namespace {
// QString() (null) est liee comme SQL NULL par le driver Qt, ce qui viole
// les contraintes NOT NULL des colonnes texte. On normalise en chaine vide.
QString notNull(const QString &value)
{
    return value.isNull() ? QStringLiteral("") : value;
}
} // namespace

UserRepository::UserRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

UserRepository::~UserRepository() = default;

models::User UserRepository::userFromQuery(const QSqlQuery &query) const
{
    // Enregistrement lu une fois par ligne : value(nom) le reconstruisait a chaque colonne.
    const QSqlRecord rec = query.record();
    models::User user;
    user.setId(query.value(rec.indexOf(QLatin1String("id"))).toInt());
    user.setName(query.value(rec.indexOf(QLatin1String("name"))).toString());
    user.setIpAddress(query.value(rec.indexOf(QLatin1String("ip_address"))).toString());
    user.setStatus(models::userStatusFromString(query.value(rec.indexOf(QLatin1String("status"))).toString()));
    
    const QString roleStr = query.value(rec.indexOf(QLatin1String("role"))).toString();
    const auto role = models::stringToUserRole(roleStr);
    user.setRole(role.value_or(models::UserRole::User));
    
    user.setPasswordHash(query.value(rec.indexOf(QLatin1String("password_hash"))).toString());
    user.setPasswordSalt(query.value(rec.indexOf(QLatin1String("password_salt"))).toString());
    user.setCreatedAt(query.value(rec.indexOf(QLatin1String("created_at"))).toDateTime());
    user.setUuid(query.value(rec.indexOf(QLatin1String("uuid"))).toString());
    user.setUpdatedAt(QDateTime::fromString(query.value(rec.indexOf(QLatin1String("updated_at"))).toString(), Qt::ISODate));
    return user;
}

int UserRepository::create(const models::User &user)
{
    QSqlQuery query(m_db);
    const QString uuid = user.uuid().isEmpty() ? QUuid::createUuid().toString(QUuid::WithoutBraces) : user.uuid();
    const QString updatedAt = user.updatedAt().isValid()
        ? user.updatedAt().toUTC().toString(Qt::ISODate)
        : QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    query.prepare(QStringLiteral(
        "INSERT INTO Users (name, ip_address, status, role, password_hash, password_salt, uuid, updated_at) "
        "VALUES (:name, :ip_address, :status, :role, :password_hash, :password_salt, :uuid, :updated_at)"));
    query.bindValue(QStringLiteral(":name"), notNull(user.name()));
    query.bindValue(QStringLiteral(":ip_address"), notNull(user.ipAddress()));
    query.bindValue(QStringLiteral(":status"), models::userStatusToString(user.status()));
    query.bindValue(QStringLiteral(":role"), models::userRoleToString(user.role()));
    query.bindValue(QStringLiteral(":password_hash"), notNull(user.passwordHash()));
    query.bindValue(QStringLiteral(":password_salt"), notNull(user.passwordSalt()));
    query.bindValue(QStringLiteral(":uuid"), uuid);
    query.bindValue(QStringLiteral(":updated_at"), updatedAt);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return -1;
    }
    return query.lastInsertId().toInt();
}

std::optional<models::User> UserRepository::read(int id) const
{
    return findById(id);
}

bool UserRepository::update(const models::User &user)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE Users SET name = :name, ip_address = :ip_address, status = :status, "
        "role = :role, password_hash = :password_hash, password_salt = :password_salt, "
        "updated_at = :updated_at WHERE id = :id"));
    query.bindValue(QStringLiteral(":name"), notNull(user.name()));
    query.bindValue(QStringLiteral(":ip_address"), notNull(user.ipAddress()));
    query.bindValue(QStringLiteral(":status"), models::userStatusToString(user.status()));
    query.bindValue(QStringLiteral(":role"), models::userRoleToString(user.role()));
    query.bindValue(QStringLiteral(":password_hash"), notNull(user.passwordHash()));
    query.bindValue(QStringLiteral(":password_salt"), notNull(user.passwordSalt()));
    const QString updateTimestamp = user.updatedAt().isValid()
        ? user.updatedAt().toUTC().toString(Qt::ISODate)
        : QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    query.bindValue(QStringLiteral(":updated_at"), updateTimestamp);
    query.bindValue(QStringLiteral(":id"), user.id());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool UserRepository::remove(int id)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM Users WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

std::optional<models::User> UserRepository::findById(int id) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM Users WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return userFromQuery(query);
}

std::optional<models::User> UserRepository::findByName(const QString &name) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM Users WHERE name = :name"));
    query.bindValue(QStringLiteral(":name"), name);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return userFromQuery(query);
}


std::optional<models::User> UserRepository::findByUuid(const QString &uuid) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM Users WHERE uuid = :uuid"));
    query.bindValue(QStringLiteral(":uuid"), uuid);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return userFromQuery(query);
}
bool UserRepository::existsByName(const QString &name) const
{
    return findByName(name).has_value();
}

std::vector<models::User> UserRepository::findAll() const
{
    std::vector<models::User> users;

    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT * FROM Users ORDER BY name COLLATE NOCASE"))) {
        m_lastError = query.lastError().text();
        return users;
    }
    while (query.next()) {
        users.push_back(userFromQuery(query));
    }
    return users;
}

bool UserRepository::updateStatus(int id, models::UserStatus status)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("UPDATE Users SET status = :status, updated_at = :updated_at WHERE id = :id"));
    query.bindValue(QStringLiteral(":status"), models::userStatusToString(status));
    query.bindValue(QStringLiteral(":updated_at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

QString UserRepository::lastError() const
{
    return m_lastError;
}

} // namespace database