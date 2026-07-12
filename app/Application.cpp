#include "Application.h"

#include <QDebug>

#include "DatabaseManager.h"
#include "UserManager.h"
#include "Discovery/DiscoveryService.h"
#include "Discovery/PeersModel.h"
#include "SharedFolderManager.h"
#include "SharedFoldersModel.h"
#include "SyncEngine.h"
#include "SyncHistoryService.h"
#include "Sync/SyncNetworkService.h"

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

    setupSharedFolders();
}

void Application::setupSharedFolders()
{
    m_sharedFolderManager = new core::SharedFolderManager(m_databaseManager.get(), this);
    m_sharedFoldersModel = new core::SharedFoldersModel(m_sharedFolderManager, m_databaseManager.get(), this);
    m_syncHistoryService = new core::SyncHistoryService(m_databaseManager.get(), this);

    m_syncEngine = new core::SyncEngine(m_databaseManager.get(), m_discoveryService->localId(), this);
    m_syncNetworkService = new network::SyncNetworkService(m_discoveryService->localId(), m_discoveryService->localName(), this);

    // Surveille tous les dossiers deja actifs au demarrage.
    for (const auto &folder : m_sharedFolderManager->activeFolders()) {
        m_syncEngine->attachFolder(folder);
    }

    // Un nouveau dossier partage est immediatement surveille ; un dossier
    // dont le partage est desactive n'est plus suivi.
    connect(m_sharedFolderManager, &core::SharedFolderManager::folderCreated, m_syncEngine, [this](const models::SharedFolder &folder) {
        m_syncEngine->attachFolder(folder);
    });
    connect(m_sharedFolderManager, &core::SharedFolderManager::folderShared, m_syncEngine, [this](const models::SharedFolder &folder) {
        m_syncEngine->attachFolder(folder);
    });
    connect(m_sharedFolderManager, &core::SharedFolderManager::folderRemoved, m_syncEngine, [this](int folderId) {
        m_syncEngine->detachFolder(folderId);
    });

    // Changement local detecte -> diffusion immediate aux postes connectes
    // (Phase 7 : synchronisation en temps reel).
    connect(m_syncEngine, &core::SyncEngine::localFileChanged, m_syncNetworkService,
            [this](int /*folderId*/, const QString &folderName, const QString &relativePath, const QString &hash, qint64 size, int version) {
                m_syncNetworkService->broadcastFileInfo(folderName, relativePath, hash, size, version);
            });
    connect(m_syncEngine, &core::SyncEngine::localFileDeleted, m_syncNetworkService,
            [this](int /*folderId*/, const QString &folderName, const QString &relativePath, int version) {
                m_syncNetworkService->broadcastDeleteFile(folderName, relativePath, version);
            });

    // Metadonnees recues d'un poste distant -> appliquees en base locale
    // (le contenu du fichier suit via FILE_REQUEST/FILE_CHUNK, non
    // automatise ici : declenche depuis l'UI ou une synchronisation
    // complete ulterieure).
    connect(m_syncNetworkService, &network::SyncNetworkService::fileInfoReceived, m_syncEngine,
            [this](const QString &peerId, const QString &folderName, const QString &relativePath, const QString &hash, qint64 size, int version) {
                for (const auto &folder : m_sharedFolderManager->activeFolders()) {
                    if (folder.name() == folderName) {
                        m_syncEngine->applyRemoteFileInfo(folder.id(), relativePath, hash, size, version, peerId);
                        break;
                    }
                }
            });
    connect(m_syncNetworkService, &network::SyncNetworkService::deleteFileReceived, m_syncEngine,
            [this](const QString &/*peerId*/, const QString &folderName, const QString &relativePath, int version) {
                for (const auto &folder : m_sharedFolderManager->activeFolders()) {
                    if (folder.name() == folderName) {
                        m_syncEngine->applyRemoteDelete(folder.id(), relativePath, version);
                        break;
                    }
                }
            });

    // Se connecte automatiquement a tout poste decouvert sur le reseau
    // local pour maintenir un canal de synchronisation permanent.
    connect(m_discoveryService, &network::DiscoveryService::peerDiscovered, m_syncNetworkService,
            [this](const network::DiscoveredPeer &peer) {
                m_syncNetworkService->connectToPeer(peer.id, peer.address, network::SyncNetworkService::kDefaultPort);
            });

    if (!m_syncNetworkService->start()) {
        qWarning() << "Impossible de demarrer SyncNetworkService (port deja utilise ?)";
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

core::SharedFolderManager *Application::sharedFolderManager() const
{
    return m_sharedFolderManager;
}

core::SharedFoldersModel *Application::sharedFoldersModel() const
{
    return m_sharedFoldersModel;
}

core::SyncHistoryService *Application::syncHistoryService() const
{
    return m_syncHistoryService;
}