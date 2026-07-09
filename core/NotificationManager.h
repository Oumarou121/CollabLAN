#ifndef CORE_NOTIFICATIONMANAGER_H
#define CORE_NOTIFICATIONMANAGER_H

#include <QObject>
#include <QString>

#include "models/Message.h"

namespace core {

/**
 * @brief Generation et distribution des notifications internes.
 *
 * Detecte les evenements (nouveau message) et declenche les notifications.
 */
class NotificationManager : public QObject
{
    Q_OBJECT

public:
    explicit NotificationManager(QObject *parent = nullptr);
    ~NotificationManager() override;

    /// Active ou desactive les notifications.
    void setNotificationsEnabled(bool enabled) { m_notificationsEnabled = enabled; }
    bool notificationsEnabled() const { return m_notificationsEnabled; }

public slots:
    /// Appelé lorsqu'un nouveau message est reçu.
    void onMessageReceived(const models::Message &message);

signals:
    /// Emis lorsqu'une notification doit être affichée.
    void notificationRequested(const QString &title, const QString &message);

private:
    bool m_notificationsEnabled = true;
};

} // namespace core

#endif // CORE_NOTIFICATIONMANAGER_H
