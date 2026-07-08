#include "Application.h"

Application::Application(QObject *parent)
    : QObject(parent)
{
}

Application::~Application()
{
}

void Application::initialize()
{
    // TODO:
    // - charger les parametres (SettingsService)
    // - initialiser la securite (Security)
    // - demarrer la decouverte reseau (Discovery)
    // - ouvrir la base de donnees (DatabaseManager)
}
