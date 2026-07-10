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

    emit notificationRequested(title, notificationMessage, QStringLiteral("message"));
}

void NotificationManager::onTransferCompleted(const QString &transferKey, const QString &filePath)
{
    Q_UNUSED(transferKey);

    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Transfert termine");
    // filePath est le chemin complet ; seul le nom de fichier interesse
    // l'utilisateur dans la notification.
    const QString fileName = filePath.section(QLatin1Char('/'), -1).section(QLatin1Char('\\'), -1);

    emit notificationRequested(title, fileName, QStringLiteral("transfer"));
}

void NotificationManager::onTransferFailed(const QString &transferKey, const QString &errorString)
{
    Q_UNUSED(transferKey);

    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Echec du transfert");

    emit notificationRequested(title, errorString, QStringLiteral("transfer"));
}

void NotificationManager::onPeerConnected(const QString &peerName)
{
    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Poste connecte");

    emit notificationRequested(title, peerName, QStringLiteral("connection"));
}

void NotificationManager::onPeerDisconnected(const QString &peerName)
{
    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Poste deconnecte");

    emit notificationRequested(title, peerName, QStringLiteral("disconnection"));
}

} // namespace core
