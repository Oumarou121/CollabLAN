#ifndef CORE_NOTIFICATIONMANAGER_H
#define CORE_NOTIFICATIONMANAGER_H

#include <QObject>
#include <QString>

#include "models/Message.h"
#include "models/Group.h"

namespace core {

class UserManager;

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

    /// Permet de resoudre le nom de l'expediteur d'un message pour
    /// enrichir la notification (cf. onMessageReceived). Optionnel : si
    /// jamais renseigne, le titre generique "Nouveau message" reste
    /// utilise comme avant (comportement inchange en son absence).
    void setUserManager(UserManager *userManager) { m_userManager = userManager; }

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

    /// Appelé lorsqu'une rafale de fichiers reçus pour un dossier partagé
    /// vient de se terminer (regroupement fait par FolderSyncService, cf.
    /// FolderSyncService::folderFilesReceived) : une SEULE notification est
    /// affichée pour tout le lot, au lieu d'une par fichier transféré
    /// (TransferService::transferCompleted en émet un par fichier).
    /// localPath (peut être vide si le dossier est introuvable au moment de
    /// l'appel) est inclus dans le message pour couvrir aussi le cas du
    /// tout premier provisionnement automatique (chemin local par défaut
    /// assigné sous ~/LocaLink/Dossiers partagés/, cf.
    /// core::SharedFolderManager::provisionDefaultLocalPath()) : plutôt
    /// qu'une notification séparée "la synchronisation démarre dans X" puis
    /// une seconde "N fichiers reçus" quelques secondes après, un seul
    /// message donne à la fois le compte ET l'emplacement une fois la
    /// rafale terminée.
    void onFolderFilesReceived(const QString &folderUuid, const QString &folderName,
                                int fileCount, const QString &localPath);

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
    void notificationRequested(const QString &title, const QString &message, const QString &category,
                               qint64 conversationId = 0);

private:
    bool m_notificationsEnabled = true;
    UserManager *m_userManager = nullptr;
};

} // namespace core

#endif // CORE_NOTIFICATIONMANAGER_H