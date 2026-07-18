#include "UserSession.h"

namespace models {

UserSession::UserSession()
    : m_createdAt(QDateTime::currentDateTimeUtc())
{
}

UserSession::UserSession(int id,
                          int userId,
                          QString tokenHash,
                          QString deviceLabel,
                          QDateTime createdAt,
                          QDateTime expiresAt)
    : m_id(id)
    , m_userId(userId)
    , m_tokenHash(std::move(tokenHash))
    , m_deviceLabel(std::move(deviceLabel))
    , m_createdAt(std::move(createdAt))
    , m_expiresAt(std::move(expiresAt))
{
}

bool UserSession::isExpired() const
{
    return QDateTime::currentDateTimeUtc() >= m_expiresAt;
}

bool UserSession::isValid() const
{
    return m_id >= 0 && m_userId >= 0 && !m_tokenHash.isEmpty() && m_expiresAt.isValid();
}

} // namespace models
