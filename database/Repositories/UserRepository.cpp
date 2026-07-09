#include "UserRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>

namespace database {

namespace {
constexpr const char *kSelectColumns =
    "id, name, ip_address, status, is_admin, password_hash, created_at";

models::User userFromQuery(const QSqlQuery &query)
{
    models::User user;
    user.setId(query.value(QStringLiteral("id")).toInt());
    user.setName(query.value(QStringLiteral("name")).toString());
    user.setIpAddress(query.value(QStringLiteral("ip_address")).toString());
    user.setStatus(query.value(QStringLiteral("status")).toString());
    user.setIsAdmin(query.value(QStringLiteral("is_admin")).toInt() != 0);
    user.setPasswordHash(query.value(QStringLiteral("password_hash")).toString());
    user.setCreatedAt(QDateTime::fromString(query.value(QStringLiteral("created_at")).toString(), Qt::ISODate));
    return user;
}
}

UserRepository::UserRepository(QSqlDatabase database)
    : m_database(std::move(database))
{
}

UserRepository::~UserRepository() = default;

std::optional<models::User> UserRepository::findOneWhere(const QString &whereClause, const QVariant &boundValue) const
{
    if (!m_database.isOpen()) {
        m_lastError = QStringLiteral("La base de donnees n'est pas ouverte.");
        return std::nullopt;
    }

    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("SELECT %1 FROM Users WHERE %2 LIMIT 1;")
                      .arg(QString::fromLatin1(kSelectColumns), whereClause));
    query.bindValue(0, boundValue);

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
    return findOneWhere(QStringLiteral("name = ?"), name);
}

std::optional<models::User> UserRepository::findById(int id) const
{
    return findOneWhere(QStringLiteral("id = ?"), id);
}

bool UserRepository::create(models::User &user)
{
    if (!m_database.isOpen()) {
        m_lastError = QStringLiteral("La base de donnees n'est pas ouverte.");
        return false;
    }

    QSqlQuery query(m_database);
    query.prepare(QStringLiteral(
        "INSERT INTO Users (name, ip_address, status, is_admin, password_hash) "
        "VALUES (:name, :ip_address, :status, :is_admin, :password_hash);"));
    query.bindValue(QStringLiteral(":name"), user.name());
    query.bindValue(QStringLiteral(":ip_address"), user.ipAddress());
    query.bindValue(QStringLiteral(":status"), user.status());
    query.bindValue(QStringLiteral(":is_admin"), user.isAdmin() ? 1 : 0);
    query.bindValue(QStringLiteral(":password_hash"), user.passwordHash());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }

    user.setId(query.lastInsertId().toInt());
    return true;
}

bool UserRepository::updateStatus(int userId, const QString &status)
{
    if (!m_database.isOpen()) {
        m_lastError = QStringLiteral("La base de donnees n'est pas ouverte.");
        return false;
    }

    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("UPDATE Users SET status = :status WHERE id = :id;"));
    query.bindValue(QStringLiteral(":status"), status);
    query.bindValue(QStringLiteral(":id"), userId);

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
