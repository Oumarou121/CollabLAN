#include "Application.h"

#include <QDebug>
#include <QHostAddress>

#include "DatabaseManager.h"
#include "UserManager.h"
#include "MessagingManager.h"
#include "GroupManager.h"
#include "TransferManager.h"
#include "NotificationManager.h"
#include "Discovery/DiscoveryService.h"
#include "Discovery/PeersModel.h"
#include "Messaging/MessagingService.h"
#include "Messaging/MessagingServer.h"
#include "Security/SecurityService.h"
#include "Transfer/TransferService.h"
#include "AudioService.h"

Application::Application(QObject *parent)
    : QObject(parent)
{
}

Application::~Application() = default;

void Application::initialize()
{
    initialize(12345); // Port par défaut
}

void Application::initialize(quint16 messagingServerPort)
{
    initialize(messagingServerPort, QString());
}

void Application::initialize(quint16 messagingServerPort, const QString &dbFilePath)
{
    // TODO:
    // - charger les parametres (SettingsService)
    // - initialiser la securite (Security)

    m_databaseManager = std::make_unique<database::DatabaseManager>();
    if (!m_databaseManager->open(dbFilePath)) {
        // On ne bloque pas le demarrage : UserManager signale proprement
        // l'indisponibilite de la base a la connexion (voir loginFailed).
        qWarning() << "Impossible d'ouvrir la base de donnees :" << m_databaseManager->lastError();
    }

    qDebug() << "Base de donnees utilisee :" << m_databaseManager->databaseFilePath();

    m_userManager = new core::UserManager(m_databaseManager.get(), this);

    // Initialiser le MessagingManager pour la messagerie
    m_messagingManager = new core::MessagingManager(m_databaseManager.get(), this);

    // Initialiser le GroupManager pour les groupes
    m_groupManager = new core::GroupManager(m_databaseManager.get(), this);

    // Initialiser le SecurityService pour la sécurité TLS
    m_securityService = new network::SecurityService();
    if (!m_securityService->initialize()) {
        qWarning() << "Impossible d'initialiser SecurityService";
    }

    // Initialiser le MessagingService pour la messagerie réseau
    m_messagingService = new network::MessagingService(m_securityService, this);

    // Initialiser le MessagingServer pour recevoir les messages
    m_messagingServer = new network::MessagingServer(m_securityService, this);
    if (!m_messagingServer->start(messagingServerPort)) {
        qWarning() << "Impossible de démarrer MessagingServer";
    }

    // Initialiser le NotificationManager pour les notifications
    m_notificationManager = new core::NotificationManager(this);

    // Initialiser le TransferService pour le transfert de fichiers par
    // blocs (issue #53). Ecoute sur le port de messagerie + 1 par
    // defaut, afin que plusieurs instances lancees localement (tests)
    // n'entrent pas en conflit entre elles.
    m_transferService = new network::TransferService(this);
    if (!m_transferService->start(static_cast<quint16>(messagingServerPort + 1))) {
        qWarning() << "Impossible de demarrer TransferService";
    }

    // Initialiser le TransferManager : persiste l'historique des
    // transferts (fichier, expediteur, destinataire, statut) en base a
    // chaque transfert emis/recu par TransferService, et le rend
    // consultable meme apres redemarrage de l'application (issue #55).
    m_transferManager = new core::TransferManager(m_databaseManager.get(), this);
    m_transferManager->setTransferService(m_transferService);

    // Initialiser l'AudioService pour les sons de notification
    // (message, transfert, appel - issue #56).
    m_audioService = new services::AudioService(this);

    // Point d'entree unique pour toast + son (issue #58) : chaque
    // evenement notifiable (message, transfert, connexion/deconnexion)
    // passe par NotificationManager::notificationRequested, qui pilote
    // ici le son coherent avec la categorie de l'evenement ; l'UI QML
    // (ToastHost.qml) ecoute le meme signal pour afficher le toast.
    connect(m_notificationManager, &core::NotificationManager::notificationRequested,
            m_audioService, [this](const QString &title, const QString &message, const QString &category) {
                Q_UNUSED(title);
                Q_UNUSED(message);
                if (category == QStringLiteral("message")) {
                    m_audioService->playMessageSound();
                } else if (category == QStringLiteral("transfer")) {
                    m_audioService->playTransferSound();
                }
                // "connection"/"disconnection" : toast silencieux (pas de son
                // dedie ; playCallSound() est reserve aux appels entrants).
            });

    // Un transfert termine ou en echec declenche une notification
    // (toast + son "transfert").
    connect(m_transferService, &network::TransferService::transferCompleted,
            m_notificationManager, &core::NotificationManager::onTransferCompleted);
    connect(m_transferService, &network::TransferService::transferFailed,
            m_notificationManager, &core::NotificationManager::onTransferFailed);

    // NOTE: VoiceService (appels vocaux) n'est pas encore implemente ;
    // brancher AudioService::playCallSound() sur son signal d'appel
    // entrant des que ce service existera.

    // Connecter les services au MessagingManager
    m_messagingManager->setMessagingService(m_messagingService);
    m_messagingManager->setMessagingServer(m_messagingServer);
    m_messagingManager->setNotificationManager(m_notificationManager);

    // Connecter MessagingServer à MessagingManager pour traiter les messages reçus
    connect(m_messagingServer, &network::MessagingServer::messageReceived,
            m_messagingManager, [this](const QString &message, const QHostAddress &senderAddress) {
                Q_UNUSED(senderAddress)
                if (!m_messagingManager->receiveMessage(message)) {
                    qWarning() << "Message reseau ignore (payload invalide) :" << message;
                }
            });

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

    // Un poste qui apparait/disparait du reseau local declenche une
    // notification "connexion"/"deconnexion" (issue #58). peerDiscovered
    // n'est emis qu'une fois par poste (premiere detection) et peerLost
    // apres expiration du timeout d'annonce (cf. DiscoveryService.h) :
    // pas de spam a chaque annonce UDP periodique (peerUpdated n'est pas
    // utilise ici).
    connect(m_discoveryService, &network::DiscoveryService::peerDiscovered,
            m_notificationManager, [this](const network::DiscoveredPeer &peer) {
                m_notificationManager->onPeerConnected(peer.name);
            });
    connect(m_discoveryService, &network::DiscoveryService::peerLost,
            m_notificationManager, [this](const network::DiscoveredPeer &peer) {
                m_notificationManager->onPeerDisconnected(peer.name);
            });

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

core::MessagingManager *Application::messagingManager() const
{
    return m_messagingManager;
}

core::GroupManager *Application::groupManager() const
{
    return m_groupManager;
}

network::SecurityService *Application::securityService() const
{
    return m_securityService;
}

network::MessagingService *Application::messagingService() const
{
    return m_messagingService;
}

network::MessagingServer *Application::messagingServer() const
{
    return m_messagingServer;
}

core::NotificationManager *Application::notificationManager() const
{
    return m_notificationManager;
}

network::TransferService *Application::transferService() const
{
    return m_transferService;
}

core::TransferManager *Application::transferManager() const
{
    return m_transferManager;
}

services::AudioService *Application::audioService() const
{
    return m_audioService;
}