#ifndef APP_APPLICATION_H
#define APP_APPLICATION_H

#include <QObject>
#include <QString>
#include <QVariant>
#include <memory>

namespace database {
class DatabaseManager;
class ServerElectionRepository;
class SyncLogRepository;
}

namespace core {
class UserManager;
class MessagingManager;
class GroupManager;
class TransferManager;
class NotificationManager;
class AuditManager;
class PermissionManager;
}

namespace network {
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
 * @brief Point d'entree logique de CollabLAN : initialise les services
 * (reseau, base de donnees, parametres) au demarrage de l'application.
 */
class Application : public QObject
{
    Q_OBJECT

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

    // Expose au bootstrap QML (voir app/main.cpp) l'objet a brancher sur
    // LoginView.qml via setContextProperty("userManager", ...).
    core::UserManager *userManager() const;

    // Expose au bootstrap QML (app/main.cpp) le modele des postes detectes,
    // a brancher sur UsersView.qml via setContextProperty("peersModel", ...)
    // (issue #17).
    network::PeersModel *peersModel() const;

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

    // Expose le DatabaseManager pour les services qui en ont besoin (ex: SettingsService).
    database::DatabaseManager *databaseManager() const;

private:
    bool shouldWriteSyncLog() const;
    void appendSyncLogEntry(const QString &tableName, const QString &recordUuid,
                            const QString &operation, const QString &payloadJson);
    void appendMessageSyncLog(const models::Message &message);
    void appendGroupSyncLog(const models::Group &group, const QString &operation);
    void appendUserSyncLog(const models::User &user, const QString &operation);

    /// Uuid de l'utilisateur local d'id donne (chaine vide si introuvable).
    /// Utilise pour serialiser des references stables (senderUuid, ownerUuid,
    /// memberUuids) dans les payloads SyncLog de Messages/Groups/GroupMembers,
    /// plutot que l'id local AUTOINCREMENT qui ne coincide pas forcement
    /// entre postes (cf. HYBRID_SERVER_FAILOVER.md et la note de
    /// SyncLogRepository::applyUserEntry).
    QString userUuidForId(qint64 userId) const;

    /// Uuid de la Conversation locale d'id donne (chaine vide si introuvable).
    QString conversationUuidForId(qint64 conversationId) const;

    // TODO: instancier ici les autres services (Security, Settings...)
    std::unique_ptr<database::DatabaseManager> m_databaseManager;
    std::unique_ptr<database::ServerElectionRepository> m_serverElectionRepository;
    std::unique_ptr<database::SyncLogRepository> m_syncLogRepository;
    core::UserManager *m_userManager = nullptr;               // parente = this (QObject)
    core::MessagingManager *m_messagingManager = nullptr;     // parente = this (QObject)
    core::GroupManager *m_groupManager = nullptr;             // parente = this (QObject)
    core::NotificationManager *m_notificationManager = nullptr; // parente = this (QObject)
    network::DiscoveryService *m_discoveryService = nullptr;  // parente = this (QObject)
    network::PeersModel *m_peersModel = nullptr;               // parente = this (QObject)
    network::SecurityService *m_securityService = nullptr;    // parente = this (QObject)
    network::MessagingService *m_messagingService = nullptr;  // parente = this (QObject)
    network::MessagingServer *m_messagingServer = nullptr;    // parente = this (QObject)
    network::TransferService *m_transferService = nullptr;    // parente = this (QObject)
    network::ElectionService *m_electionService = nullptr;      // parente = this (QObject)
    network::SyncService *m_syncService = nullptr;              // parente = this (QObject)
    core::TransferManager *m_transferManager = nullptr;       // parente = this (QObject)
    services::AudioService *m_audioService = nullptr;         // parente = this (QObject)
    core::AuditManager *m_auditManager = nullptr;             // parente = this (QObject)
    core::PermissionManager *m_permissionManager = nullptr; // parente = this (QObject)
    network::VoiceService *m_voiceService = nullptr;        // parente = this (QObject)
};

#endif // APP_APPLICATION_H