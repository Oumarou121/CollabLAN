#include "User.h"

namespace models {

QString userStatusToString(UserStatus status)
{
    switch (status) {
    case UserStatus::Online:
        return QStringLiteral("online");
    case UserStatus::Away:
        return QStringLiteral("away");
    case UserStatus::Offline:
    default:
        return QStringLiteral("offline");
    }
}

UserStatus userStatusFromString(const QString &value)
{
    const QString v = value.toLower();
    if (v == QStringLiteral("online")) {
        return UserStatus::Online;
    }
    if (v == QStringLiteral("away")) {
        return UserStatus::Away;
    }
    return UserStatus::Offline;
}

QString userRoleToString(UserRole role)
{
    switch (role) {
    case UserRole::Admin:
        return QStringLiteral("admin");
    case UserRole::User:
        return QStringLiteral("user");
    }
    return QStringLiteral("user");
}

std::optional<UserRole> stringToUserRole(const QString &str)
{
    const QString v = str.toLower();
    if (v == QStringLiteral("admin"))
        return UserRole::Admin;
    if (v == QStringLiteral("user"))
        return UserRole::User;
    return std::nullopt;
}

User::User()
    : m_createdAt(QDateTime::currentDateTimeUtc())
    , m_updatedAt(m_createdAt)
{
}

User::User(int id,
           QString name,
           QString ipAddress,
           UserStatus status,
           UserRole role,
           QString passwordHash,
           QString passwordSalt,
           QDateTime createdAt)
    : m_id(id)
    , m_name(std::move(name))
    , m_ipAddress(ipAddress.isNull() ? QStringLiteral("") : std::move(ipAddress))
    , m_status(status)
    , m_role(role)
    , m_passwordHash(passwordHash.isNull() ? QStringLiteral("") : std::move(passwordHash))
    , m_passwordSalt(passwordSalt.isNull() ? QStringLiteral("") : std::move(passwordSalt))
    , m_createdAt(std::move(createdAt))
    , m_updatedAt(m_createdAt)
{
}

User::~User() = default;

int User::id() const { return m_id; }
void User::setId(int id) { m_id = id; }

QString User::name() const { return m_name; }
void User::setName(const QString &name) { m_name = name; }

QString User::ipAddress() const { return m_ipAddress; }
void User::setIpAddress(const QString &ipAddress) { m_ipAddress = ipAddress.isNull() ? QStringLiteral("") : ipAddress; }

UserStatus User::status() const { return m_status; }
void User::setStatus(UserStatus status) { m_status = status; }

UserRole User::role() const { return m_role; }
void User::setRole(UserRole role) { m_role = role; }

bool User::isAdmin() const { return m_role == UserRole::Admin; }
void User::setIsAdmin(bool isAdmin) { m_role = isAdmin ? UserRole::Admin : UserRole::User; }

QString User::passwordHash() const { return m_passwordHash; }
void User::setPasswordHash(const QString &hash) { m_passwordHash = hash.isNull() ? QStringLiteral("") : hash; }

QString User::passwordSalt() const { return m_passwordSalt; }
void User::setPasswordSalt(const QString &salt) { m_passwordSalt = salt.isNull() ? QStringLiteral("") : salt; }

QDateTime User::createdAt() const { return m_createdAt; }
void User::setCreatedAt(const QDateTime &createdAt) { m_createdAt = createdAt; }

QString User::uuid() const { return m_uuid; }
void User::setUuid(const QString &uuid) { m_uuid = uuid; }

QDateTime User::updatedAt() const { return m_updatedAt; }
void User::setUpdatedAt(const QDateTime &updatedAt) { m_updatedAt = updatedAt; }

bool User::isValid() const
{
    return m_id >= 0 && !m_name.isEmpty();
}

} // namespace models
