#ifndef APP_APPLICATION_H
#define APP_APPLICATION_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QSet>
#include <QHash>
#include <QDateTime>
#include <QJsonObject>
#include <memory>

class QTimer;

namespace database {
class DatabaseManager;
class ServerElectionRepository;
class SyncLogRepository;
struct MessageReceipt;
}

namespace core {
class UserManager;
class MessagingManager;
class GroupManager;
class TransferManager;
class NotificationManager;
class AuditManager;
class PermissionManager;
class CallHistoryManager;
class SharedFolderManager;
namespace sync {
class SyncEngine;
class FolderSyncService;
}
}

namespace network {
struct DiscoveredPeer;
class DiscoveryService;
class PeersModel;
class MessagingService;
class MessagingServer;
class SecurityService;
class TransferService;
class ElectionService;
class SyncService;
class VoiceService;
}

namespace models {
class Group;
class Message;
class User;
}

namespace services {
class AudioService;
}

/**
 * @brief Point d'entree logique de LocaLink : initialise les services
 * (reseau, base de donnees, parametres) au demarrage de l'application.
 */
class Application : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString pendingServerFingerprint READ pendingServerFingerprint NOTIFY pendingServerChanged)
    Q_PROPERTY(QString pendingServerAddress READ pendingServerAddress NOTIFY pendingServerChanged)
    Q_PROPERTY(int pendingServerPort READ pendingServerPort NOTIFY pendingServerChanged)
    /// Code d'appairage du serveur en attente d'approbation (6 chiffres), a
    /// comparer avec celui que l'administrateur voit pour ce poste.
    Q_PROPERTY(QString pendingServerPairingCode READ pendingServerPairingCode NOTIFY pendingServerChanged)
    Q_PROPERTY(int pendingClientCount READ pendingClientCount NOTIFY pendingClientCountChanged)
    /// Vrai au tout premier lancement du serveur principal, tant qu'aucun compte n'existe :
    /// l'ecran de connexion propose alors de creer le premier administrateur (plus aucun
    /// compte par defaut a mot de passe connu).
    Q_PROPERTY(bool needsInitialAdmin READ needsInitialAdmin NOTIFY initialAdminStateChanged)

public:
    explicit Application(QObject *parent = nullptr);
    ~Application();

    void initialize();

    /// Initialise avec un port spécifique pour le serveur de messagerie.
    void initialize(quint16 messagingServerPort);

    /// Initialise avec un port et un chemin de base de donnees specifiques.
    /// Utile pour lancer plusieurs instances sur la meme machine (tests
    /// locaux) sans qu'elles ne partagent la meme base ni le meme port.
    /// dbFilePath vide => chemin par defaut (DatabaseManager::defaultDatabaseFilePath()).
    void initialize(quint16 messagingServerPort, const QString &dbFilePath);

    /// Variante de test/démo : force le rôle initial (et éventuellement le
    /// priority_weight) de ce poste dans ServerElection avant le démarrage
    /// d'ElectionService, plutôt que de laisser la valeur déjà persistée en
    /// base. Sert à scripter des scénarios de bascule multi-instances (CLI
    /// --role, cf. app/main.cpp) sans avoir à passer par l'UI d'admin.
    /// roleOverride vide => pas de forçage, on garde l'état déjà en base.
    /// priorityWeightOverride < 0 => pas de forçage.
    void initialize(quint16 messagingServerPort, const QString &dbFilePath,
                     const QString &roleOverride, int priorityWeightOverride = -1);

    /// Variante utilisee par les tests d'integration (bascule automatique,
    /// HYBRID_SERVER_FAILOVER.md section 9) : plusieurs instances Application
    /// lancees dans le meme process de test doivent utiliser des ports
    /// ElectionService distincts pour ne pas se parasiter mutuellement.
    /// electionPort == 0 => port par defaut d'ElectionService (45455).
    void initialize(quint16 messagingServerPort, const QString &dbFilePath,
                     const QString &roleOverride, int priorityWeightOverride,
                     quint16 electionPort);

    /// Applique un port UDP de decouverte different du defaut (45454,
    /// DiscoveryService::m_port) - a appeler AVANT initialize() (le port
    /// d'un socket deja lie/en ecoute ne peut pas etre change a chaud).
    /// Reflete settingsModel.discoveryPort (ecran Parametres > Ports
    /// reseau, cf. app/main.cpp) : le changement ne prend donc effet qu'au
    /// prochain lancement de l'application, comme pour le port de
    /// messagerie (--port).
    /// port == 0 => garde le port par defaut de DiscoveryService.
    void setDiscoveryPort(quint16 port);

    // Expose au bootstrap QML (voir app/main.cpp) l'objet a brancher sur
    // LoginView.qml via setContextProperty("userManager", ...).
    core::UserManager *userManager() const;

    // Expose au bootstrap QML (app/main.cpp) le modele des postes detectes,
    // a brancher sur UsersView.qml via setContextProperty("peersModel", ...)
    // (issue #17).
    network::PeersModel *peersModel() const;
    network::DiscoveryService *discoveryService() const;

    // Expose au bootstrap QML le MessagingManager pour la messagerie.
    core::MessagingManager *messagingManager() const;

    // Expose au bootstrap QML le GroupManager pour les groupes.
    core::GroupManager *groupManager() const;

    // Expose au bootstrap QML le SecurityService pour la sécurité.
    network::SecurityService *securityService() const;

    // Expose au bootstrap QML le MessagingService pour la messagerie réseau.
    network::MessagingService *messagingService() const;

    // Expose au bootstrap QML le MessagingServer pour recevoir les messages.
    network::MessagingServer *messagingServer() const;

    // Expose l'ElectionService : utilise par AdminView.qml pour l'historique
    // des bascules (issue future) et par les tests d'integration pour
    // observer/accelerer le cycle heartbeat/election sans attendre les
    // delais par defaut (HYBRID_SERVER_FAILOVER.md section 9, etape 3).
    network::ElectionService *electionService() const;

    // Expose le SyncService : utilise par les tests d'integration pour
    // observer la reconciliation post-panne (reconciliationCompleted/Failed)
    // declenchee via ElectionService::reconciliationRequired (issue #4).
    network::SyncService *syncService() const;

    /// Historique des bascules (ServerElectionLog), du plus recent au plus
    /// ancien, pour AdminView.qml (HYBRID_SERVER_FAILOVER.md section 9,
    /// etape 5). Chaque entree : { event, epoch, machineUuid, createdAt }.
    Q_INVOKABLE QVariantList electionHistory(int limit = 50) const;

    /// A appeler depuis SettingsView.qml plutot que
    /// electionService()->setPriorityWeight() directement : met a jour le
    /// service ET persiste la valeur en base (ServerElectionRepository),
    /// pour qu'elle survive a un redemarrage.
    Q_INVOKABLE bool setElectionPriorityWeight(int weight);

    /// A appeler depuis SettingsView.qml pour faire de CE poste le serveur
    /// officiel (role Server, non temporaire). Reutilise le meme mecanisme
    /// que la reprise de main post-panne (ElectionService::reclaimAsOfficialServer,
    /// section 7.3) : nouvel epoch, diffusion server_promoted(temporary=false).
    /// electionService()::roleChanged (deja cable dans initialize()) se charge
    /// ensuite de persister le role en base et de demarrer MessagingServer.
    /// Ne fait rien si ce poste est deja Server (retourne false).
    Q_INVOKABLE bool promoteToServer();
    Q_INVOKABLE bool demoteToClient();

    QString pendingServerFingerprint() const;
    QString pendingServerAddress() const;
    int pendingServerPort() const;
    int pendingClientCount() const;
    QString pendingServerPairingCode() const;
    /// Nom affiche d'un poste decouvert : compte connecte, sinon nom du poste.
    QString peerDisplayName(const network::DiscoveredPeer &peer) const;
    Q_INVOKABLE bool approvePendingServerCertificate();
    /// Code d'appairage entre ce poste et la machine d'empreinte donnee
    /// (Administration : machine en attente, poste detecte a ajouter).
    Q_INVOKABLE QString pairingCodeWith(const QString &peerFingerprint) const;

    // Expose au bootstrap QML le NotificationManager pour les notifications.
    core::NotificationManager *notificationManager() const;

    // Expose au bootstrap QML le TransferService pour le transfert de fichiers (issue #53).
    network::TransferService *transferService() const;

    // Expose au bootstrap QML le TransferManager pour l'historique des transferts (issue #55).
    core::TransferManager *transferManager() const;

    // Expose au bootstrap QML l'AudioService pour les sons de notification (issue #56).
    services::AudioService *audioService() const;

    // Expose au bootstrap QML le AuditManager pour le journal d'audit (issue #65).
    core::AuditManager *auditManager() const;

    // Expose au bootstrap QML le PermissionManager pour la gestion des rôles (issue #67).
    core::PermissionManager *permissionManager() const;

    // Expose au bootstrap QML le VoiceService pour les appels vocaux P2P (issues #60/#61/#64).
    network::VoiceService *voiceService() const;

    // Expose au bootstrap QML le CallHistoryManager pour l'historique des appels.
    core::CallHistoryManager *callHistoryManager() const;

    // Expose au bootstrap QML le SharedFolderManager pour le module "Shared Folder".
    core::SharedFolderManager *sharedFolderManager() const;

    // Expose au bootstrap QML le SyncEngine (orchestration de la
    // (re)indexation + journal SyncOperations, cf. core/Sync/SyncEngine.h).
    core::sync::SyncEngine *syncEngine() const;

    // Expose le FolderSyncService (diffusion réseau temps réel des changements
    // de dossiers partagés, Releases 4-7).
    core::sync::FolderSyncService *folderSyncService() const;

    // Expose le DatabaseManager pour les services qui en ont besoin (ex: SettingsService).
    database::DatabaseManager *databaseManager() const;

signals:
    void pendingServerChanged();
    void pendingClientCountChanged();
    void initialAdminStateChanged();

private:
    /// Cree le compte "admin" par defaut (dev/demo) si la base est vide et
    /// que ce poste est (ou devient) Server/TempServer. Ne doit JAMAIS etre
    /// appele pour un poste Client : celui-ci recupere systematiquement les
    /// comptes existants via synchronisation, et un seed local ferait
    /// collision avec le compte "admin" reel du serveur (rejeu renomme en
    /// "admin*conflict*<uuid>", cf. SyncLogRepository::applyUserEntry).
    /// Idempotent (relit allUsers() a chaque appel).
    void seedDefaultAdminIfNeeded();

public:
    bool needsInitialAdmin() const;

    /// Cree le premier compte administrateur (premier lancement du serveur principal, base vide).
    /// Renvoie un message d'erreur a afficher, ou une chaine vide en cas de succes.
    Q_INVOKABLE QString createInitialAdmin(const QString &name, const QString &password,
                                           const QString &confirmation);

private:

    /// Diffuse en temps reel (type "user_event") la creation/mise a jour
    /// d'un utilisateur a tous les postes actuellement connectes, plutot
    /// que d'attendre la prochaine reconciliation SyncLog (qui ne se
    /// declenche qu'a la (re)connexion -- cf. appendUserSyncLog, qui ne
    /// fait que journaliser pour un rejeu differe). Meme principe que
    /// GroupManager::createGroup pour "group_created" : envoi sur les deux
    /// canaux (m_messagingService sortant + m_messagingServer entrant), le
    /// createur pouvant etre SERVER ou simple CLIENT.
    void broadcastUserEvent(const models::User &user, const QString &operation);

    /// Rattrapage cible : envoie a UN client qui vient de s'identifier
    /// (cf. MessagingServer::clientIdentified) l'integralite des comptes
    /// utilisateurs existants sous forme de "users_catchup_batch", meme
    /// format de payload que broadcastUserEvent afin de reutiliser
    /// exactement le meme chemin de reception (handleIncomingPayload ->
    /// SyncLogRepository::applyUserEntry, deja idempotent et LWW).
    /// Sans cela, un poste qui rejoint le reseau APRES la creation d'un
    /// compte ne le voit jamais : le "user_event" temps reel de
    /// broadcastUserEvent n'atteint que les postes deja connectes au
    /// moment de la creation (meme lacune que celle deja comblee pour les
    /// dossiers partages via folder_catchup_batch, cf. FolderSyncService).
    /// Ne s'applique que si CE poste ecoute reellement (Server/TempServer) :
    /// un simple Client n'a pas de MessagingServer actif et ne peut donc
    /// jamais recevoir ce signal.
    /// @p userUuid peut etre vide (poste tout neuf sans aucun compte local,
    /// cf. MessagingServer::clientIdentified) : dans ce cas le batch est
    /// cible via @p fingerprint (sendToFingerprint) plutot que via
    /// sendToUuids, seul moyen d'atteindre une machine qui ne peut par
    /// definition jamais s'identifier par userUuid avant d'avoir recu ce
    /// meme batch (cf. debrief "chicken-and-egg" login/rattrapage).
    void sendUsersCatchupTo(const QString &userUuid, const QString &fingerprint, bool authorized);

    /// Liste des machines autorisees ("authorized_peers") envoyee par le
    /// serveur a ses clients autorises, pour que deux clients s'acceptent
    /// pour les appels et transferts directs. Envoyee a chaque client qui
    /// s'identifie, puis rediffusee a chaque autorisation, revocation ou
    /// retrait. Sans effet si ce poste n'ecoute pas (simple client).
    QString authorizedPeersPayload() const;
    /// Machines autorisees sur ce poste ("temp_authorizations"), envoyees par
    /// un serveur de secours au serveur officiel qui le rejoint pour la
    /// reconciliation : celui-ci reprend les autorisations donnees pendant la panne.
    QString tempAuthorizationsPayload() const;
    void sendAuthorizedPeersTo(const QString &userUuid, const QString &fingerprint, bool authorized);
    void broadcastAuthorizedPeers();

    /// Diffuse en temps reel (type "server_election_event") une entree
    /// d'historique ServerElectionLog (log_uuid, event, epoch, machineUuid)
    /// a tous les postes actuellement connectes, afin que ServerElection/
    /// ServerElectionLog ne divergent plus silencieusement entre instances
    /// (cf. HYBRID_SERVER_FAILOVER.md). Meme principe que broadcastUserEvent :
    /// envoi sur les deux canaux (m_messagingService sortant + m_messagingServer
    /// entrant), et reception geree dans handleIncomingPayload() via
    /// ServerElectionRepository::applyRemoteLogEntry (idempotent sur log_uuid)
    /// + ServerElectionRepository::bumpEpochIfNewer (jamais de retour en
    /// arriere sur l'epoch local, current_role jamais copie depuis un pair).
    void broadcastServerElectionEvent(const QString &logUuid, const QString &event, int epoch,
                                      const QString &machineUuid, const QDateTime &createdAt);

    bool shouldWriteSyncLog() const;
    void appendSyncLogEntry(const QString &tableName, const QString &recordUuid,
                            const QString &operation, const QString &payloadJson,
                            bool bypassRoleCheck = false);
    void appendMessageSyncLog(const models::Message &message);
    /// Serveur : journalise un message relaye (payload reseau "message"), meme
    /// si son utilisateur n'y participe pas, pour le servir aux destinataires
    /// absents. Vrai si le message est (deja) dans le journal.
    bool journalRelayedMessage(const QJsonObject &message);
    /// Serveur : journalise une modification/suppression de message ("message_update").
    void journalMessageChange(const QJsonObject &payload);
    /// Destinataires d'un payload adresse comme un message (participants, membres).
    QStringList messageTargets(const QJsonObject &payload) const;
    /// Serveur : l'utilisateur identifie sur la connexion courante est le
    /// proprietaire de ce groupe.
    bool isGroupOwnerOnConnection(const QString &groupUuid) const;
    /// Serveur : enregistre et journalise des accuses (etat cumule), puis les
    /// transmet aux expediteurs connectes.
    /// Cles "message|utilisateur" : traites (y compris sans effet), et inconnus
    /// (message absent du journal de ce serveur).
    struct ReceiptOutcome {
        QStringList handled;
        QStringList unknown;
    };
    ReceiptOutcome processReceiptsAsServer(const QVector<database::MessageReceipt> &receipts);
    /// Accuses envoyes sur la connexion courante, en attente de "receipts_ack".
    QSet<QString> m_receiptsInFlight;
    /// Transmet les accuses produits ici (au serveur, ou traites ici si ce
    /// poste est le serveur). Regroupes par scheduleReceiptFlush.
    void flushReceipts();
    void scheduleReceiptFlush();
    bool m_receiptFlushScheduled = false;
    /// Serveur : purge du journal (SyncLogRepository::compact), au passage en
    /// role serveur puis toutes les 6 heures.
    void compactJournal();
    QTimer *m_compactTimer = nullptr;

    /// Changement fait ici (modification/suppression de message, groupes) :
    /// serveur -> journalise et relaye aux destinataires ; client -> mis en file
    /// d'attente (table Outbox) puis transmis, jusqu'a l'accuse "change_ack".
    /// requiresOfficial : n'est transmis qu'au serveur officiel.
    void sendOrQueueChange(const QJsonObject &payload, const QStringList &targets, bool requiresOfficial);
    /// Transmet les changements en attente de l'utilisateur connecte.
    void flushOutbox();
    /// Ce poste devient serveur : ses changements en attente sont journalises ici.
    void takeOverOutbox();
    void journalLocalChange(const QJsonObject &payload);
    /// Serveur : accuse (accepte ou refuse) d'un changement venu de la file d'un client.
    void ackChange(const QJsonObject &payload, bool accepted, const QString &reason = QString());
    /// Changements envoyes sur la connexion courante, en attente d'accuse.
    QSet<QString> m_outboxInFlight;

    /// Journal d'audit : marque un evenement a transmettre au serveur officiel
    /// (AuditLogs.pending_send), puis transmet ceux en attente jusqu'a "audit_ack".
    void queueAuditEvent(const QString &eventUuid, bool remote);
    void flushAuditEvents();
    QSet<QString> m_auditInFlight;
    void appendGroupSyncLog(const models::Group &group, const QString &operation);
    void appendUserSyncLog(const models::User &user, const QString &operation,
                           bool bypassRoleCheck = false);

    /// Uuid de l'utilisateur local d'id donne (chaine vide si introuvable).
    /// Utilise pour serialiser des references stables (senderUuid, ownerUuid,
    /// memberUuids) dans les payloads SyncLog de Messages/Groups/GroupMembers,
    /// plutot que l'id local AUTOINCREMENT qui ne coincide pas forcement
    /// entre postes (cf. HYBRID_SERVER_FAILOVER.md et la note de
    /// SyncLogRepository::applyUserEntry).
    QString userUuidForId(qint64 userId) const;

    /// Uuid des comptes membres du groupe designe par son uuid (vide si inconnu localement).
    QStringList groupMemberUuids(const QString &groupUuid) const;

    /// Vrai si l'uuid designe un compte Admin dans la base LOCALE de ce poste.
    bool isLocalAdminUuid(const QString &userUuid) const;

    /// Un changement de compte (user_event) recu d'un client n'est accepte par le serveur que
    /// si cette connexion est autorisee et identifiee comme un compte Admin connu ici.
    bool isUserEventFromAdmin() const;

    /// Uuid de la Conversation locale d'id donne (chaine vide si introuvable).
    QString conversationUuidForId(qint64 conversationId) const;

    /// Traite un payload applicatif recu du reseau (type "message" ou
    /// "group_created"), que ce poste soit celui qui l'a recu en tant que
    /// SERVER (connexion entrante, cf. MessagingServer::messageReceived)
    /// ou en tant que CLIENT (connexion sortante vers le SERVER actif, cf.
    /// MessagingService::messageReceived). Persiste localement (ou
    /// deduplique si deja connu) puis, si `relay` est vrai (poste SERVER
    /// disposant d'autres clients connectes), rediffuse le payload tel
    /// quel : dans la topologie en etoile de LocaLink, un message envoye
    /// par un client n'atteignait jusqu'ici QUE le SERVER (qui le
    /// persistait dans SA PROPRE base sans jamais le retransmettre au
    /// veritable destinataire) - c'etait la cause principale des messages
    /// "perdus" cote destinataire.
    /// Q_INVOKABLE : permet aux tests d appeler ce point d entree unique de reception
    /// sans monter une vraie connexion WebSocket (meme procede que FolderSyncService).
    Q_INVOKABLE void handleIncomingPayload(const QString &message, bool relay);

    /// Envoie au serveur actif le handshake d'identification
    /// {"type":"identify","userUuid":...} via m_messagingService, si la
    /// connexion est etablie ET qu'un utilisateur est actuellement
    /// connecte localement. Appele a la fois sur MessagingService::connected
    /// et sur UserManager::loginSucceeded (l'ordre entre les deux n'est
    /// pas garanti : connexion reseau et login peuvent survenir dans
    /// n'importe quel ordre selon que ce poste redemarre avec un serveur
    /// deja actif ou se connecte avant/apres l'authentification).
    /// Sans ce handshake, MessagingServer ne peut jamais associer cette
    /// connexion a un utilisateur, et sendToUuids() ne peut donc jamais
    /// cibler ce poste (issue #2 : diffusion non ciblee).
    void sendIdentifyIfReady();

    /// Apres chaque identification aupres du serveur (connexion, reconnexion,
    /// login) : synchronisation incrementale du journal pour l'utilisateur
    /// courant, puis renvoi de sa file d'envoi.
    void requestClientSync();

    /// Vrai si ce qui arrive maintenant par la connexion sortante ne vient pas du
    /// serveur officiel : ce poste est le serveur officiel (il ne se connecte en
    /// sortie qu'a un serveur de secours, pour la reconciliation), ou il est
    /// client d'un serveur de secours.
    bool userChangesFromUntrustedSource() const;

    /// Reconnexion automatique au serveur actif apres une coupure (delai
    /// croissant de 1 s a 30 s). Sans elle, un client restait deconnecte tant
    /// que le serveur actif ne changeait pas.
    void scheduleReconnect();
    void attemptReconnect();
    QTimer *m_reconnectTimer = nullptr;
    int m_reconnectDelayMs = 1000;

    /// CORRECTIF (bande passante) : ElectionService::reconciliationRequired
    /// est emis a CHAQUE heartbeat recu du TempServer tant que ce poste
    /// reste Server officiel (pas une seule fois), et chaque heartbeat
    /// redemandait jusqu'ici une reconciliation complete avec le meme
    /// fromEpoch -> le meme sync_batch (~20 entrees) etait retransmis
    /// quasi identique des dizaines de fois. Ces deux champs permettent de
    /// n'effectuer reellement la reconciliation qu'une fois par epoch
    /// distincte, et d'ignorer les heartbeats suivants tant qu'elle est
    /// deja en cours ou deja terminee pour cet epoch.
    int m_lastReconciledEpoch = -1;
    bool m_reconciliationInFlight = false;

    /// CORRECTIF (boucle de reconnexion infinie -> instabilite/plantage du
    /// poste Server) : sans garde, un certificat TEMP_SERVER jamais
    /// approuve (cf. m_pendingServerFingerprint) faisait retenter une
    /// connexion TLS complete a CHAQUE heartbeat (toutes les 3s, cf.
    /// ElectionService::heartbeatIntervalMs), pour toujours -- la
    /// connexion aboutissait puis etait fermee aussitot par
    /// MessagingService::onConnected() des que trustRemoteServerCertificate()
    /// echouait, sans jamais faire avancer m_lastReconciledEpoch (mis a jour
    /// uniquement en cas de succes). A la longue, ce handshake TLS repete
    /// toutes les 3 secondes epuise les ressources reseau (sockets en
    /// TIME_WAIT, allocations OpenSSL) et peut geler/planter le poste. On
    /// n'attend meme plus le prochain heartbeat pour retenter : si le
    /// certificat en attente correspond exactement a ce TEMP_SERVER, on
    /// n'a aucune raison de reessayer avant qu'un humain l'approuve
    /// (Parametres > approveServerCertificate). Le cooldown ci-dessous est
    /// un filet de securite general pour toute autre cause de blocage.
    qint64 m_lastReconciliationAttemptMs = 0;
    static constexpr qint64 kReconciliationRetryCooldownMs = 15000;

    /// Payloads JSON de messages temps reel dont l'expediteur (senderUuid)
    /// n'etait pas encore connu localement au moment de la reception (cf.
    /// MessagingManager::unresolvedSenderMessage) ; rejoues des qu'une
    /// reconciliation se termine.
    QStringList m_pendingUnresolvedMessages;

    // TODO: instancier ici les autres services (Security, Settings...)
    quint16 m_discoveryPortOverride = 0; // 0 = port par defaut de DiscoveryService (voir setDiscoveryPort())
    std::unique_ptr<database::DatabaseManager> m_databaseManager;
    std::unique_ptr<database::ServerElectionRepository> m_serverElectionRepository;
    std::unique_ptr<database::SyncLogRepository> m_syncLogRepository;
    core::UserManager *m_userManager = nullptr;               // parente = this (QObject)
    core::MessagingManager *m_messagingManager = nullptr;     // parente = this (QObject)
    core::GroupManager *m_groupManager = nullptr;             // parente = this (QObject)
    core::NotificationManager *m_notificationManager = nullptr; // parente = this (QObject)
    network::DiscoveryService *m_discoveryService = nullptr;  // parente = this (QObject)
    QSet<QString> m_notifiedPeerUsers;
    network::PeersModel *m_peersModel = nullptr;               // parente = this (QObject)
    network::SecurityService *m_securityService = nullptr;    // parente = this (QObject)
    network::MessagingService *m_messagingService = nullptr;  // parente = this (QObject)
    QString m_pendingServerFingerprint;
    /// Codes d'appairage deja calcules (PBKDF2, environ 0,1 s chacun), par empreinte.
    mutable QHash<QString, QString> m_pairingCodes;
    QString m_pendingServerAddress;
    quint16 m_pendingServerPort = 0;
    network::MessagingServer *m_messagingServer = nullptr;    // parente = this (QObject)
    network::TransferService *m_transferService = nullptr;    // parente = this (QObject)
    network::ElectionService *m_electionService = nullptr;      // parente = this (QObject)
    network::SyncService *m_syncService = nullptr;              // parente = this (QObject)
    core::TransferManager *m_transferManager = nullptr;       // parente = this (QObject)
    services::AudioService *m_audioService = nullptr;         // parente = this (QObject)
    core::AuditManager *m_auditManager = nullptr;             // parente = this (QObject)
    core::PermissionManager *m_permissionManager = nullptr; // parente = this (QObject)
    network::VoiceService *m_voiceService = nullptr;        // parente = this (QObject)
    core::CallHistoryManager *m_callHistoryManager = nullptr; // parente = this (QObject)
    core::SharedFolderManager *m_sharedFolderManager = nullptr; // parente = this (QObject)
    core::sync::SyncEngine *m_syncEngine = nullptr;             // parente = this (QObject)
    core::sync::FolderSyncService *m_folderSyncService = nullptr; // parente = this (QObject)
};

#endif // APP_APPLICATION_H
