#include "AuthorizedMachine.h"

namespace models {

AuthorizedMachine::AuthorizedMachine()
    : m_addedAt(QDateTime::currentDateTimeUtc())
{
}

AuthorizedMachine::AuthorizedMachine(int id,
                                     const QString &ipAddress,
                                     const QString &hostname,
                                     bool authorized,
                                     std::optional<int> addedBy,
                                     const QDateTime &addedAt,
                                     const QString &reason)
    : m_id(id)
    , m_ipAddress(ipAddress)
    , m_hostname(hostname)
    , m_authorized(authorized)
    , m_addedBy(addedBy)
    , m_addedAt(addedAt)
    , m_reason(reason)
{
}

bool AuthorizedMachine::isValid() const
{
    return m_id >= 0 && !m_ipAddress.isEmpty();
}

} // namespace models
