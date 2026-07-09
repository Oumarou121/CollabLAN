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

private:
    // TODO: instancier ici les autres services (Discovery, Security, Settings...)
    std::unique_ptr<database::DatabaseManager> m_databaseManager;
    core::UserManager *m_userManager = nullptr; // parente = this (QObject)
};

#endif // APP_APPLICATION_H
