#ifndef CORE_SYNC_FOLDERSYNCSERVICE_H
#define CORE_SYNC_FOLDERSYNCSERVICE_H

#include <QObject>
#include <QString>
#include <QHostAddress>
#include <QVector>
#include <QHash>

#include "database/Repositories/SyncOperationRepository.h"
#include "database/Repositories/SharedFileRepository.h"
#include "database/Repositories/SharedFolderAccessRepository.h"
#include "database/Repositories/UserRepository.h"
#include "models/FileSyncOperation.h"
#include "models/SharedFolder.h"
#include "models/SharedFile.h"
#include "models/SharedFolderPermission.h"

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
 *        de dossiers partagés (Releases 4–8 du cahier des charges).
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
 * Release 8 — Intégration des fichiers reçus + gestion des conflits
 *   Quand TransferService complète un transfert déclenché par un
 *   folder_file_request, ce service :
 *     1. Déplace le fichier reçu vers son chemin cible dans le dossier partagé.
 *     2. Détecte un éventuel conflit (hash local ≠ hash reçu, mêmes noms).
 *     3. En cas de conflit, renomme le fichier reçu en
 *        "nom (MachineId_courte).ext" et émet conflictDetected().
 *     4. Enregistre le fichier dans SharedFiles (upsert) et crée une
 *        FileSyncOperation de type Create/Update dans SyncOperations.
 *     5. Émet fileIntegrated() pour rafraîchir l'UI.
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

    /// Nécessaire pour servir les folder_file_request reçus de pairs et pour
    /// corréler les transferts entrants avec les demandes en attente.
    void setTransferService(network::TransferService *transfer);

    /// Nécessaire pour résoudre l'adresse IP d'un pair à partir de son machineId.
    void setDiscoveryService(network::DiscoveryService *discovery);

    /// Identifiant local (DiscoveryService::localId()) inclus dans chaque message.
    void setLocalMachineId(const QString &machineId);

    /**
     * @brief Annonce aux autres machines qu'un acces a ete accorde sur un
     *        dossier partage (a connecter sur SharedFolderManager::accessGranted,
     *        cf. app/Application.cpp).
     *
     * Diffuse un message "folder_access_granted" contenant l'uuid/nom du
     * dossier, l'uuid du proprietaire et l'uuid de l'utilisateur autorise.
     * Cote receveur (handleFolderAccessGranted()), si l'utilisateur autorise
     * existe localement (meme poste, cas multi-comptes), le dossier est
     * enregistre en metadonnees seules (registerRemoteFolder(), pas de
     * contenu) s'il n'existe pas deja, puis l'acces est accorde localement.
     * Ainsi une creation de dossier partage devient visible sur les autres
     * machines du LAN sans attendre une premiere synchronisation de fichiers.
     */
    void announceAccessGranted(qint64 folderId, qint64 userId, models::SharedFolderPermission permission);

    /**
     * @brief Annonce aux autres machines qu'un acces a ete revoque sur un
     *        dossier partage (a connecter sur SharedFolderManager::accessRevoked,
     *        cf. app/Application.cpp).
     *
     * Contrairement aux grants, ceci n'est PAS rattrapé hors-ligne (pas de
     * journal des revocations passees) : si le destinataire est deconnecte
     * au moment de l'annonce, il continuera de voir le dossier jusqu'a la
     * prochaine action de partage sur ce dossier. Limitation acceptee pour
     * borner la portee de cette version -- cf. mémoire du projet.
     */
    void announceAccessRevoked(qint64 folderId, qint64 userId);

    /**
     * @brief Envoie un folder_file_request pour un fichier distant.
     *
     * Enregistre également la demande en attente pour que onTransferStarted()
     * puisse corréler le transfert entrant avec le bon dossier/chemin.
     *
     * @param folderUuid      UUID du dossier partagé cible.
     * @param relativePath    Chemin relatif du fichier dans le dossier.
     * @param ownerMachineId  machineId du pair qui possède le fichier.
     */
    void requestRemoteFile(const QString &folderUuid, const QString &relativePath,
                           const QString &ownerMachineId);

    /**
     * @brief Surcharge enrichie : enregistre aussi la PendingFileTransfer pour
     *        que onTransferStarted/onTransferCompleted intègrent le fichier
     *        automatiquement dans le dossier partagé (Release 8).
     *
     * @param folderId        ID local du dossier (0 = désactive l'intégration).
     * @param localFolderPath Chemin absolu de la racine du dossier partagé.
     * @param incomingHash    SHA-256 annoncé dans folder_op (peut être vide).
     * @param incomingVersion Version annoncée dans folder_op (0 = inconnu).
     */
    void requestRemoteFile(const QString &folderUuid, const QString &relativePath,
                           const QString &ownerMachineId, qint64 folderId,
                           const QString &localFolderPath, const QString &incomingHash,
                           int incomingVersion);

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

    /**
     * @brief Émis quand un fichier reçu a été intégré avec succès dans le
     *        dossier partagé et enregistré dans SharedFiles (Release 8).
     *
     * @param folderUuid    UUID du dossier partagé.
     * @param relativePath  Chemin relatif du fichier intégré (dans le dossier).
     * @param wasConflict   true si un conflit a été détecté (le fichier reçu a
     *                      été renommé, voir conflictDetected).
     */
    void fileIntegrated(const QString &folderUuid,
                        const QString &relativePath,
                        bool wasConflict);

    /**
     * @brief Émis quand un conflit de version est détecté lors de l'intégration
     *        d'un fichier reçu (Release 8).
     *
     * Le fichier reçu a été renommé en conflictPath pour préserver les deux
     * versions. Le fichier local n'est pas modifié.
     *
     * @param folderUuid    UUID du dossier partagé.
     * @param relativePath  Chemin relatif du fichier en conflit.
     * @param conflictPath  Chemin relatif du fichier renommé (copie en conflit).
     */
    void conflictDetected(const QString &folderUuid,
                          const QString &relativePath,
                          const QString &conflictPath);

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

    /**
     * @brief À connecter sur TransferService::transferStarted (Release 8).
     * Corrèle le transferKey avec la PendingFileTransfer correspondante.
     */
    void onTransferStarted(const QString &transferKey, const QString &fileName,
                           qint64 fileSize, bool incoming, qint64 resumeOffset,
                           const QString &senderUuid, const QString &recipientUuid,
                           const QHostAddress &peerAddress, const QString &peerMachineId);

    /**
     * @brief À connecter sur TransferService::transferCompleted (Release 8).
     * Intègre le fichier reçu dans le dossier partagé (copie, upsert, SyncOp).
     */
    void onTransferCompleted(const QString &transferKey, const QString &filePath);

private slots:
    void onServerMessageReceived(const QString &message, const QHostAddress &senderAddress);
    void onClientMessageReceived(const QString &message);

private:
    /// Demande de fichier en attente de réception (Release 8).
    struct PendingFileTransfer {
        QString folderUuid;
        QString relativePath;   ///< Chemin relatif dans le dossier partagé.
        qint64  folderId = 0;   ///< ID local du dossier.
        QString localFolderPath; ///< Chemin absolu de la racine du dossier.
        QString ownerMachineId;  ///< machineId du pair émetteur.
        QString incomingHash;    ///< Hash annoncé dans folder_op (peut être vide).
        int     incomingVersion = 0;
    };

    /// Diffuse un message JSON à tous les clients connectés (côté SERVER)
    /// ou l'envoie au serveur actif (côté CLIENT).
    void broadcastMessage(const QString &json);

    /// Envoie un message JSON uniquement vers le serveur actif (MessagingService).
    void sendMessageToServer(const QString &json);

    void handleFolderOp(const QJsonObject &obj, const QHostAddress &senderAddress);
    void handleFolderHello(const QJsonObject &obj);
    void handleFolderCatchupBatch(const QJsonObject &obj);
    void handleFolderFileRequest(const QJsonObject &obj, const QHostAddress &senderAddress);
    void handleFolderAccessGranted(const QJsonObject &obj);
    void handleFolderAccessRevoked(const QJsonObject &obj);

    /// Construit le JSON d'une annonce "folder_access_granted" pour un
    /// acces donne (utilise par announceAccessGranted() pour la diffusion
    /// immediate ET par handleFolderHello() pour le rattrapage hors-ligne,
    /// cf. SharedFolderAccessRepository::getSinceId()). std::nullopt si le
    /// dossier/proprietaire/beneficiaire ne peut pas etre resolu.
    std::optional<QJsonObject> buildAccessGrantedJson(qint64 folderId, qint64 userId,
                                                        models::SharedFolderPermission permission) const;

    /**
     * @brief Applique localement une suppression distante (folder_op Delete).
     *
     * Supprime le fichier sur disque (s'il existe encore), marque la ligne
     * SharedFiles correspondante comme supprimee (tombstone) et journalise
     * l'operation dans SyncOperations pour un futur rattrapage (Release 7).
     */
    void applyRemoteDelete(const models::SharedFolder &folder, const QString &relativePath,
                           const QString &machineId);

    /**
     * @brief Applique localement un renommage/deplacement distant
     *        (folder_op Rename).
     *
     * Renomme le fichier sur disque (s'il existe encore sous son ancien
     * chemin), met a jour relative_path dans SharedFiles et journalise
     * l'operation.
     */
    void applyRemoteRename(const models::SharedFolder &folder, const QString &oldRelativePath,
                          const QString &newRelativePath, const QString &machineId);

    /// Construit le JSON d'un folder_op à partir d'une FileSyncOperation déjà
    /// hydratée (relativePath renseigné via JOIN de getByFolderId).
    QJsonObject buildFolderOpJson(const models::FileSyncOperation &op,
                                  const models::SharedFolder &folder) const;

    /**
     * @brief Intègre un fichier reçu dans le dossier partagé (Release 8).
     *
     * 1. Calcule le hash SHA-256 du fichier source.
     * 2. Détecte un éventuel conflit (fichier local ≠ version reçue).
     * 3. Crée les répertoires parents si nécessaire.
     * 4. Copie le fichier (avec renommage si conflit).
     * 5. Upsert SharedFile + insert FileSyncOperation.
     * 6. Émet fileIntegrated() (et conflictDetected() si applicable).
     */
    void integrateReceivedFile(const PendingFileTransfer &pending, const QString &sourcePath);

    /// Calcule le SHA-256 hex d'un fichier sur disque. Retourne "" en cas d'erreur.
    static QString computeHash(const QString &filePath);

    /// Génère un chemin de conflit, ex: "Docs/rapport (abc123).docx".
    static QString makeConflictPath(const QString &relativePath, const QString &shortMachineId);


    database::SyncOperationRepository m_repository;
    database::SharedFileRepository m_fileRepository;
    database::SharedFolderAccessRepository m_accessRepository;
    database::UserRepository m_userRepository;
    core::SharedFolderManager *m_folderManager = nullptr;
    network::MessagingServer *m_messagingServer = nullptr;
    network::MessagingService *m_messagingService = nullptr;
    network::TransferService *m_transferService = nullptr;
    network::DiscoveryService *m_discoveryService = nullptr;
    QString m_machineId;

    /// Curseur de diffusion : dernier op_id déjà broadcasté.
    qint64 m_lastBroadcastOpId = 0;

    // Release 8 — suivi des demandes de fichiers en attente.
    // Clé : "<ownerMachineId>::<fileName>" → PendingFileTransfer
    // (indexé par le basename du fichier tel qu'annoncé par TransferService).
    QHash<QString, PendingFileTransfer> m_pendingByKey;

    // Clé : transferKey (UUID) → PendingFileTransfer
    // (construit lors de onTransferStarted pour une corrélation O(1)).
    QHash<QString, PendingFileTransfer> m_activeByTransferKey;
};

} // namespace core::sync

#endif // CORE_SYNC_FOLDERSYNCSERVICE_H
