#include "Application.h"

#include <QDebug>

#include "DatabaseManager.h"
#include "UserManager.h"
#include "Discovery/DiscoveryService.h"
#include "Discovery/PeersModel.h"

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

    m_databaseManager = std::make_unique<database::DatabaseManager>();
    if (!m_databaseManager->open()) {
        // On ne bloque pas le demarrage : UserManager signale proprement
        // l'indisponibilite de la base a la connexion (voir loginFailed).
        qWarning() << "Impossible d'ouvrir la base de donnees :" << m_databaseManager->lastError();
    }

    qDebug() << "Base de donnees utilisee :" << m_databaseManager->databaseFilePath();

    m_userManager = new core::UserManager(m_databaseManager.get(), this);

    // Seed du compte admin par defaut (dev/demo), tant qu'aucun ecran
    // d'inscription n'existe. Le hash est toujours produit par
    // core::PasswordHasher (salt aleatoire) : jamais de valeur figee
    // dans les migrations SQL.
    if (m_userManager->allUsers().empty()) {
        const auto admin = m_userManager->createUser(QStringLiteral("admin"), QStringLiteral("admin123"), /*isAdmin=*/true);
        if (!admin.has_value()) {
            qWarning() << "Impossible de creer le compte admin par defaut (code erreur :"
                       << static_cast<int>(m_userManager->lastError()) << ")";
        }
    }

    // Demarre la decouverte reseau (issue #9) et branche le modele QML
    // (PeersModel) qui alimentera UsersView.qml en temps reel (issue #17).
    m_discoveryService = new network::DiscoveryService(this);
    m_peersModel = new network::PeersModel(m_discoveryService, this);

    // Renomme l'annonce avec le nom d'utilisateur connecte des qu'une
    // authentification reussit (avant cela, le hostname sert de nom par
    // defaut, cf. DiscoveryService::DiscoveryService).
    if (m_userManager) {
        connect(m_userManager, &core::UserManager::authenticationChanged, m_discoveryService,
                [this]() {
                    const QString username = m_userManager->currentUsername();
                    if (!username.isEmpty())
                        m_discoveryService->setLocalName(username);
                });
    }

    if (!m_discoveryService->start()) {
        qWarning() << "Impossible de demarrer DiscoveryService (port deja utilise ?)";
    }
}

core::UserManager *Application::userManager() const
{
    return m_userManager;
}

network::PeersModel *Application::peersModel() const
{
    return m_peersModel;
}