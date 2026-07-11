#include "Notification.h"

namespace models {

Notification::Notification()
    : m_timestamp(QDateTime::currentDateTime())
{
}

Notification::Notification(const QString &title, const QString &message, NotificationType type)
    : m_title(title)
    , m_message(message)
    , m_type(type)
    , m_timestamp(QDateTime::currentDateTime())
{
}

int Notification::id() const
{
    return m_id;
}

void Notification::setId(int id)
{
    m_id = id;
}

QString Notification::title() const
{
    return m_title;
}

void Notification::setTitle(const QString &title)
{
    m_title = title;
}

QString Notification::message() const
{
    return m_message;
}

void Notification::setMessage(const QString &message)
{
    m_message = message;
}

NotificationType Notification::type() const
{
    return m_type;
}

void Notification::setType(NotificationType type)
{
    m_type = type;
}

QString Notification::category() const
{
    switch (m_type) {
    case NotificationType::Message:
        return QStringLiteral("message");
    case NotificationType::Transfer:
        return QStringLiteral("transfer");
    case NotificationType::Call:
        return QStringLiteral("call");
    case NotificationType::Connection:
        return QStringLiteral("connection");
    case NotificationType::Disconnection:
        return QStringLiteral("disconnection");
    case NotificationType::Error:
        return QStringLiteral("error");
    case NotificationType::Info:
        return QStringLiteral("info");
    }
    return QStringLiteral("info");
}

QDateTime Notification::timestamp() const
{
    return m_timestamp;
}

void Notification::setTimestamp(const QDateTime &timestamp)
{
    m_timestamp = timestamp;
}

bool Notification::isRead() const
{
    return m_isRead;
}

void Notification::setRead(bool read)
{
    m_isRead = read;
}

} // namespace models
