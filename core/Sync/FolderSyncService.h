#ifndef CORE_SYNC_FOLDERSYNCSERVICE_H
#define CORE_SYNC_FOLDERSYNCSERVICE_H

#include <QObject>
#include <QString>
#include <QHostAddress>
#include <QVector>
#include <QHash>
#include <QTimer>

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
class UserManager;
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

    /// Identifiant de l'utilisateur courant sur cette machine (UserManager::currentUserId()).
    /// Utilisé par handleFolderAccessRevoked() pour détecter si c'est NOUS qui sommes
    /// révoqués et nettoyer les données locales du dossier en conséquence.
    void setLocalUserId(qint64 userId);

    /// Nécessaire pour inclure user_uuid dans les messages folder_op
    /// (pour la vérification des permissions effectivePermission).
    void setUserManager(core::UserManager *userManager);

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
     * @brief Demande un resync d'un dossier distant pour récupérer son contenu.
     *
     * Envoie un message folder_resync_request au propriétaire du dossier pour
     * récupérer toutes les opérations de synchronisation et télécharger les fichiers.
     *
     * @param folderUuid UUID du dossier distant à resynchroniser.
     */
    void requestFolderResync(const QString &folderUuid);

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

    /**
     * @brief Émis groupé (anti-rebond) après une rafale de fichiers reçus
     *        pour un même dossier partagé, afin qu'une seule notification
     *        "N fichiers reçus" soit affichée plutôt qu'une par fichier
     *        (cf. NotificationManager::onFolderFilesReceived).
     */
    void folderFilesReceived(const QString &folderUuid, const QString &folderName, int fileCount);

    /**
     * @brief Émis groupé (anti-rebond) après une rafale de fichiers envoyés
     *        (côté propriétaire/expéditeur) pour un même dossier partagé, en
     *        réponse à des folder_file_request, afin qu'une seule notification
     *        "N fichiers envoyés" soit affichée plutôt qu'une par fichier
     *        (cf. NotificationManager::onFolderFilesSent, symétrique de
     *        folderFilesReceived côté destinataire).
     */
    void folderFilesSent(const QString &folderUuid, const QString &folderName, int fileCount);

    /**
     * @brief Progression agrégée d'une rafale de transferts de synchronisation
     *        pour un même dossier partagé (réception OU envoi), émis à chaque
     *        fichier qui démarre/progresse/se termine pendant la rafale.
     *
     * Permet à l'UI d'afficher UNE SEULE barre de progression globale pour
     * tout le lot (ex: partage d'un dossier de 40 fichiers) plutôt qu'un
     * indicateur par fichier -- symétrique de folderFilesReceived/
     * folderFilesSent, mais émis en temps réel PENDANT la rafale plutôt
     * qu'une fois à la fin (cf. NotificationManager, qui reste la source de
     * la notification finale une fois la rafale terminée).
     *
     * @param incoming         true = réception, false = envoi (une rafale
     *                         entrante et une rafale sortante peuvent être en
     *                         cours simultanément pour le même dossier).
     * @param filesCompleted   Nombre de fichiers déjà terminés dans la rafale en cours.
     * @param filesTotal       Nombre total de fichiers annoncés jusqu'ici dans la rafale.
     * @param bytesTransferred Octets transférés cumulés (fichiers terminés + progression
     *                         des transferts encore actifs).
     * @param bytesTotal       Taille cumulée de tous les fichiers de la rafale.
     */
    void folderTransferProgress(const QString &folderUuid, const QString &folderName,
                                 bool incoming, int filesCompleted, int filesTotal,
                                 qint64 bytesTransferred, qint64 bytesTotal);

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

    /**
     * @brief À connecter sur TransferService::transferProgress.
     * Ne fait rien si transferKey ne correspond pas à un transfert
     * folder-sync actif (cf. isFolderTransfer()) : sinon, met à jour la
     * progression agrégée de la rafale en cours et émet folderTransferProgress().
     */
    void onTransferProgress(const QString &transferKey, qint64 bytesTransferred, qint64 totalBytes);

    /**
     * @brief Indique si transferKey correspond à un transfert déclenché par
     *        la synchronisation d'un dossier partagé (folder_file_request),
     *        par opposition à un transfert P2P "manuel" classique.
     *
     * Utilisé par app/Application.cpp pour éviter d'afficher une
     * notification par fichier lors d'un partage de dossier (les fichiers
     * "folder-sync" sont regroupés en une seule notification via
     * folderFilesReceived() côté destinataire, ou folderFilesSent() côté
     * expéditeur ; seuls les transferts manuels gardent leur notification
     * individuelle "Transfert terminé").
     *
     * Couvre les deux sens : un transfert entrant corrélé via
     * onTransferStarted()/m_activeByTransferKey (réception), ou un transfert
     * sortant déclenché par handleFolderFileRequest()/m_activeOutgoingByTransferKey
     * (envoi, réponse à un folder_file_request d'un pair).
     *
     * IMPORTANT : doit être appelé AVANT onTransferCompleted() pour le même
     * transferKey (qui retire l'entrée correspondante) -- voir l'ordre de
     * connexion dans Application.cpp.
     */
    bool isFolderTransfer(const QString &transferKey) const;

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

    /**
     * @brief Traite un "folder_resync_request" : un pair qui vient de
     *        recevoir un accès à ce dossier (folder_access_granted) demande
     *        immédiatement le contenu existant, sans attendre une future
     *        reconnexion (cf. handleFolderAccessGranted()).
     *
     * Ne répond que si CE poste est l'origine locale du dossier (seul le
     * propriétaire détient le contenu réel) et que le demandeur a toujours
     * un accès valide. Répond en réutilisant le format folder_catchup_batch
     * existant, limité aux opérations de ce dossier plus récentes que
     * since_op_id.
     */
    void handleFolderResyncRequest(const QJsonObject &obj);

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

    /**
     * @brief Applique localement un déplacement de SOUS-DOSSIER ENTIER
     *        distant (folder_op DirectoryRename, debrief point #6).
     *
     * oldRelativeDir/newRelativeDir sont des chemins de DOSSIERS (pas de
     * fichiers) : contrairement à applyRemoteRename() (un fichier à la
     * fois), cette méthode déplace tout le sous-arbre EN UNE SEULE
     * opération disque (QDir::rename()) quand le dossier source existe
     * déjà localement, puis répercute le renommage sur chaque ligne
     * SharedFiles concernée (mise à jour DB uniquement, pas de nouvel
     * accès disque par fichier). Se replie sur un renommage fichier par
     * fichier (applyRemoteRename()) si le sous-dossier source est
     * introuvable localement ou si la cible existe déjà (évite d'écraser
     * un contenu local par un renommage de dossier "en gros").
     */
    void applyRemoteDirectoryRename(const models::SharedFolder &folder, const QString &oldRelativeDir,
                                    const QString &newRelativeDir, const QString &machineId);

    /// Construit le JSON d'un folder_op à partir d'une FileSyncOperation déjà
    /// hydratée (relativePath renseigné via JOIN de getByFolderId).
    QJsonObject buildFolderOpJson(const models::FileSyncOperation &op,
                                  const models::SharedFolder &folder) const;

    /**
     * @brief Résout la permission effective d'un pair (machineId réseau) sur un
     *        dossier donné.
     *
     *  - Le propriétaire du dossier obtient toujours Write.
     *  - Un utilisateur connu (uuid == machineId) voit sa permission interrogée en
     *    base ; None signifie que son accès a été explicitement révoqué.
     *  - Si aucun utilisateur local ne correspond au machineId (identité non
     *    résolue), retourne Write (politique « fail-open ») : sur un réseau LAN de
     *    confiance on ne peut pas bloquer une machine dont le compte n'est pas
     *    enregistré localement — la sécurité périmètre repose sur l'isolation du LAN.
     *    En revanche, un utilisateur CONNU dont l'accès est révoqué est bloqué (None).
     */
    models::SharedFolderPermission effectivePermission(const models::SharedFolder &folder,
                                                        const QString &peerMachineId) const;

    /**
     * @brief Nettoie les données locales d'un dossier dont l'accès vient d'être
     *        révoqué sur CETTE machine (appeler uniquement quand m_localUserId
     *        correspond à l'utilisateur révoqué).
     *
     * Supprime les fichiers indexés sur le disque puis supprime l'enregistrement
     * du dossier dans la base locale (SharedFiles + SharedFolders cascade).
     */
    void cleanupRevokedFolder(const models::SharedFolder &folder);

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

    /**
     * @brief Enregistre les métadonnées d'un fichier annoncé par un
     *        folder_catchup_batch alors que le dossier distant n'a pas
     *        encore de localPath (l'utilisateur n'a pas choisi où stocker
     *        ce dossier reçu -- cf. setFolderLocalPath()).
     *
     * Sans localPath il est impossible de télécharger le contenu réel du
     * fichier, mais on peut déjà upserter SharedFiles + journaliser une
     * FileSyncOperation pour que le dossier n'apparaisse pas vide et que
     * son historique reflète ce qui a été annoncé. Ces entrées seront
     * complétées (hash/contenu réels) par le resync déclenché dès que
     * setFolderLocalPath() est appelé (cf. requestFolderResync()).
     */
    void registerCatchupPlaceholder(const models::SharedFolder &folder,
                                     const QString &relativePath,
                                     const QString &fileHash,
                                     int version,
                                     const QString &machineId);

    /// Regroupe (anti-rebond ~800ms) les fichiers reçus pour un même
    /// dossier avant d'émettre folderFilesReceived() -- voir isFolderTransfer().
    void scheduleFolderNotification(const QString &folderUuid);

    /// Émet folderFilesReceived() immédiatement pour folderUuid (arrête le
    /// timer d'anti-rebond en cours s'il y en a un) et nettoie l'état de
    /// notification/progression associé. Factorise la logique commune entre
    /// le timeout du timer de scheduleFolderNotification() et la détection
    /// de fin de rafale exacte (filesCompleted == filesExpected, cf.
    /// onTransferCompleted()). No-op si aucune notification n'est en attente.
    void flushFolderNotification(const QString &folderUuid);

    /// Symétrique de scheduleFolderNotification() côté expéditeur : regroupe
    /// (anti-rebond ~800ms) les fichiers envoyés en réponse à des
    /// folder_file_request pour un même dossier avant d'émettre
    /// folderFilesSent() -- voir isFolderTransfer() et handleFolderFileRequest().
    void scheduleFolderSentNotification(const QString &folderUuid);

    /// Symétrique de flushFolderNotification() côté expéditeur : émet
    /// folderFilesSent() immédiatement et nettoie l'état associé. No-op si
    /// aucune notification n'est en attente.
    void flushFolderSentNotification(const QString &folderUuid);

    /// État de progression agrégé d'une rafale de transferts folder-sync en
    /// cours pour un dossier donné (réception OU envoi, deux instances
    /// indépendantes -- voir m_receiveProgress/m_sentProgress).
    struct BatchProgress {
        int filesTotal = 0;
        int filesCompleted = 0;
        /// Nombre de fichiers déjà "acceptés" pour la rafale en cours,
        /// connu de façon SYNCHRONE et donc fiable, contrairement à
        /// filesTotal (incrémenté de façon asynchrone, fichier par fichier,
        /// à chaque démarrage réel de transfert dans onTransferStarted()).
        /// Coté RÉCEPTION (m_receiveProgress) : incrémenté dans
        /// requestRemoteFile(), dès l'émission de la demande -- avant même
        /// que le transfert ne démarre (cf. handleFolderCatchupBatch()).
        /// Côté ENVOI (m_sentProgress) : incrémenté dans
        /// handleFolderFileRequest(), dès l'acceptation d'un
        /// folder_file_request -- avant même que sendFile() ne termine (les
        /// requêtes d'une même rafale arrivent en rafale réseau rapprochée,
        /// bien avant que les transferts eux-mêmes ne se terminent).
        /// Dans les deux cas, permet de détecter la fin exacte d'une rafale
        /// sans attendre le debounce de 800ms (cf. scheduleFolderNotification()
        /// / scheduleFolderSentNotification()) -- ce debounce reste un filet
        /// de sécurité pour le cas où filesExpected sous-évalue le total réel.
        int filesExpected = 0;
        qint64 bytesTotal = 0;
        /// Somme des tailles des fichiers déjà terminés dans la rafale.
        qint64 bytesCompletedSum = 0;
        /// transferKey -> taille annoncée, pour les transferts encore actifs.
        QHash<QString, qint64> transferSizes;
        /// transferKey -> octets transférés à ce jour, pour les transferts encore actifs.
        QHash<QString, qint64> activeBytes;
    };

    /// Enregistre un nouveau fichier dans la rafale en cours pour folderUuid
    /// (incrémente filesTotal/bytesTotal) -- appelé depuis onTransferStarted()
    /// une fois le transfert corrélé à une PendingFileTransfer/folder_file_request.
    void registerBatchTransfer(QHash<QString, BatchProgress> &store, const QString &folderUuid,
                                const QString &transferKey, qint64 fileSize);

    /// Marque un fichier de la rafale comme terminé (déplace sa taille de
    /// transferSizes/activeBytes vers bytesCompletedSum, incrémente
    /// filesCompleted) -- appelé depuis onTransferCompleted().
    void completeBatchTransfer(QHash<QString, BatchProgress> &store, const QString &folderUuid,
                                const QString &transferKey);

    /// Émet folderTransferProgress() avec l'état courant de la rafale pour
    /// folderUuid (no-op si aucune rafale n'est en cours pour ce dossier).
    void emitBatchProgress(const QString &folderUuid, bool incoming);

    /// Calcule le SHA-256 hex d'un fichier sur disque. Retourne "" en cas d'erreur.
    static QString computeHash(const QString &filePath);

    /// Génère un chemin de conflit, ex: "Docs/rapport (abc123).docx".
    static QString makeConflictPath(const QString &relativePath, const QString &shortMachineId);


    database::SyncOperationRepository m_repository;
    database::SharedFileRepository m_fileRepository;
    database::SharedFolderAccessRepository m_accessRepository;
    database::UserRepository m_userRepository;
    core::SharedFolderManager *m_folderManager = nullptr;
    core::UserManager *m_userManager = nullptr;
    qint64 m_localUserId = 0; ///< Utilisateur courant (setLocalUserId).
    network::MessagingServer *m_messagingServer = nullptr;
    network::MessagingService *m_messagingService = nullptr;
    network::TransferService *m_transferService = nullptr;
    network::DiscoveryService *m_discoveryService = nullptr;
    QString m_machineId;

    /// Curseur de diffusion : dernier op_id déjà broadcasté.
    qint64 m_lastBroadcastOpId = 0;

    /// Dedup/backoff des folder_resync_request (debrief perf, point #3).
    /// Clé : "<folder_uuid>::<requester_machine_id>" → epoch ms (currentMSecsSinceEpoch)
    /// de la dernière réponse effectivement envoyée. Une nouvelle demande pour
    /// la même clé reçue moins de kResyncResponseCooldownMs après est ignorée
    /// sans reconstruire ni rediffuser de batch identique.
    QHash<QString, qint64> m_lastResyncResponseMs;

    // Release 8 — suivi des demandes de fichiers en attente.
    // Clé : "<ownerMachineId>::<fileName>" → PendingFileTransfer
    // (indexé par le basename du fichier tel qu'annoncé par TransferService).
    QHash<QString, PendingFileTransfer> m_pendingByKey;

    // Clé : transferKey (UUID) → PendingFileTransfer
    // (construit lors de onTransferStarted pour une corrélation O(1)).
    QHash<QString, PendingFileTransfer> m_activeByTransferKey;

    // Regroupement des notifications "fichier reçu" par dossier (anti-rebond).
    // Clé : folderUuid → nombre de fichiers reçus depuis le dernier signal.
    QHash<QString, int> m_pendingNotifyCounts;
    // Clé : folderUuid → minuteur anti-rebond associé.
    QHash<QString, QTimer *> m_notifyTimers;

    // Suivi symétrique côté ENVOI (expéditeur/propriétaire répondant à des
    // folder_file_request) -- permet à isFolderTransfer() de reconnaître ces
    // transferts sortants et de les regrouper en une seule notification
    // "N fichiers envoyés" au lieu d'une par fichier.
    // Clé : "<recipientUuid>::<fileName>" → folderUuid, enregistrée juste
    // après l'appel à TransferService::sendFile() dans handleFolderFileRequest().
    // (recipientUuid porte ici le machineId du demandeur, cf. sendFile() appelé
    // avec requesterMachineId en 5e argument -- pas de peerMachineId disponible
    // côté envoi, voir TransferService::onClientSocketConnected().)
    QHash<QString, QString> m_pendingOutgoingByKey;
    // Clé : transferKey (UUID) → folderUuid, construit lors de onTransferStarted()
    // une fois le transfert sortant corrélé à sa demande.
    QHash<QString, QString> m_activeOutgoingByTransferKey;
    // Clé : folderUuid → nombre de fichiers envoyés depuis le dernier signal.
    QHash<QString, int> m_pendingSentCounts;
    // Clé : folderUuid → minuteur anti-rebond associé (envoi).
    QHash<QString, QTimer *> m_sentNotifyTimers;

    // Progression agrégée en temps réel des rafales folder-sync en cours,
    // pour la barre de progression globale de l'UI (voir folderTransferProgress()).
    // Clé : folderUuid. Vidé (entrée retirée) une fois la rafale terminée,
    // càd au même moment que l'émission de folderFilesReceived()/
    // folderFilesSent() (fin du minuteur anti-rebond ~800ms), pour que la
    // rafale suivante reparte de zéro.
    QHash<QString, BatchProgress> m_receiveProgress;
    QHash<QString, BatchProgress> m_sentProgress;
};

} // namespace core::sync

#endif // CORE_SYNC_FOLDERSYNCSERVICE_H