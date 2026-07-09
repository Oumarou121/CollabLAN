#include "Application.h"

#include <QDebug>

#include "DatabaseManager.h"
#include "UserManager.h"

Application::Application(QObject *parent)
    : QObject(parent)
{
}

Application::~Application() = default;

void Application::initialize()
{
    // TODO:
    // - charger les parametres (SettingsService)
    // - initialiser la securite (Security)
    // - demarrer la decouverte reseau (Discovery)

    m_databaseManager = std::make_unique<database::DatabaseManager>();
    if (!m_databaseManager->open()) {
        // On ne bloque pas le demarrage : UserManager signale proprement
        // l'indisponibilite de la base a la connexion (voir loginFailed).
        qWarning() << "Impossible d'ouvrir la base de donnees :" << m_databaseManager->lastError();
    }

    m_userManager = new core::UserManager(m_databaseManager.get(), this);
}

core::UserManager *Application::userManager() const
{
    return m_userManager;
}
