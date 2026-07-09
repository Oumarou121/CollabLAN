#include "NotificationManager.h"

#include <QDebug>

namespace core {

NotificationManager::NotificationManager(QObject *parent)
    : QObject(parent)
{
}

NotificationManager::~NotificationManager()
{
}

void NotificationManager::onMessageReceived(const models::Message &message)
{
    if (!m_notificationsEnabled) {
        return;
    }

    // Generer une notification pour le nouveau message
    const QString title = QStringLiteral("Nouveau message");
    const QString notificationMessage = message.content();

    emit notificationRequested(title, notificationMessage);
}

} // namespace core
