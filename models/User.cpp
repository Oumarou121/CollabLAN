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

User::User()
    : m_createdAt(QDateTime::currentDateTimeUtc())
{
}

User::User(int id,
           QString name,
           QString ipAddress,
           UserStatus status,
           bool isAdmin,
           QString passwordHash,
           QString passwordSalt,
           QDateTime createdAt)
    : m_id(id)
    , m_name(std::move(name))
    , m_ipAddress(std::move(ipAddress))
    , m_status(status)
    , m_isAdmin(isAdmin)
    , m_passwordHash(std::move(passwordHash))
    , m_passwordSalt(std::move(passwordSalt))
    , m_createdAt(std::move(createdAt))
{
}

User::~User() = default;

int User::id() const { return m_id; }
void User::setId(int id) { m_id = id; }

QString User::name() const { return m_name; }
void User::setName(const QString &name) { m_name = name; }

QString User::ipAddress() const { return m_ipAddress; }
void User::setIpAddress(const QString &ipAddress) { m_ipAddress = ipAddress; }

UserStatus User::status() const { return m_status; }
void User::setStatus(UserStatus status) { m_status = status; }

bool User::isAdmin() const { return m_isAdmin; }
void User::setIsAdmin(bool isAdmin) { m_isAdmin = isAdmin; }

QString User::passwordHash() const { return m_passwordHash; }
void User::setPasswordHash(const QString &hash) { m_passwordHash = hash; }

QString User::passwordSalt() const { return m_passwordSalt; }
void User::setPasswordSalt(const QString &salt) { m_passwordSalt = salt; }

QDateTime User::createdAt() const { return m_createdAt; }
void User::setCreatedAt(const QDateTime &createdAt) { m_createdAt = createdAt; }

bool User::isValid() const
{
    return m_id >= 0 && !m_name.isEmpty();
}

} // namespace models
