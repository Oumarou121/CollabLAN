#include "AuditLog.h"

namespace models {

AuditLog::AuditLog()
    : m_timestamp(QDateTime::currentDateTimeUtc())
{
}

AuditLog::AuditLog(const QString &eventType, const QString &description,
                   std::optional<qint64> userId, const QString &actorLabel)
    : m_eventType(eventType)
    , m_description(description)
    , m_userId(userId)
    , m_actorLabel(actorLabel)
    , m_timestamp(QDateTime::currentDateTimeUtc())
{
}

} // namespace models
