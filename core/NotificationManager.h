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

    /// Appelé lorsqu'un dossier partagé distant vient d'être provisionné
    /// automatiquement (chemin local par défaut assigné sous Documents/
    /// CollabLAN Shared Folders/, cf. core::SharedFolderManager::
    /// provisionDefaultLocalPath()) : la synchronisation démarre sans que
    /// l'utilisateur ait eu à choisir un dossier lui-même, donc on
    /// l'informe explicitement OÙ le contenu va apparaître sur son disque.
    void onFolderAutoProvisioned(const QString &folderName, const QString &localPath);

    /// Appelé lorsqu'une rafale de fichiers reçus pour un dossier partagé
    /// vient de se terminer (regroupement fait par FolderSyncService, cf.
    /// FolderSyncService::folderFilesReceived) : une SEULE notification est
    /// affichée pour tout le lot, au lieu d'une par fichier transféré
    /// (TransferService::transferCompleted en émet un par fichier).
    void onFolderFilesReceived(const QString &folderUuid, const QString &folderName, int fileCount);

    /// Notification groupée "N fichiers envoyés" pour une rafale de fichiers
    /// envoyés en réponse à des folder_file_request lors d'un partage de
    /// dossier (cf. FolderSyncService::folderFilesSent), symétrique de
    /// onFolderFilesReceived() côté destinataire, au lieu d'une notification
    /// par fichier (TransferService::transferCompleted en émet un par fichier
    /// côté expéditeur aussi).
    void onFolderFilesSent(const QString &folderUuid, const QString &folderName, int fileCount);

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