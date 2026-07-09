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

private:
    // TODO: instancier ici les autres services (Security, Settings...)
    std::unique_ptr<database::DatabaseManager> m_databaseManager;
    core::UserManager *m_userManager = nullptr;               // parente = this (QObject)
    network::DiscoveryService *m_discoveryService = nullptr;  // parente = this (QObject)
    network::PeersModel *m_peersModel = nullptr;               // parente = this (QObject)
};

#endif // APP_APPLICATION_H
