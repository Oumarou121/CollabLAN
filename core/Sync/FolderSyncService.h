#ifndef CORE_SYNC_FOLDERSYNCSERVICE_H
#define CORE_SYNC_FOLDERSYNCSERVICE_H

#include <QObject>
#include <QString>
#include <QHostAddress>
#include <QVector>

#include "database/Repositories/SyncOperationRepository.h"
#include "models/FileSyncOperation.h"
#include "models/SharedFolder.h"
#include "models/SharedFile.h"

namespace network {
class MessagingServer;
class MessagingService;
class TransferService;
class DiscoveryService;
}

namespace core {
class SharedFolderManager;
}

namespace database {
class DatabaseManager;
}

namespace core::sync {

/**
 * @brief Diffusion réseau en temps réel des opérations de synchronisation
 *        de dossiers partagés (Releases 4–7 du cahier des charges).
 *
 * Release 4 — Protocole dédié
 *   Quatre types de messages JSON distincts des messages de chat/groupe :
 *     • "folder_op"            — diffusion d'un changement de fichier local
 *     • "folder_hello"         — annonce de connexion avec le dernier op_id connu
 *     • "folder_catchup_batch" — réponse serveur : opérations depuis last_op_id
 *     • "folder_file_request"  — demande de transfert d'un fichier précis
 *
 * Release 5/6 — Synchronisation temps réel
 *   Quand SyncEngine émet folderReindexed(folderId, count), ce service lit
 *   les nouvelles SyncOperations via SyncOperationRepository et les diffuse
 *   en broadcast (côté SERVER via MessagingServer) ou les envoie au serveur
 *   actif (côté CLIENT via MessagingService).
 *   Quand un pair reçoit un folder_op Create/Update pour un dossier qu'il
 *   possède localement avec une version inférieure, il envoie automatiquement
 *   un folder_file_request ; le pair qui détient le fichier le transfère via
 *   TransferService::sendFile().
 *
 * Release 7 — Récupération hors-ligne
 *   À chaque connexion au serveur, le CLIENT envoie folder_hello avec son
 *   dernier op_id connu (SyncOperationRepository::latestId()). Le SERVER
 *   répond avec toutes les opérations postérieures (folder_catchup_batch).
 *   Le CLIENT applique le batch et demande les fichiers manquants.
 *
 * Séparation des responsabilités : ce service ne touche jamais au réseau
 * vocal, à la messagerie textuelle ni à l'élection de serveur.
 */
class FolderSyncService : public QObject
{
    Q_OBJECT

public:
    explicit FolderSyncService(database::DatabaseManager *dbManager,
                                core::SharedFolderManager *folderManager,
                                QObject *parent = nullptr);
    ~FolderSyncService() override;

    /// Branche le MessagingServer local (écoute les messages entrants côté SERVER).
    void setMessagingServer(network::MessagingServer *server);

    /// Branche le MessagingService local (envoi côté CLIENT vers le SERVER actif).
    void setMessagingService(network::MessagingService *service);

    /// Nécessaire pour servir les folder_file_request reçus de pairs.
    void setTransferService(network::TransferService *transfer);

    /// Nécessaire pour résoudre l'adresse IP d'un pair à partir de son machineId.
    void setDiscoveryService(network::DiscoveryService *discovery);

    /// Identifiant local (DiscoveryService::localId()) inclus dans chaque message.
    void setLocalMachineId(const QString &machineId);

    /**
     * @brief Envoie un folder_file_request pour un fichier distant.
     *
     * Utile pour que l'Application déclenche manuellement la récupération
     * d'un fichier (ex. après catchupBatchReceived).
     */
    void requestRemoteFile(const QString &folderUuid, const QString &relativePath,
                           const QString &ownerMachineId);

signals:
    /**
     * @brief Émis quand un pair diffuse un folder_op.
     * L'Application peut l'utiliser pour mettre à jour l'UI, etc.
     * Pour Create/Update, FolderSyncService envoie automatiquement un
     * folder_file_request si le fichier est absent ou périmé localement.
     */
    void remoteOpReceived(const QString &folderUuid,
                          const QString &opType,
                          const QString &relativePath,
                          const QString &oldRelativePath,
                          const QString &machineId,
                          const QHostAddress &senderAddress,
                          quint16 senderTransferPort);

    /**
     * @brief Émis quand un folder_catchup_batch arrive (Release 7).
     * ops contient les opérations manquées depuis le dernier op_id connu.
     */
    void catchupBatchReceived(const QVector<models::FileSyncOperation> &ops);

public slots:
    /**
     * @brief À connecter sur SyncEngine::folderReindexed.
     * Lit les SyncOperations nouvellement insérées et les diffuse aux pairs.
     */
    void onLocalFolderReindexed(qint64 folderId, int changeCount);

    /**
     * @brief À connecter sur MessagingService::connected (Release 7).
     * Envoie un folder_hello avec le dernier op_id connu pour déclencher
     * la récupération des opérations manquées.
     */
    void onConnectedToServer();

private slots:
    void onServerMessageReceived(const QString &message, const QHostAddress &senderAddress);
    void onClientMessageReceived(const QString &message);

private:
    /// Diffuse un message JSON à tous les clients connectés (côté SERVER)
    /// ou l'envoie au serveur actif (côté CLIENT).
    void broadcastMessage(const QString &json);

    /// Envoie un message JSON uniquement vers le serveur actif (MessagingService).
    void sendMessageToServer(const QString &json);

    void handleFolderOp(const QJsonObject &obj, const QHostAddress &senderAddress);
    void handleFolderHello(const QJsonObject &obj);
    void handleFolderCatchupBatch(const QJsonObject &obj);
    void handleFolderFileRequest(const QJsonObject &obj, const QHostAddress &senderAddress);

    /// Construit le JSON d'un folder_op à partir d'une FileSyncOperation déjà
    /// hydratée (relativePath renseigné via JOIN de getByFolderId).
    QJsonObject buildFolderOpJson(const models::FileSyncOperation &op,
                                  const models::SharedFolder &folder) const;

    database::SyncOperationRepository m_repository;
    core::SharedFolderManager *m_folderManager = nullptr;
    network::MessagingServer *m_messagingServer = nullptr;
    network::MessagingService *m_messagingService = nullptr;
    network::TransferService *m_transferService = nullptr;
    network::DiscoveryService *m_discoveryService = nullptr;
    QString m_machineId;

    /// Curseur de diffusion : dernier op_id déjà broadcasté.
    /// Initialisé à latestId() pour ne pas re-diffuser les opérations
    /// des sessions précédentes au démarrage.
    qint64 m_lastBroadcastOpId = 0;
};

} // namespace core::sync

#endif // CORE_SYNC_FOLDERSYNCSERVICE_H
