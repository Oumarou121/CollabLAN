#ifndef MODELS_AUTHORIZEDMACHINE_H
#define MODELS_AUTHORIZEDMACHINE_H

#include <QString>
#include <QDateTime>
#include <optional>
#include <QUuid>

namespace models {

/**
 * @brief Représente une machine autorisée ou révoquée dans le réseau CollabLAN (issue #68).
 */
class AuthorizedMachine
{
public:
    AuthorizedMachine();
    AuthorizedMachine(int id,
                     const QString &ipAddress,
                     const QString &hostname,
                     bool authorized,
                     std::optional<int> addedBy,
                     const QDateTime &addedAt = QDateTime::currentDateTimeUtc(),
                     const QString &reason = QString());

    int id() const { return m_id; }
    void setId(int id) { m_id = id; }

    QString uuid() const { return m_uuid; }
    void setUuid(const QString &uuid) { m_uuid = uuid; }

    QString ipAddress() const { return m_ipAddress; }
    void setIpAddress(const QString &ipAddress) { m_ipAddress = ipAddress; }

    QString hostname() const { return m_hostname; }
    void setHostname(const QString &hostname) { m_hostname = hostname; }

    bool isAuthorized() const { return m_authorized; }
    void setAuthorized(bool authorized) { m_authorized = authorized; }

    std::optional<int> addedBy() const { return m_addedBy; }
    void setAddedBy(std::optional<int> addedBy) { m_addedBy = addedBy; }

    QDateTime addedAt() const { return m_addedAt; }
    void setAddedAt(const QDateTime &addedAt) { m_addedAt = addedAt; }

    QString reason() const { return m_reason; }
    void setReason(const QString &reason) { m_reason = reason; }

    bool isValid() const;

private:
    int m_id = -1;
    QString m_uuid;
    QString m_ipAddress;
    QString m_hostname;
    bool m_authorized = true;
    std::optional<int> m_addedBy;
    QDateTime m_addedAt;
    QString m_reason;
};

} // namespace models

#endif // MODELS_AUTHORIZEDMACHINE_H
