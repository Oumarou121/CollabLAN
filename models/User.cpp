#include "User.h"

namespace models {

User::User() = default;

User::User(int id,
           QString name,
           QString ipAddress,
           QString status,
           bool isAdmin,
           QString passwordHash,
           QDateTime createdAt)
    : m_id(id)
    , m_name(std::move(name))
    , m_ipAddress(std::move(ipAddress))
    , m_status(std::move(status))
    , m_isAdmin(isAdmin)
    , m_passwordHash(std::move(passwordHash))
    , m_createdAt(std::move(createdAt))
{
}

User::~User() = default;

int User::id() const
{
    return m_id;
}

void User::setId(int id)
{
    m_id = id;
}

QString User::name() const
{
    return m_name;
}

void User::setName(const QString &name)
{
    m_name = name;
}

QString User::ipAddress() const
{
    return m_ipAddress;
}

void User::setIpAddress(const QString &ipAddress)
{
    m_ipAddress = ipAddress;
}

QString User::status() const
{
    return m_status;
}

void User::setStatus(const QString &status)
{
    m_status = status;
}

bool User::isAdmin() const
{
    return m_isAdmin;
}

void User::setIsAdmin(bool isAdmin)
{
    m_isAdmin = isAdmin;
}

QString User::passwordHash() const
{
    return m_passwordHash;
}

void User::setPasswordHash(const QString &passwordHash)
{
    m_passwordHash = passwordHash;
}

QDateTime User::createdAt() const
{
    return m_createdAt;
}

void User::setCreatedAt(const QDateTime &createdAt)
{
    m_createdAt = createdAt;
}

} // namespace models
