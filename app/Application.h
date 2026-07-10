#ifndef APP_APPLICATION_H
#define APP_APPLICATION_H

#include <QObject>
#include <QString>
#include <memory>

namespace database {
class DatabaseManager;
}

namespace core {
class UserManager;
class MessagingManager;
class GroupManager;
class TransferManager;
class NotificationManager;
}

namespace network {
class DiscoveryService;
class PeersModel;
class MessagingService;
class MessagingServer;
class SecurityService;
class TransferService;
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

    // Expose au bootstrap QML le NotificationManager pour les notifications.
    core::NotificationManager *notificationManager() const;

    // Expose au bootstrap QML le TransferService pour le transfert de fichiers (issue #53).
    network::TransferService *transferService() const;

    // Expose au bootstrap QML le TransferManager pour l'historique des transferts (issue #55).
    core::TransferManager *transferManager() const;

private:
    // TODO: instancier ici les autres services (Security, Settings...)
    std::unique_ptr<database::DatabaseManager> m_databaseManager;
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
    core::TransferManager *m_transferManager = nullptr;       // parente = this (QObject)
};

#endif // APP_APPLICATION_H
