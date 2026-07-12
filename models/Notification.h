#ifndef MODELS_NOTIFICATION_H
#define MODELS_NOTIFICATION_H

#include <QString>
#include <QDateTime>

namespace models {

enum class NotificationType {
    Message,
    Transfer,
    Call,
    Connection,
    Disconnection,
    Error,
    Info
};

/**
 * @brief Represente une notification affichee a l'utilisateur.
 */
class Notification
{
public:
    Notification();
    explicit Notification(const QString &title, const QString &message, NotificationType type);

    int id() const;
    void setId(int id);

    QString title() const;
    void setTitle(const QString &title);

    QString message() const;
    void setMessage(const QString &message);

    NotificationType type() const;
    void setType(NotificationType type);

    QString category() const;

    QDateTime timestamp() const;
    void setTimestamp(const QDateTime &timestamp);

    bool isRead() const;
    void setRead(bool read);

private:
    int m_id = 0;
    QString m_title;
    QString m_message;
    NotificationType m_type = NotificationType::Info;
    QDateTime m_timestamp;
    bool m_isRead = false;
};

} // namespace models

#endif // MODELS_NOTIFICATION_H
