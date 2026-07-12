#include "NotificationService.h"

#include <QDebug>

namespace services {

NotificationService::NotificationService(QObject *parent)
    : QObject(parent)
{
}

NotificationService::~NotificationService()
{
}

void NotificationService::showNotification(const QString &title, const QString &message)
{
    qDebug() << "Notification:" << title << "-" << message;

    // Emettre le signal pour l'UI
    emit notificationAvailable(title, message);
}

} // namespace services
