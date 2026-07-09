#include "UserRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>

namespace database {

namespace {
// QString() (null) est lie comme SQL NULL par le driver Qt, ce qui viole les
// contraintes NOT NULL des colonnes texte. On normalise donc en chaine vide.
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
    models::User user;
    user.setId(query.value(QStringLiteral("id")).toInt());
    user.setName(query.value(QStringLiteral("name")).toString());
    user.setIpAddress(query.value(QStringLiteral("ip_address")).toString());
    user.setStatus(models::userStatusFromString(query.value(QStringLiteral("status")).toString()));
    user.setIsAdmin(query.value(QStringLiteral("is_admin")).toInt() != 0);
    user.setPasswordHash(query.value(QStringLiteral("password_hash")).toString());
    user.setPasswordSalt(query.value(QStringLiteral("password_salt")).toString());
    user.setCreatedAt(query.value(QStringLiteral("created_at")).toDateTime());
    return user;
}

int UserRepository::create(const models::User &user)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO Users (name, ip_address, status, is_admin, password_hash, password_salt) "
        "VALUES (:name, :ip_address, :status, :is_admin, :password_hash, :password_salt)"));
    query.bindValue(QStringLiteral(":name"), user.name());
    query.bindValue(QStringLiteral(":ip_address"), notNull(user.ipAddress()));
    query.bindValue(QStringLiteral(":status"), models::userStatusToString(user.status()));
    query.bindValue(QStringLiteral(":is_admin"), user.isAdmin() ? 1 : 0);
    query.bindValue(QStringLiteral(":password_hash"), notNull(user.passwordHash()));
    query.bindValue(QStringLiteral(":password_salt"), notNull(user.passwordSalt()));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return -1;
    }

    return query.lastInsertId().toInt();
}

bool UserRepository::update(const models::User &user)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE Users SET name = :name, ip_address = :ip_address, status = :status, "
        "is_admin = :is_admin, password_hash = :password_hash, password_salt = :password_salt "
        "WHERE id = :id"));
    query.bindValue(QStringLiteral(":name"), user.name());
    query.bindValue(QStringLiteral(":ip_address"), notNull(user.ipAddress()));
    query.bindValue(QStringLiteral(":status"), models::userStatusToString(user.status()));
    query.bindValue(QStringLiteral(":is_admin"), user.isAdmin() ? 1 : 0);
    query.bindValue(QStringLiteral(":password_hash"), notNull(user.passwordHash()));
    query.bindValue(QStringLiteral(":password_salt"), notNull(user.passwordSalt()));
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
    query.prepare(QStringLiteral("UPDATE Users SET status = :status WHERE id = :id"));
    query.bindValue(QStringLiteral(":status"), models::userStatusToString(status));
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
