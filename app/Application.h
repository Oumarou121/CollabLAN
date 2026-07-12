#ifndef APP_APPLICATION_H
#define APP_APPLICATION_H

#include <QObject>
#include <memory>

namespace database {
class DatabaseManager;
}

namespace core {
class UserManager;
}

namespace network {
class DiscoveryService;
class PeersModel;
class SyncNetworkService;
class SecurityService;
}

namespace core {
class SharedFolderManager;
class SharedFoldersModel;
class SyncEngine;
class SyncHistoryService;
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

    // Expose au bootstrap QML (voir app/main.cpp) l'objet a brancher sur
    // LoginView.qml via setContextProperty("userManager", ...).
    core::UserManager *userManager() const;

    // Expose au bootstrap QML (app/main.cpp) le modele des postes detectes,
    // a brancher sur UsersView.qml via setContextProperty("peersModel", ...)
    // (issue #17).
    network::PeersModel *peersModel() const;

    // Expose au bootstrap QML les composants de la fonctionnalite "Shared
    // Folder" : gestion CRUD des dossiers (SharedFolderView.qml) et
    // historique de synchronisation.
    core::SharedFolderManager *sharedFolderManager() const;
    core::SharedFoldersModel *sharedFoldersModel() const;
    core::SyncHistoryService *syncHistoryService() const;

    // Expose au bootstrap QML la gestion des postes de confiance TLS
    // (ui/Admin) : le SyncNetworkService delegue a sa propre instance de
    // TlsHandshakeService, dont la liste de confiance persiste sur disque.
    network::SyncNetworkService *syncNetworkService() const;

private:
    void setupSharedFolders();

    // TODO: instancier ici les autres services (Security, Settings...)
    std::unique_ptr<database::DatabaseManager> m_databaseManager;
    core::UserManager *m_userManager = nullptr;               // parente = this (QObject)
    network::DiscoveryService *m_discoveryService = nullptr;  // parente = this (QObject)
    network::PeersModel *m_peersModel = nullptr;               // parente = this (QObject)

    core::SharedFolderManager *m_sharedFolderManager = nullptr;   // parente = this (QObject)
    core::SharedFoldersModel *m_sharedFoldersModel = nullptr;     // parente = this (QObject)
    core::SyncEngine *m_syncEngine = nullptr;                     // parente = this (QObject)
    core::SyncHistoryService *m_syncHistoryService = nullptr;     // parente = this (QObject)
    std::unique_ptr<network::SecurityService> m_securityService;
    network::SyncNetworkService *m_syncNetworkService = nullptr;  // parente = this (QObject)
};

#endif // APP_APPLICATION_H
