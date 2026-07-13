#ifndef CORE_NOTIFICATIONMANAGER_H
#define CORE_NOTIFICATIONMANAGER_H

#include <QObject>
#include <QString>

#include "models/Message.h"
#include "models/Group.h"

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

    /// Appelé lorsqu'un transfert de fichier se termine avec succes.
    void onTransferCompleted(const QString &transferKey, const QString &filePath);

    /// Appelé lorsqu'un transfert de fichier echoue.
    void onTransferFailed(const QString &transferKey, const QString &errorString);

    /// Appelé lorsqu'un poste du reseau local est detecte (connexion).
    void onPeerConnected(const QString &peerName);

    /// Appelé lorsqu'un poste du reseau local n'est plus joignable (deconnexion).
    void onPeerDisconnected(const QString &peerName);

    /// Appelé lorsqu'un groupe distant est recu (creation, cf.
    /// GroupManager::receiveGroupCreated). N'est PAS appele pour un groupe
    /// que l'on cree soi-meme (pas de notification pour sa propre action).
    void onGroupCreated(const models::Group &group);

    /// Appelé lorsqu'un dossier partagé est créé.
    void onFolderCreated(const QString &folderName, const QString &ownerName);

    /// Appelé lorsqu'un accès à un dossier partagé est révoqué.
    void onFolderAccessRevoked(const QString &folderName);

signals:
    /// Emis lorsqu'une notification doit être affichée (toast) et/ou
    /// sonorisee par l'UI. category identifie le type d'evenement
    /// ("message", "transfer", "connection", "disconnection") afin que
    /// le son joue coherent avec l'evenement (issue #58).
    void notificationRequested(const QString &title, const QString &message, const QString &category);

private:
    bool m_notificationsEnabled = true;
};

} // namespace core

#endif // CORE_NOTIFICATIONMANAGER_H