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
    qDebug() << "[NotificationManager] onMessageReceived called, enabled:" << m_notificationsEnabled;
    if (!m_notificationsEnabled) {
        qDebug() << "[NotificationManager] Notifications disabled, skipping";
        return;
    }

    // Generer une notification pour le nouveau message
    const QString title = QStringLiteral("Nouveau message");
    const QString notificationMessage = message.content();

    qDebug() << "[NotificationManager] Emitting notificationRequested for message:" << notificationMessage;
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

void NotificationManager::onGroupCreated(const models::Group &group)
{
    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Nouveau groupe");
    const QString message = QStringLiteral("Vous avez ete ajoute au groupe \"%1\"").arg(group.name());

    emit notificationRequested(title, message, QStringLiteral("group"));
}

void NotificationManager::onFolderCreated(const QString &folderName, const QString &ownerName)
{
    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Nouveau dossier partagé");
    const QString message = QStringLiteral("\"%1\" a partagé le dossier \"%2\" avec vous").arg(ownerName, folderName);

    emit notificationRequested(title, message, QStringLiteral("folder"));
}

} // namespace core