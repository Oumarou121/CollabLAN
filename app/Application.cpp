#include "Application.h"

#include <QDebug>
#include <QHostAddress>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QTimer>
#include <QSqlQuery>
#include <QVariantMap>
#include <QVariantList>
#include <algorithm>
#include <utility>

#include "DatabaseManager.h"
#include "database/Repositories/SettingsRepository.h"
#include "models/Settings.h"
#include "UserManager.h"
#include "MessagingManager.h"
#include "GroupManager.h"
#include "TransferManager.h"
#include "NotificationManager.h"
#include "AuditManager.h"
#include "CallHistoryManager.h"
#include "SharedFolderManager.h"
#include "core/Sync/SyncEngine.h"
#include "PermissionManager.h"
#include "Discovery/DiscoveryService.h"
#include "Discovery/PeersModel.h"
#include "Messaging/MessagingService.h"
#include "Messaging/MessagingServer.h"
#include "Security/SecurityService.h"
#include "Transfer/TransferService.h"
#include "Voice/VoiceService.h"
#include "AudioService.h"
#include "Election/ElectionService.h"
#include "Sync/SyncService.h"
#include "core/Sync/FolderSyncService.h"
#include "database/Repositories/ServerElectionRepository.h"
#include "database/Repositories/SyncLogRepository.h"
#include "database/Repositories/GroupRepository.h"
#include "models/ServerElection.h"
#include "models/Message.h"
#include "models/Group.h"
#include "models/SyncLogEntry.h"
#include <QSysInfo>

namespace {
// Delai au-dela duquel un serveur annonce par UDP mais injoignable en TLS est
// rejete (voir ElectionService::setRequireValidatedServer). Volontairement plus
// court que le delai de heartbeat (15 s) pour qu une election puisse suivre.
constexpr int kServerValidationTimeoutMs = 8000;
} // namespace

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

void Application::setDiscoveryPort(quint16 port)
{
    if (m_discoveryService) {
        qWarning() << "Application::setDiscoveryPort: appele apres initialize(), "
                       "sans effet (DiscoveryService deja demarre) - appeler avant initialize().";
        return;
    }
    m_discoveryPortOverride = port;
}

void Application::initialize(quint16 messagingServerPort, const QString &dbFilePath)
{
    initialize(messagingServerPort, dbFilePath, QString(), -1);
}

void Application::initialize(quint16 messagingServerPort, const QString &dbFilePath,
                              const QString &roleOverride, int priorityWeightOverride)
{
    initialize(messagingServerPort, dbFilePath, roleOverride, priorityWeightOverride, 0);
}

void Application::initialize(quint16 messagingServerPort, const QString &dbFilePath,
                              const QString &roleOverride, int priorityWeightOverride,
                              quint16 electionPort)
{
    // TODO:
    // - charger les parametres (SettingsService)
    // - initialiser la securite (Security)

    // Nom de connexion Qt SQL unique par instance : par defaut DatabaseManager
    // utilise "localink_db" pour tout le monde, ce qui casse silencieusement
    // (connexion partagee/ecrasee) des qu'on instancie plusieurs Application
    // dans le meme process, comme le font les tests d'integration multi-
    // postes (HYBRID_SERVER_FAILOVER.md section 9, etape 3).
    m_databaseManager = std::make_unique<database::DatabaseManager>(
        QStringLiteral("localink_db_%1").arg(reinterpret_cast<quintptr>(this)));
    if (!m_databaseManager->open(dbFilePath)) {
        // On ne bloque pas le demarrage : UserManager signale proprement
        // l'indisponibilite de la base a la connexion (voir loginFailed).
        qWarning() << "Impossible d'ouvrir la base de donnees :" << m_databaseManager->lastError();
    }

    qDebug() << "Base de donnees utilisee :" << m_databaseManager->databaseFilePath();

    m_userManager = new core::UserManager(m_databaseManager.get(), this);
    // Ecran "premier administrateur" : a reevaluer des que la liste des comptes change
    // (creation locale, comptes recus par synchronisation).
    connect(m_userManager, &core::UserManager::usersChanged, this, &Application::initialAdminStateChanged);
    connect(m_userManager, &core::UserManager::userCreated, this, &Application::initialAdminStateChanged);

    // Initialiser le MessagingManager pour la messagerie
    m_messagingManager = new core::MessagingManager(m_databaseManager.get(), this);

    // Initialiser le GroupManager pour les groupes
    m_groupManager = new core::GroupManager(m_databaseManager.get(), this);

    // Initialiser le SecurityService pour la sécurité TLS
    m_securityService = new network::SecurityService(
    m_databaseManager->databaseFilePath() + QStringLiteral(".security"));
    if (!m_securityService->initialize()) {
        qWarning() << "Impossible d'initialiser SecurityService";
    }

    // Initialiser le MessagingService pour la messagerie réseau
    m_messagingService = new network::MessagingService(m_securityService, this);
    connect(m_messagingService, &network::MessagingService::serverCertificateTrustRequired,
            this, [this](const QString &fingerprint, const QString &address, quint16 port) {
        m_pendingServerFingerprint = fingerprint;
        m_pendingServerAddress = address;
        m_pendingServerPort = port;
        qWarning() << "Certificat serveur a approuver localement:" << fingerprint
                   << "pour" << address << ':' << port;
        emit pendingServerChanged();
    });
    connect(m_messagingService, &network::MessagingService::connected, this, [this]() {
        if (m_pendingServerFingerprint.isEmpty()) return;
        m_pendingServerFingerprint.clear();
        m_pendingServerAddress.clear();
        m_pendingServerPort = 0;
        // Le certificat vient d'etre approuve (ou une connexion a reussi
        // entre-temps) : plus de raison d'attendre le reste du cooldown
        // avant la prochaine reconciliation eventuelle.
        m_lastReconciliationAttemptMs = 0;
        emit pendingServerChanged();
    });

    // Initialiser le MessagingServer pour recevoir les messages.
    // Le démarrage effectif (start/stop) est désormais piloté par le rôle
    // courant (ElectionService::roleChanged, voir plus bas) : seuls les
    // rôles Server et TempServer écoutent réellement sur ce port ; un
    // poste Client reste silencieux jusqu'à ce qu'il soit éventuellement
    // promu (architecture hybride, HYBRID_SERVER_FAILOVER.md section 3/9).
    m_messagingServer = new network::MessagingServer(m_securityService, this);

    // Initialiser l'election serveur + la reconciliation post-panne.
    m_serverElectionRepository = std::make_unique<database::ServerElectionRepository>(m_databaseManager->database());
    m_syncLogRepository = std::make_unique<database::SyncLogRepository>(m_databaseManager->database());

    const models::ServerElection electionState = m_serverElectionRepository->current();

    // Forçage optionnel du rôle/priority_weight (CLI --role / --priority-weight,
    // cf. app/main.cpp) : utile pour scripter des scénarios de test multi-
    // instances sans passer par AdminView.qml. On persiste tout de suite le
    // résultat en base pour que ce soit lui, et non l'ancien état lu ci-
    // dessus, qui serve de référence pour tout le reste de initialize().
    models::ServerElection effectiveElectionState = electionState;
    if (!roleOverride.isEmpty()) {
        const models::ServerRole forcedRole = models::serverRoleFromString(roleOverride);
        effectiveElectionState.setCurrentRole(forcedRole);
        qDebug() << "Rôle forcé via --role :" << models::serverRoleToString(forcedRole);
    }
    if (priorityWeightOverride >= 0) {
        effectiveElectionState.setPriorityWeight(priorityWeightOverride);
        qDebug() << "priority_weight forcé via --priority-weight :" << priorityWeightOverride;
    }
    if (!roleOverride.isEmpty() || priorityWeightOverride >= 0) {
        if (!m_serverElectionRepository->save(effectiveElectionState)) {
            qWarning() << "Impossible de persister le forçage de rôle/priority_weight :"
                       << m_serverElectionRepository->lastError();
        }
    }

    m_electionService = new network::ElectionService(this);
    m_electionService->setInitialState(effectiveElectionState.currentRole(), effectiveElectionState.epoch());
    m_electionService->setPriorityWeight(effectiveElectionState.priorityWeight());
    if (electionPort != 0) {
        m_electionService->setPort(electionPort);
    }
    // Corrige un bug silencieux : sans ceci, les autres postes supposaient
    // que CE poste (une fois Server/TempServer) écoutait sur LEUR PROPRE
    // messagingServerPort au lieu du port réellement utilisé ici (--port).
    // Inoffensif tant que tout le monde garde le port 12345 par défaut,
    // mais casse la connexion dès qu'une instance utilise un port différent
    // (cf. ElectionService::messagingPort()/activeServerPort()).
    m_electionService->setMessagingPort(messagingServerPort);

    // CORRECTIF : GroupManager::receiveGroupCreated a besoin de l'uuid de
    // CETTE machine pour renseigner SyncLog.origin_machine_id (NOT NULL)
    // lors de l'insertion d'un groupe recu en temps reel (le payload
    // "group_created" lui-meme ne transporte pas ce champ, contrairement
    // aux entrees d'un sync_batch). Sans cet appel, receiveGroupCreated()
    // echouait systematiquement (violation de contrainte) puis, apres
    // durcissement du garde-fou, echouait silencieusement au lieu de
    // planter -- dans les deux cas le groupe restait invisible tant que
    // la reconciliation periodique ne le rattrapait pas.
    if (m_groupManager) {
        m_groupManager->setLocalMachineUuid(m_electionService->localMachineUuid());
    }

    // setInitialState() ne déclenche pas roleChanged (c'est un simple
    // réglage d'état avant démarrage) : si ce poste redémarre alors qu'il
    // était Server ou TempServer, il faut donc démarrer MessagingServer
    // explicitement ici plutôt que d'attendre un roleChanged qui ne viendra
    // pas. Le cas Client n'a rien de spécial à faire au démarrage (voir
    // roleChanged plus bas pour la reconnexion vers le serveur actif).
    if (effectiveElectionState.currentRole() == models::ServerRole::Server
        || effectiveElectionState.currentRole() == models::ServerRole::TempServer) {
        if (!m_messagingServer->start(messagingServerPort)) {
            qWarning() << "Impossible de démarrer MessagingServer au démarrage pour le rôle"
                       << models::serverRoleToString(effectiveElectionState.currentRole());
        }
    }

    m_syncService = new network::SyncService(m_syncLogRepository.get(), this);
    m_syncService->setMessagingServer(m_messagingServer);
    m_syncService->setMessagingService(m_messagingService);
    // Permet au sync_batch de rattraper aussi ServerElectionLog (entrees
    // jamais recues via broadcastServerElectionEvent faute de pair connecte
    // au bon moment, cf. HYBRID_SERVER_FAILOVER.md section 7.2).
    m_syncService->setServerElectionRepository(m_serverElectionRepository.get());

    connect(m_messagingManager, &core::MessagingManager::messageSent,
            this, &Application::appendMessageSyncLog);
    connect(m_messagingManager, &core::MessagingManager::messageReceived,
            this, &Application::appendMessageSyncLog);

    // CORRECTIF : un message temps reel dont l'expediteur n'est pas encore
    // connu localement (Users pas encore reconcilie) etait jusqu'ici perdu
    // pour de bon (cf. MessagingManager::unresolvedSenderMessage). On
    // reagit en demandant une reconciliation complete au serveur actif
    // (deja connecte, puisque c'est par lui que ce message temps reel
    // vient d'arriver), puis en rejouant le payload une fois la
    // reconciliation terminee -- l'expediteur devrait alors etre connu.
    connect(m_messagingManager, &core::MessagingManager::unresolvedSenderMessage,
            this, [this](const QString &senderUuid, const QString &jsonPayload) {
                m_pendingUnresolvedMessages.append(jsonPayload);
                qWarning() << "Message en attente de reconciliation pour sender inconnu"
                           << senderUuid << "- declenchement d'une reconciliation";
                if (m_syncService && m_messagingService && m_messagingService->isConnected()
                    && m_electionService) {
                    m_syncService->requestReconciliation(m_electionService->epoch(),
                                                          m_electionService->localMachineUuid());
                }
            });

    // Handshake d'identification (issue #2) : des que la connexion sortante
    // vers le serveur actif est etablie ET/OU des qu'un utilisateur se
    // connecte localement, on informe le serveur de notre userUuid. Les
    // deux evenements (connexion reseau, login) peuvent survenir dans
    // n'importe quel ordre selon le contexte de demarrage ; sendIdentifyIfReady()
    // ne fait rien tant que les deux conditions ne sont pas reunies.
    connect(m_messagingService, &network::MessagingService::connected,
            this, &Application::sendIdentifyIfReady);
    if (m_userManager) {
        connect(m_userManager, &core::UserManager::loginSucceeded,
                this, &Application::sendIdentifyIfReady);
    }

    connect(m_groupManager, &core::GroupManager::groupCreated,
            this, [this](const models::Group &group) {
                appendGroupSyncLog(group, models::SyncOperation::Insert);
            });
    connect(m_groupManager, &core::GroupManager::memberAdded,
            this, [this](qint64 groupId, qint64 memberId) {
                // groupUuid/memberUuid : references stables inter-postes
                // (cf. migration 011 / applyGroupMemberEntry), l'id local
                // de groupe ou d'utilisateur n'ayant aucune raison de
                // coincider entre postes.
                database::GroupRepository groupRepo(m_databaseManager.get());
                const auto group = groupRepo.getById(groupId);
                const QString groupUuid = group.has_value() ? group->uuid() : QString();
                const QString memberUuid = userUuidForId(memberId);
                if (groupUuid.isEmpty() || memberUuid.isEmpty()) {
                    qWarning() << "memberAdded : group/user non resolu en uuid, entree ignoree";
                    return;
                }
                QJsonObject payload;
                payload.insert(QStringLiteral("groupUuid"), groupUuid);
                payload.insert(QStringLiteral("memberUuid"), memberUuid);
                appendSyncLogEntry(QStringLiteral("GroupMembers"),
                                   QStringLiteral("%1:%2").arg(groupUuid, memberUuid),
                                   models::SyncOperation::Insert,
                                   QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
            });
    connect(m_groupManager, &core::GroupManager::memberRemoved,
            this, [this](qint64 groupId, qint64 memberId) {
                database::GroupRepository groupRepo(m_databaseManager.get());
                const auto group = groupRepo.getById(groupId);
                const QString groupUuid = group.has_value() ? group->uuid() : QString();
                const QString memberUuid = userUuidForId(memberId);
                if (groupUuid.isEmpty() || memberUuid.isEmpty()) {
                    qWarning() << "memberRemoved : group/user non resolu en uuid, entree ignoree";
                    return;
                }
                QJsonObject payload;
                payload.insert(QStringLiteral("groupUuid"), groupUuid);
                payload.insert(QStringLiteral("memberUuid"), memberUuid);
                appendSyncLogEntry(QStringLiteral("GroupMembers"),
                                   QStringLiteral("%1:%2").arg(groupUuid, memberUuid),
                                   models::SyncOperation::Delete,
                                   QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
            });

    connect(m_userManager, &core::UserManager::userCreated,
            this, [this](const models::User &user) {
                appendUserSyncLog(user, models::SyncOperation::Insert);
                broadcastUserEvent(user, models::SyncOperation::Insert);
            });
    connect(m_userManager, &core::UserManager::userUpdated,
            this, [this](const models::User &user) {
                appendUserSyncLog(user, models::SyncOperation::Update);
                broadcastUserEvent(user, models::SyncOperation::Update);
            });
    connect(m_userManager, &core::UserManager::userDeleted,
            this, [this](const QString &uuid, int id) {
                Q_UNUSED(id)
                appendSyncLogEntry(QStringLiteral("Users"), uuid, models::SyncOperation::Delete, QString());
            });
    // --- Validation TLS du resultat d'election ---------------------------
    // Les datagrammes UDP d'election ne sont ni signes ni authentifies :
    // n'importe quelle machine du reseau pouvait diffuser un server_promoted
    // avec un epoch arbitrairement grand et detourner ainsi tous les postes
    // vers elle. Plutot que de signer les paquets (fragmentation UDP, amorcage
    // a froid, rejeu), on valide le RESULTAT : l'annonce n'est qu'une
    // indication, et ElectionService n'applique rien tant que ce poste n'a pas
    // joint le serveur annonce en TLS. MessagingService::connected n'est emis
    // qu'apres verification du certificat du pair contre les machines
    // autorisees (PermissionManager::trustRemoteServerCertificate) : c'est
    // donc lui, et lui seul, qui confirme l'adoption.
    m_electionService->setRequireValidatedServer(true);
    connect(m_electionService, &network::ElectionService::serverEndpointPending,
            this, [this](const QString &machineUuid, const QHostAddress &address, quint16 port) {
                if (address.isNull() || port == 0) {
                    m_electionService->rejectPendingServer(
                        machineUuid, QStringLiteral("adresse ou port de messagerie inconnu"));
                    return;
                }

                if (m_messagingService->isConnected()
                    && m_messagingService->peerAddress() == address
                    && m_messagingService->peerPort() == port) {
                    // Deja connecte a ce poste, donc certificat deja reconnu.
                    m_electionService->confirmPendingServer(machineUuid);
                    return;
                }

                // Objet ephemere porteur des trois issues possibles (succes,
                // erreur, delai depasse) : le detruire deconnecte d'un coup les
                // trois lambdas, sans qu'une annonce ulterieure puisse etre
                // confirmee par la connexion declenchee pour une annonce
                // precedente.
                auto *validation = new QObject(this);
                connect(m_messagingService, &network::MessagingService::connected, validation,
                        [this, machineUuid, validation]() {
                            m_electionService->confirmPendingServer(machineUuid);
                            validation->deleteLater();
                        });
                connect(m_messagingService, &network::MessagingService::error, validation,
                        [this, machineUuid, validation](const QString &reason) {
                            m_electionService->rejectPendingServer(machineUuid, reason);
                            validation->deleteLater();
                        });
                // Sans cette echeance, un serveur annonce qui ne repond jamais
                // laisserait le poste suspendu a une annonce non verifiee : le
                // rejet laisse au contraire le delai de heartbeat declencher une
                // nouvelle election.
                QTimer::singleShot(kServerValidationTimeoutMs, validation,
                                    [this, machineUuid, validation]() {
                    m_electionService->rejectPendingServer(
                        machineUuid, QStringLiteral("delai de validation depasse"));
                    validation->deleteLater();
                });

                m_messagingService->disconnectFromHost();
                if (!m_messagingService->connectToHost(address, port)) {
                    m_electionService->rejectPendingServer(
                        machineUuid, QStringLiteral("connexion au serveur annonce impossible"));
                    validation->deleteLater();
                }
            });
    connect(m_electionService, &network::ElectionService::serverEndpointRejected,
            this, [](const QString &machineUuid, const QString &reason) {
                qWarning() << "Annonce de serveur ignoree (non validee) :" << machineUuid << '-' << reason;
            });

    connect(m_electionService, &network::ElectionService::roleChanged,
            this, &Application::initialAdminStateChanged);
    connect(m_electionService, &network::ElectionService::roleChanged,
            this, [this, messagingServerPort](models::ServerRole newRole, models::ServerRole previousRole) {
                m_serverElectionRepository->updateRoleAndEpoch(newRole, m_electionService->epoch());

                // Pilotage de MessagingServer selon le rôle courant
                // (HYBRID_SERVER_FAILOVER.md section 9, étape 3) :
                //   - Server / TempServer -> on écoute réellement sur ce poste.
                //   - Client              -> on n'écoute pas (on se connecte
                //     au serveur actif via MessagingService à la place).
                const bool shouldListen = (newRole == models::ServerRole::Server
                                            || newRole == models::ServerRole::TempServer);
                if (shouldListen) {
                    if (!m_messagingServer->isRunning() && !m_messagingServer->start(messagingServerPort)) {
                        qWarning() << "Impossible de démarrer MessagingServer pour le rôle"
                                   << models::serverRoleToString(newRole);
                    }
                    // Cas du tout premier poste seul sur le réseau : il démarre
                    // Client par défaut (aucun --role forcé) puis n'est promu
                    // Server/TempServer qu'après le délai d'élection, donc le
                    // seed initial a été sauté. Seul le serveur principal
                    // peut alors initialiser le compte admin ; un TempServer
                    // attend les comptes synchronisés.
                    if (newRole == models::ServerRole::Server)
                        seedDefaultAdminIfNeeded();
                } else {
                    if (m_messagingServer->isRunning()) {
                        m_messagingServer->stop();
                    }

                    // On ne se connecte au serveur actif que si l'on redevient
                    // Client alors qu'on ne l'était pas déjà (transition
                    // TempServer -> Client typiquement, cf. section 7.4) et
                    // qu'on connait son adresse.
                    if (previousRole != models::ServerRole::Client) {
                        const QHostAddress activeAddress = m_electionService->activeServerAddress();
                        const quint16 activePort = m_electionService->activeServerPort();
                        if (!activeAddress.isNull() && activePort != 0) {
                            m_messagingService->disconnectFromHost();
                            if (!m_messagingService->connectToHost(activeAddress, activePort)) {
                                qWarning() << "Reconnexion au serveur actif impossible :" << activeAddress << activePort;
                            }
                        } else if (!activeAddress.isNull()) {
                            qWarning() << "Reconnexion au serveur actif impossible : port de messagerie inconnu pour"
                                       << activeAddress;
                        }
                    }
                }
            });

    // Cas du regime permanent (steady state) : un Client qui demarre alors
    // qu'un Server tourne deja depuis longtemps ne vit ni transition de role
    // (roleChanged) ni server_promoted -- il ne fait que recevoir des
    // heartbeats reguliers. Sans ce hook, MessagingService ne se connectait
    // JAMAIS dans ce cas (les trois connexions ci-dessus ne se declenchent
    // que sur un evenement de bascule), d'ou l'absence totale d'utilisateurs/
    // groupes visibles cote Client tant qu'aucune election n'a jamais eu
    // lieu depuis son demarrage.
    connect(m_electionService, &network::ElectionService::activeServerUuidChanged,
            this, [this]() {
                if (m_electionService->role() != models::ServerRole::Client)
                    return; // rien a connecter : ce poste est lui-meme Server/TempServer

                const QString activeUuid = m_electionService->activeServerUuid();
                if (activeUuid.isEmpty() || activeUuid == m_electionService->localMachineUuid())
                    return;

                const QHostAddress activeAddress = m_electionService->activeServerAddress();
                const quint16 activePort = m_electionService->activeServerPort();
                if (activeAddress.isNull() || activePort == 0)
                    return;

                if (m_messagingService->isConnected()
                    && m_messagingService->peerAddress() == activeAddress
                    && m_messagingService->peerPort() == activePort) {
                    // Deja connecte au bon serveur : c'est desormais le cas
                    // normal, puisque la connexion TLS est precisement ce qui
                    // vient de valider l'annonce (serverEndpointPending). Le
                    // signal connected() est donc deja passe : on demande ici
                    // la reconciliation que la connexion differee aurait
                    // declenchee, sinon ce poste resterait sans journal.
                    m_syncService->requestReconciliation(0, m_electionService->localMachineUuid());
                    return;
                }

                const QString localUuid = m_electionService->localMachineUuid();
                connect(m_messagingService, &network::MessagingService::connected,
                        m_syncService, [this, localUuid]() {
                            // fromEpoch=0 : demande l'integralite du journal
                            // (Users/Groups/Messages), pas seulement ce qui a
                            // ete rate depuis une panne -- c'est la premiere
                            // fois que ce poste voit ce serveur.
                            // SyncLogRepository::applyBatch() est idempotent :
                            // rejouable sans risque a chaque (re)connexion.
                            m_syncService->requestReconciliation(0, localUuid);
                        }, Qt::SingleShotConnection);

                m_messagingService->disconnectFromHost();
                if (!m_messagingService->connectToHost(activeAddress, activePort)) {
                    qWarning() << "Connexion initiale au serveur actif impossible :" << activeAddress << activePort;
                }
            });

    // Un server_promoted valide (epoch strictement supérieur, cf. règle
    // anti split-brain section 7) implique un nouveau serveur actif : tout
    // poste qui reste Client doit reconnecter MessagingService vers lui.
    // (Les transitions de CE poste vers/depuis Server/TempServer sont déjà
    // gérées ci-dessus via roleChanged.)
    connect(m_electionService, &network::ElectionService::serverPromoted,
            this, [this](int epoch, const QString &machineUuid, bool temporary) {
                Q_UNUSED(epoch);
                Q_UNUSED(temporary);
                if (m_electionService->role() != models::ServerRole::Client)
                    return; // ce poste est lui-même Server/TempServer, rien à reconnecter

                if (machineUuid == m_electionService->localMachineUuid())
                    return;

                const QHostAddress newServerAddress = m_electionService->activeServerAddress();
                const quint16 newServerPort = m_electionService->activeServerPort();
                if (newServerAddress.isNull() || newServerPort == 0) {
                    qWarning() << "server_promoted reçu mais adresse/port introuvable pour" << machineUuid;
                    return;
                }

                if (m_messagingService->isConnected()
                    && m_messagingService->peerAddress() == newServerAddress
                    && m_messagingService->peerPort() == newServerPort) {
                    // Depuis la validation TLS des annonces d'election, la
                    // connexion vers ce serveur est deja etablie au moment ou
                    // serverPromoted est emis : la couper pour la refaire a
                    // l'identique ne ferait que provoquer une coupure inutile.
                    return;
                }

                m_messagingService->disconnectFromHost();
                if (!m_messagingService->connectToHost(newServerAddress, newServerPort)) {
                    qWarning() << "Reconnexion au nouveau serveur actif impossible :" << newServerAddress << newServerPort;
                }
            });

    connect(m_electionService, &network::ElectionService::heartbeatLost,
            this, [this]() {
                QString logUuid;
                const int epoch = m_electionService->epoch();
                const QString machineUuid = m_electionService->activeServerUuid();
                if (m_serverElectionRepository->appendLogEntry(models::ServerElectionEvent::HeartbeatLost,
                                                                epoch, machineUuid, &logUuid)) {
                    broadcastServerElectionEvent(logUuid, models::ServerElectionEvent::HeartbeatLost,
                                                 epoch, machineUuid, QDateTime::currentDateTimeUtc());
                }
            });

    connect(m_electionService, &network::ElectionService::serverPromoted,
            this, [this](int epoch, const QString &machineUuid, bool temporary) {
                m_serverElectionRepository->updateRoleAndEpoch(m_electionService->role(), epoch);
                m_serverElectionRepository->updateActiveServer(m_electionService->activeServerAddress().toString(),
                                                               machineUuid,
                                                               QDateTime::currentDateTimeUtc());

                // CORRECTIF (divergence ServerElectionLog, cf. analyse CSV
                // instance1/instance2) : ElectionService::serverPromoted est
                // emis a la fois par le poste qui SE promeut localement
                // (enterServerRole) et par tout poste Client qui recoit le
                // paquet reseau server_promoted d'un pair. Journaliser+diffuser
                // dans les deux cas fait que chaque instance cree sa PROPRE
                // entree locale (log_uuid distinct) pour le meme evenement
                // logique, avant meme que la replication reseau n'ait eu
                // l'occasion de faire son travail -- applyRemoteLogEntry ne
                // peut alors plus dedupliquer puisque les uuid divergent des
                // la generation (cas SERVER_RESTORED observe sur les deux
                // instances avec epoch/machineUuid identiques mais log_uuid
                // ade3e1b6... vs e9f246d4...).
                // Seul le poste qui EST machineUuid (l'auteur reel de la
                // promotion) doit ecrire+diffuser l'entree ; les autres
                // postes la recoivent exclusivement via applyRemoteLogEntry
                // (handleIncomingPayload), qui reste la seule source de
                // verite chez eux pour cet evenement.
                if (machineUuid != m_electionService->localMachineUuid()) {
                    return;
                }

                QString logUuid;
                const QString eventType = temporary ? models::ServerElectionEvent::TempPromoted
                                                     : models::ServerElectionEvent::ServerRestored;
                if (m_serverElectionRepository->appendLogEntry(eventType, epoch, machineUuid, &logUuid)) {
                    broadcastServerElectionEvent(logUuid, eventType, epoch, machineUuid,
                                                 QDateTime::currentDateTimeUtc());
                }
            });

    connect(m_electionService, &network::ElectionService::reconciliationRequired,
            this, [this](const QString &tempServerUuid) {
                const int fromEpoch = m_electionService->epoch();

                // Voir commentaire sur m_lastReconciledEpoch/m_reconciliationInFlight
                // dans Application.h : sans cette garde, CHAQUE heartbeat du
                // TempServer (recu toutes les quelques secondes tant qu'on
                // reste Server officiel) redeclenchait une reconciliation
                // complete identique.
                if (m_reconciliationInFlight) {
                    return;
                }
                if (m_lastReconciledEpoch == fromEpoch) {
                    return;
                }

                const QHostAddress tempServerAddress = m_electionService->activeServerAddress();
                const quint16 tempServerPort = m_electionService->activeServerPort();
                if (tempServerAddress.isNull() || tempServerPort == 0) {
                    qWarning() << "Reconciliation impossible: adresse/port TEMP_SERVER inconnu pour" << tempServerUuid;
                    return;
                }

                // CORRECTIF (boucle de reconnexion infinie, cf. commentaire sur
                // m_lastReconciliationAttemptMs dans Application.h) : si ce
                // TEMP_SERVER a DEJA un certificat en attente d'approbation
                // (serverCertificateTrustRequired recu pour cette meme
                // adresse:port et jamais valide via approveServerCertificate()),
                // retenter maintenant echouera exactement de la meme facon --
                // inutile de rouvrir une connexion TLS avant qu'un humain
                // l'approuve depuis Parametres.
                if (!m_pendingServerFingerprint.isEmpty()
                    && m_pendingServerAddress == tempServerAddress.toString()
                    && m_pendingServerPort == tempServerPort) {
                    return;
                }

                // Filet de securite general : quelle qu'en soit la cause, ne
                // jamais retenter une reconciliation plus d'une fois par
                // cooldown -- le heartbeat (toutes les 3s) est bien plus
                // frequent que ce dont une vraie tentative de connexion TLS a
                // besoin pour echouer proprement, et marteler le reseau a ce
                // rythme indefiniment est ce qui degradait/plantait le poste
                // Server.
                const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
                if (nowMs - m_lastReconciliationAttemptMs < kReconciliationRetryCooldownMs) {
                    return;
                }
                m_lastReconciliationAttemptMs = nowMs;

                m_reconciliationInFlight = true;

                const QString localUuid = m_electionService->localMachineUuid();

                // CORRECTIF (reconciliation refusee en boucle des que le TEMP_SERVER
                // est aussi notre pair de messagerie habituel) : m_messagingService
                // est une connexion WebSocket UNIQUE et partagee. Si elle est deja
                // connectee a ce meme TEMP_SERVER (cas frequent : le TEMP_SERVER
                // temporaire est souvent le pair avec lequel on discute deja),
                // connectToHost() refusait immediatement et SYNCHRONE ("Already
                // connected, disconnect first") avant meme la moindre tentative
                // reseau -- ce qui declenchait a chaque heartbeat le message
                // "Reconciliation impossible: connexion au TEMP_SERVER refusee" en
                // boucle infinie, sans jamais aboutir. On reutilise ici directement
                // la connexion existante quand elle pointe deja vers le TEMP_SERVER.
                if (m_messagingService->isConnected()) {
                    if (m_messagingService->peerAddress() == tempServerAddress
                        && m_messagingService->peerPort() == tempServerPort) {
                        m_syncService->requestReconciliation(fromEpoch, localUuid);
                    } else {
                        qWarning() << "Reconciliation impossible: deja connecte a un autre poste ("
                                   << m_messagingService->peerAddress() << m_messagingService->peerPort()
                                   << "), impossible de joindre le TEMP_SERVER" << tempServerAddress << tempServerPort;
                        m_reconciliationInFlight = false;
                    }
                    return;
                }

                // CORRECTIF (Server officiel bloque indefiniment en attente de
                // reconciliation) : connectToHost() renvoie true des qu'il
                // INITIE la connexion TLS ; l'echec reel (certificat du
                // TEMP_SERVER non approuve, handshake TLS refuse, timeout
                // socket) n'arrive que plus tard, de facon asynchrone, via
                // MessagingService::disconnected()/error(). Ces deux signaux
                // n'etaient ecoutes nulle part ici : en cas d'echec async,
                // m_reconciliationInFlight restait bloque a "true" pour
                // toujours, et TOUT reconciliationRequired suivant (a chaque
                // heartbeat du TEMP_SERVER, donc en continu) etait alors
                // ignore en silence (garde ligne ci-dessus) -- le Server
                // officiel ne reclamait alors plus jamais son role, laissant
                // le TEMP_SERVER en place jusqu'a un passage manuel en
                // Client depuis Parametres. On arme donc ici aussi une garde
                // sur disconnected()/error(), a usage unique et qui se
                // desarme mutuellement des que l'un des trois signaux
                // (connected/disconnected/error) se declenche.
                auto connConn = std::make_shared<QMetaObject::Connection>();
                auto discConn = std::make_shared<QMetaObject::Connection>();
                auto errConn = std::make_shared<QMetaObject::Connection>();

                *discConn = connect(m_messagingService, &network::MessagingService::disconnected,
                        m_syncService, [this, connConn, errConn, discConn]() {
                            if (m_reconciliationInFlight) {
                                qWarning() << "Reconciliation impossible: deconnecte du TEMP_SERVER avant reponse";
                                m_reconciliationInFlight = false;
                            }
                            QObject::disconnect(*connConn);
                            QObject::disconnect(*errConn);
                        }, Qt::SingleShotConnection);

                *errConn = connect(m_messagingService, &network::MessagingService::error,
                        m_syncService, [this, connConn, errConn, discConn](const QString &errorString) {
                            if (m_reconciliationInFlight) {
                                qWarning() << "Reconciliation impossible: erreur de connexion au TEMP_SERVER -"
                                           << errorString;
                                m_reconciliationInFlight = false;
                            }
                            QObject::disconnect(*connConn);
                            QObject::disconnect(*discConn);
                        }, Qt::SingleShotConnection);

                *connConn = connect(m_messagingService, &network::MessagingService::connected,
                        m_syncService, [this, fromEpoch, localUuid, errConn, discConn]() {
                            QObject::disconnect(*errConn);
                            QObject::disconnect(*discConn);
                            m_syncService->requestReconciliation(fromEpoch, localUuid);
                        }, Qt::SingleShotConnection);

                if (!m_messagingService->connectToHost(tempServerAddress, tempServerPort)) {
                    qWarning() << "Reconciliation impossible: connexion au TEMP_SERVER refusee"
                               << tempServerAddress << tempServerPort;
                    m_reconciliationInFlight = false;
                    QObject::disconnect(*connConn);
                    QObject::disconnect(*discConn);
                    QObject::disconnect(*errConn);
                }
            });

    connect(m_syncService, &network::SyncService::reconciliationCompleted,
            this, [this](int mergedEntryCount) {
                qDebug() << "Reconciliation terminee, entrees fusionnees:" << mergedEntryCount;
                m_lastReconciledEpoch = m_electionService->epoch();
                m_reconciliationInFlight = false;

                // Rejeu des messages temps reel mis en attente le temps que
                // leur expediteur soit resolu (cf. connexion sur
                // unresolvedSenderMessage plus haut). Si l'expediteur reste
                // introuvable (reconciliation incomplete), receiveMessage()
                // re-emettra unresolvedSenderMessage et le message sera
                // simplement retente a la prochaine reconciliation.
                if (!m_pendingUnresolvedMessages.isEmpty() && m_messagingManager) {
                    const QStringList toReplay = m_pendingUnresolvedMessages;
                    m_pendingUnresolvedMessages.clear();
                    for (const QString &payload : toReplay) {
                        m_messagingManager->receiveMessage(payload);
                    }
                }
                {
                    QString logUuid;
                    const int epoch = m_electionService->epoch();
                    const QString machineUuid = m_electionService->activeServerUuid();
                    if (m_serverElectionRepository->appendLogEntry(models::ServerElectionEvent::ServerReconciled,
                                                                    epoch, machineUuid, &logUuid)) {
                        broadcastServerElectionEvent(logUuid, models::ServerElectionEvent::ServerReconciled,
                                                     epoch, machineUuid, QDateTime::currentDateTimeUtc());
                    }
                }
                // Notifier que la liste des utilisateurs a change (apres synchro)
                // Utiliser Qt::QueuedConnection pour éviter les crashs de thread
                if (m_userManager) {
                    QMetaObject::invokeMethod(m_userManager, [this]() {
                        m_userManager->emitUsersChanged();
                    }, Qt::QueuedConnection);
                }
                // reclaimAsOfficialServer() ne concerne QUE le Server officiel
                // qui revient d'une panne (section 7.3) : reconciliationCompleted
                // est desormais aussi emis pour la synchro initiale d'un simple
                // Client (cf. activeServerUuidChanged plus haut) qui ne doit
                // surtout pas s'auto-promouvoir Server.
                if (m_electionService->role() == models::ServerRole::Server) {
                    m_electionService->reclaimAsOfficialServer();
                }
            });

    connect(m_syncService, &network::SyncService::reconciliationFailed,
            this, [this](const QString &reason) {
                qWarning() << "Reconciliation echouee:" << reason;
                // Sans ce reset, un premier essai qui echoue (ex. TEMP_SERVER
                // injoignable momentanement) bloquait m_reconciliationInFlight
                // a "true" pour toujours, empechant tout nouvel essai au
                // prochain heartbeat.
                m_reconciliationInFlight = false;
            });

    if (!m_electionService->start()) {
        qWarning() << "Impossible de demarrer ElectionService";
    }
    // Initialiser le NotificationManager pour les notifications
    m_notificationManager = new core::NotificationManager(this);
    // Permet a onMessageReceived() de resoudre le nom de l'expediteur pour
    // le titre de la notification enrichie (cf. NotificationManager::setUserManager).
    m_notificationManager->setUserManager(m_userManager);

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
                qDebug() << "[Application] notificationRequested recu pour le son, categorie:" << category
                         << "soundEnabled:" << m_audioService->isSoundEnabled();
                if (category == QStringLiteral("message")) {
                    m_audioService->playMessageSound();
                } else if (category == QStringLiteral("transfer")) {
                    m_audioService->playTransferSound();
                } else if (category == QStringLiteral("folder") || category == QStringLiteral("group")) {
                    // Partage/revocation de dossier ET creation de groupe : meme
                    // son que "message" (aucun son dedie n'existe pour ces
                    // categories dans AudioService pour l'instant). CORRECTIF :
                    // "group" n'etait rattache a aucune branche ici, donc les
                    // notifications "Nouveau groupe" affichaient un toast mais
                    // ne jouaient jamais aucun son.
                    m_audioService->playMessageSound();
                }
                // "connection"/"disconnection" : toast silencieux (pas de son
                // dedie ; playCallSound() est reserve aux appels entrants).
            });

    // Un transfert termine ou en echec declenche une notification
    // (toast + son "transfert"). Exception : un transfert declenche par la
    // synchronisation d'un dossier partage -- que ce soit une reception ou
    // un envoi en reponse a un folder_file_request d'un pair -- n'affiche
    // PAS sa propre notification, sinon partager un dossier de N fichiers
    // afficherait N toasts (cote destinataire ET cote expediteur). Ces
    // transferts sont regroupes en une seule notification "N fichiers
    // recus" (folderFilesReceived) ou "N fichiers envoyes" (folderFilesSent)
    // via FolderSyncService (cf. plus bas, une fois m_folderSyncService cree).
    //
    // CORRECTIF (notifications parasites persistantes malgre le fix
    // QMultiHash de m_pendingOutgoingByKey) : on utilise ici DIRECTEMENT le
    // flag isFolderTransfer transmis par TransferService::transferStarted
    // (connu de maniere fiable a la source, cf. PendingSendJob::
    // isFolderTransfer / SendState::isFolderTransfer / TransferService.h)
    // plutot que FolderSyncService::isFolderTransfer(), qui ne fait que
    // RECONSTRUIRE cette meme information en devinant a partir d'une
    // correlation "<requesterUuid>::<fileName>" -- fragile par nature
    // (plusieurs demandes concurrentes pour un meme fichier lors d'un rejeu
    // d'historique, cf. m_lastBroadcastOpIdByFolder non persiste). Le flag
    // du fil reseau ne peut jamais se tromper : on le capture ici au
    // demarrage du transfert et on le consulte/consomme a la fin, sans
    // dependre d'aucune reconstruction par nom de fichier.
    auto folderTransferKeys = std::make_shared<QSet<QString>>();
    connect(m_transferService, &network::TransferService::transferStarted,
            this, [folderTransferKeys](const QString &transferKey, const QString &/*fileName*/,
                                        qint64 /*fileSize*/, bool /*incoming*/, qint64 /*resumeOffset*/,
                                        const QString &/*senderUuid*/, const QString &/*recipientUuid*/,
                                        const QHostAddress &/*peerAddress*/, const QString &/*peerMachineId*/,
                                        bool isFolderTransfer) {
                if (isFolderTransfer) {
                    folderTransferKeys->insert(transferKey);
                }
            });
    connect(m_transferService, &network::TransferService::transferCompleted,
            this, [this, folderTransferKeys](const QString &transferKey, const QString &filePath) {
                const bool isFolder = folderTransferKeys->remove(transferKey);
                qDebug() << "[Application] transferCompleted pour transferKey:" << transferKey
                         << "isFolderTransfer (flag fiable transferStarted):" << isFolder
                         << "-- filePath:" << filePath;
                if (isFolder) {
                    return;
                }
                m_notificationManager->onTransferCompleted(transferKey, filePath);
            });
    connect(m_transferService, &network::TransferService::transferFailed,
            this, [this, folderTransferKeys](const QString &transferKey, const QString &reason) {
                if (folderTransferKeys->remove(transferKey)) {
                    return;
                }
                m_notificationManager->onTransferFailed(transferKey, reason);
            });

    // Initialiser le VoiceService pour les appels vocaux P2P (issues #60/
    // #61/#64) : signalisation WebRTC sur le port de messagerie + 2 (meme
    // logique que TransferService plus haut, port + 1), pour eviter tout
    // conflit entre plusieurs instances lancees localement.
    m_voiceService = new network::VoiceService(m_securityService, this);
    if (!m_voiceService->startListening(static_cast<quint16>(messagingServerPort + 2))) {
        qWarning() << "Impossible de demarrer VoiceService";
    }

    // Un appel entrant declenche le son "call" (issue #56) des la
    // reception de l'offre, avant meme que l'utilisateur ait decroche -
    // c'est le signal incomingCall(), pas callConnected(), qui doit piloter
    // playCallSound() ici.
    connect(m_voiceService, &network::VoiceService::incomingCall,
            m_audioService, [this](const QHostAddress &callerAddress) {
                Q_UNUSED(callerAddress);
                m_audioService->playCallSound();
            });

    // La sonnerie (boucle infinie, cf. AudioService::AudioService) doit
    // s'arreter des que l'appel quitte l'etat "Ringing", quelle qu'en soit
    // la raison : decroche, refuse localement, ou raccroche par l'appelant
    // avant que l'utilisateur ait reagi.
    connect(m_voiceService, &network::VoiceService::stateChanged,
            m_audioService, [this](network::CallState state) {
                if (state != network::CallState::Ringing) {
                    m_audioService->stopCallSound();
                }
            });

    // Initialiser l'AuditManager pour le journal d'audit (issues #62/#63),
    // consulte/exporte depuis AdminView.qml (issue #65).
    m_auditManager = new core::AuditManager(m_databaseManager.get(), this);

    connect(m_auditManager, &core::AuditManager::eventRecorded,
            this, [this](const models::AuditLog &entry) {
                if (!m_messagingService || !m_messagingService->isConnected()) return;
                QJsonObject payload;
                payload[QStringLiteral("type")] = QStringLiteral("audit_event");
                payload[QStringLiteral("event_uuid")] = entry.eventUuid();
                payload[QStringLiteral("machine_uuid")] = m_discoveryService->localId();
                payload[QStringLiteral("event_type")] = entry.eventType();
                payload[QStringLiteral("description")] = entry.description();
                payload[QStringLiteral("actor_label")] = entry.actorLabel();
                payload[QStringLiteral("created_at")] = entry.timestamp().toUTC().toString(Qt::ISODateWithMs);
                if (const auto uid = m_userManager->currentUserId(); uid.has_value())
                    payload[QStringLiteral("user_uuid")] = userUuidForId(*uid);
                m_messagingService->sendMessage(
                    QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
            });

    connect(m_messagingManager, &core::MessagingManager::messageSent,
            m_auditManager, [this](const models::Message &message) {
                const auto userId = m_userManager->currentUserId();
                m_auditManager->logMessage(message.senderId(), message.conversationId(), true);
                Q_UNUSED(userId)
            });
    connect(m_messagingManager, &core::MessagingManager::messageReceived,
            m_auditManager, [this](const models::Message &message) {
                m_auditManager->logMessage(message.senderId(), message.conversationId(), false);
            });

    connect(m_transferManager, &core::TransferManager::transferRecorded,
            m_auditManager, [this](int, const models::Transfer &transfer) {
                const auto userId = m_userManager->currentUserId();
                m_auditManager->logTransfer(
                    userId.has_value() ? *userId : 0,
                    transfer.fileName(), transfer.fileSize(),
                    models::transferStatusToString(transfer.status()));
            });

    // Le journal ne se remplit pas automatiquement : les services ne font
    // que definir les methodes d'audit. Enregistrer explicitement les
    // authentifications permet au journal d'avoir une trace fiable des
    // sessions, y compris quand aucun trafic reseau n'a encore eu lieu.
    connect(m_userManager, &core::UserManager::loginSucceeded,
            m_auditManager, [this](const QString &username) {
                const auto userId = m_userManager->currentUserId();
                m_auditManager->recordEvent(
                    core::AuditEventType::Connection,
                    QStringLiteral("Utilisateur authentifie : %1").arg(username),
                    userId.has_value() ? std::optional<qint64>(*userId) : std::nullopt,
                    username);
            });

    connect(m_userManager, &core::UserManager::loginFailed,
            m_auditManager, [this](const QString &reason) {
                m_auditManager->recordEvent(
                    core::AuditEventType::AccessDenied,
                    QStringLiteral("Echec d'authentification : %1").arg(reason));
            });

    // Initialiser le PermissionManager pour la gestion des rôles (issue #67)
    // et des machines autorisées (issue #68).
    m_permissionManager = new core::PermissionManager(m_databaseManager.get(), this);
    connect(m_permissionManager, &core::PermissionManager::machineChanged,
            this, &Application::pendingClientCountChanged);

    // Les politiques TLS sont volontairement LOCALES : TrustedServers porte
    // la confiance du client envers un serveur, AuthorizedClients porte la
    // decision du serveur envers ses clients. Elles ne sont jamais envoyees
    // via MessagingService ni repliquees avec les donnees metier.

    // Connecter les services au MessagingManager
    m_messagingManager->setMessagingService(m_messagingService);
    m_messagingManager->setMessagingServer(m_messagingServer);
    m_messagingManager->setNotificationManager(m_notificationManager);
    // Necessaire pour que MessagingManager::receiveMessage() connaisse
    // notre identite locale (repli quand l'uuid de "l'autre" participant
    // envoye par l'expediteur ne correspond a aucun utilisateur local -
    // cf. commentaire dans MessagingManager::receiveMessage()).
    m_messagingManager->setUserManager(m_userManager);
    m_groupManager->setMessagingServer(m_messagingServer);
    m_groupManager->setMessagingService(m_messagingService);

    // Connecter PermissionManager aux services réseau pour vérifier les machines autorisées
    m_messagingService->setPermissionManager(m_permissionManager);
    m_messagingServer->setPermissionManager(m_permissionManager);
    m_syncService->setPermissionManager(m_permissionManager);
    m_transferService->setPermissionManager(m_permissionManager);
    m_transferService->setSecurityService(m_securityService);
    m_voiceService->setPermissionManager(m_permissionManager);


    // Connecter MessagingServer à MessagingManager pour traiter les messages reçus.
    // Ce poste agit ici en tant que SERVER (connexions entrantes) : relay=true,
    // il doit retransmettre (broadcastMessage) le payload aux AUTRES clients
    // connectes pour que le veritable destinataire le reçoive en temps reel
    // (topologie en etoile : sans ce relais, le message n'etait persiste que
    // dans la base du SERVER, jamais transmis au destinataire).
    // SyncService écoute aussi MessagingServer::messageReceived pour les messages de sync
    connect(m_messagingServer, &network::MessagingServer::messageReceived,
            m_messagingManager, [this](const QString &message, const QHostAddress &senderAddress) {
                Q_UNUSED(senderAddress)
                handleIncomingPayload(message, /*relay=*/true);
            });

    // Connecter MessagingService (connexion sortante) à MessagingManager :
    // ce poste agit ici en tant que CLIENT du SERVER actif. Ce signal
    // n'etait auparavant ecoute que par SyncService (qui ignore
    // silencieusement les payloads de type "message"/"group_created") :
    // un poste CLIENT ne traitait donc JAMAIS les messages qui lui
    // etaient pourtant bien transmis par le SERVER - ils disparaissaient
    // purement et simplement. relay=false : un CLIENT n'a pas ses propres
    // clients connectes a retransmettre.
    connect(m_messagingService, &network::MessagingService::messageReceived,
            m_messagingManager, [this](const QString &message) {
                handleIncomingPayload(message, /*relay=*/false);
            });

    // Connecter les connexions refusées à l'audit (issue #70)
    connect(m_messagingServer, &network::MessagingServer::connectionRefused,
            m_auditManager, [this](const QHostAddress &clientAddress, const QString &reason) {
                m_auditManager->logRefusedAttempt(
                    QStringLiteral("Machine %1 non autorisée : %2").arg(clientAddress.toString(), reason),
                    clientAddress
                );
            });

    // Connecter les erreurs de connexion de MessagingService à l'audit (issue #70)
    connect(m_messagingService, &network::MessagingService::error,
            m_auditManager, [this](const QString &errorString) {
                if (errorString.contains(QStringLiteral("not authorized"))) {
                    m_auditManager->logRefusedAttempt(errorString);
                }
            }, Qt::QueuedConnection);

    // Seed du compte admin par defaut (dev/demo), tant qu'aucun ecran
    // d'inscription n'existe.
    //
    // CORRECTIF (bug "admin*conflict*<uuid>") : ce seed etait auparavant
    // inconditionnel, execute sur CHAQUE poste (Server ET Client) des lors
    // que sa base locale etait vide. Consequence : un Client fraichement
    // installe se creait son propre "admin" (uuid local) AVANT meme de se
    // synchroniser, puis recevait via sync_batch le "admin" reel du serveur
    // -- collision de nom detectee par SyncLogRepository::applyUserEntry,
    // qui renommait alors l'entrant en "admin*conflict*<uuid8>". Ce n'etait
    // pas un vrai conflit concurrent, juste un artefact du bootstrap.
    //
    // Le seed est reserve au serveur principal. Un TempServer peut coexister
    // avec le serveur officiel pendant une partition : le laisser creer un
    // admin vide recreerait une collision a la reconciliation.
    if (effectiveElectionState.currentRole() == models::ServerRole::Server)
        seedDefaultAdminIfNeeded();

    // Demarre la decouverte reseau (issue #9) et branche le modele QML
    // (PeersModel) qui alimentera UsersView.qml en temps reel (issue #17).
    m_discoveryService = new network::DiscoveryService(this);

    // Remplace l'identifiant ephemere auto-genere (QUuid::createUuid() a
    // chaque lancement, cf. DiscoveryService::DiscoveryService()) par une
    // valeur relue (ou creee une seule fois) dans la table Settings LOCALE
    // (donc stable tant que --db pointe vers le meme fichier -- exactement
    // ce qui distingue deux "machines" simulees sur un seul poste de test).
    //
    // Sans ce correctif, FolderSyncService perd la correlation
    // ownerMachineId/peerMachineId de chaque PendingFileTransfer des qu'une
    // machine redemarre : les fichiers demandes via un rattrapage
    // (folder_hello / folder_resync_request) sont bien transferes par
    // TransferService, mais ne sont jamais integres au dossier partage
    // (onTransferStarted() ne retrouve pas la demande en attente) -- ils
    // n'apparaissent nulle part dans SharedFolderView, alors que le
    // transfert reseau lui-meme a reussi.
    if (m_databaseManager) {
        database::SettingsRepository settingsRepository(m_databaseManager->database());
        const QString kMachineIdKey = QStringLiteral("local_machine_id");
        const auto existing = settingsRepository.findByKey(kMachineIdKey);
        if (existing.has_value() && !existing->value().toString().isEmpty()) {
            m_discoveryService->setLocalId(existing->value().toString());
        } else {
            const QString newId = m_discoveryService->localId();
            settingsRepository.save(models::Settings(kMachineIdKey, newId));
        }
    }

    m_discoveryService->setPermissionManager(m_permissionManager);
    if (m_securityService) {
        m_discoveryService->setLocalCertificateFingerprint(
            m_securityService->identity().fingerprintSha256);
    }
    m_discoveryService->setTransferPort(static_cast<quint16>(messagingServerPort + 1));
    m_discoveryService->setSignalingPort(static_cast<quint16>(messagingServerPort + 2));
    if (m_discoveryPortOverride != 0) {
        m_discoveryService->setPort(m_discoveryPortOverride);
    }
    m_peersModel = new network::PeersModel(m_discoveryService, this);

    // La decouverte identifie d'abord une machine, pas necessairement un
    // utilisateur authentifie. Une notification utilisateur ne doit donc
    // partir que lorsque l'annonce contient userUuid. Le passage hostname ->
    // nom utilisateur arrive ensuite via peerUpdated.
    connect(m_discoveryService, &network::DiscoveryService::peerDiscovered,
            m_notificationManager, [this](const network::DiscoveredPeer &peer) {
                if (peer.userUuid.isEmpty())
                    return;
                const QString key = peer.id + QStringLiteral("|") + peer.userUuid;
                if (m_notifiedPeerUsers.contains(key))
                    return;
                m_notifiedPeerUsers.insert(key);
                m_notificationManager->onPeerConnected(peer.name);
            }, Qt::QueuedConnection);
    connect(m_discoveryService, &network::DiscoveryService::peerUpdated,
            m_notificationManager, [this](const network::DiscoveredPeer &peer) {
                if (peer.userUuid.isEmpty())
                    return;
                const QString key = peer.id + QStringLiteral("|") + peer.userUuid;
                if (m_notifiedPeerUsers.contains(key))
                    return;
                m_notifiedPeerUsers.insert(key);
                m_notificationManager->onPeerConnected(peer.name);
            }, Qt::QueuedConnection);
    connect(m_discoveryService, &network::DiscoveryService::peerLost,
            m_notificationManager, [this](const network::DiscoveredPeer &peer) {
                const QString prefix = peer.id + QStringLiteral("|");
                QStringList matchingKeys;
                for (const QString &key : std::as_const(m_notifiedPeerUsers)) {
                    if (key.startsWith(prefix))
                        matchingKeys.append(key);
                }
                if (matchingKeys.isEmpty())
                    return;
                for (const QString &key : matchingKeys)
                    m_notifiedPeerUsers.remove(key);
                m_notificationManager->onPeerDisconnected(peer.name);
            }, Qt::QueuedConnection);

    // Renomme l'annonce avec le nom d'utilisateur connecte des qu'une
    // authentification reussit (avant cela, le hostname sert de nom par
    // defaut, cf. DiscoveryService::DiscoveryService).
    if (m_userManager) {
        connect(m_userManager, &core::UserManager::authenticationChanged, m_discoveryService,
                [this]() {
                    const QString username = m_userManager->currentUsername();
                    if (!username.isEmpty())
                        m_discoveryService->setLocalName(username);
                    // Bug #2 (recipient_uuid toujours vide) : diffuse aussi
                    // l'UUID du compte connecte, pour que sendFile() puisse
                    // resoudre recipientUuid a partir du peerMachineId choisi
                    // (cf. TransferContext::sendFile()). Remis a vide sur
                    // deconnexion, comme currentUsername().
                    m_discoveryService->setLocalUserUuid(m_userManager->currentUserUuid());
                });
    }

    if (!m_discoveryService->start()) {
        qWarning() << "Impossible de demarrer DiscoveryService (port deja utilise ?)";
    }

    // AuthorizedClients ne contient que les clients entrants du serveur :
    // le serveur local ne s'y inscrit jamais lui-meme.

    // Initialiser le CallHistoryManager : persiste chaque appel (emis ou
    // recu) et son issue finale dans la table CallHistory (migration 013),
    // ce qui manquait jusqu'ici - VoiceService gerait l'appel entierement
    // en memoire sans jamais rien enregistrer. Doit etre cree apres
    // m_voiceService (deja pret plus haut), m_userManager (deja pret,
    // cf. debut de cette methode) et m_discoveryService (juste au-dessus),
    // les trois etant necessaires pour resoudre local_user_id/peer_name.
    m_callHistoryManager = new core::CallHistoryManager(m_databaseManager.get(), this);
    m_callHistoryManager->setVoiceService(m_voiceService);
    m_callHistoryManager->setUserManager(m_userManager);
    m_callHistoryManager->setDiscoveryService(m_discoveryService);

    connect(m_callHistoryManager, &core::CallHistoryManager::callRecorded,
            m_auditManager, [this](int, const models::CallHistoryEntry &entry) {
                const std::optional<qint64> userId = entry.localUserId() > 0
                    ? std::optional<qint64>(entry.localUserId()) : std::nullopt;
                const QString direction = models::callDirectionToString(entry.direction());
                m_auditManager->logCall(
                    userId, QHostAddress(entry.peerAddress()),
                    QStringLiteral("%1 (%2)").arg(models::callStatusToString(entry.status()), direction),
                    entry.peerName());
            });

    // TransferManager a ete instancie plus haut (avant DiscoveryService) :
    // on ne peut lui fournir la resolution de peer_name (migration #015)
    // qu'a partir d'ici, une fois m_discoveryService pret.
    if (m_transferManager) {
        m_transferManager->setDiscoveryService(m_discoveryService);
    }

    // Initialiser le SharedFolderManager (module "Shared Folder", 1ere
    // tranche : creer/lister/supprimer des dossiers partages + indexation
    // locale de leur contenu). Aucune dependance reseau -- peut etre cree
    // des que m_databaseManager est pret.
    m_sharedFolderManager = new core::SharedFolderManager(m_databaseManager.get(), this);

    // SyncEngine (Release 2 : detection des changements) orchestre toute
    // (re)indexation d'un dossier partage -- surveillance du systeme de
    // fichiers (FolderWatcher) + journal des changements (SyncOperations,
    // migration #018). Cree juste apres m_sharedFolderManager (dont il
    // depend) et m_discoveryService (dont il tire l'identifiant local a
    // enregistrer sur chaque SyncOperation, comme TransferService
    // ci-dessous). start() commence a surveiller les dossiers deja
    // partages ; toute (re)indexation ulterieure doit passer par
    // m_syncEngine->reindexFolder() plutot que par
    // m_sharedFolderManager->shareFolder() directement (cf.
    // core/SharedFolderContext.cpp).
    m_syncEngine = new core::sync::SyncEngine(m_sharedFolderManager, m_databaseManager.get(),
                                               m_discoveryService->localId(), this);
    // Necessaire pour que canWatchFolder() puisse resoudre la permission
    // Write du poste local sur un dossier replique (cf. SyncEngine.h) ;
    // meme cablage que m_folderSyncService->setLocalUserId() ci-dessous,
    // car initialize() s'execute avant le login (currentUserId() est
    // nullopt a ce stade la premiere fois).
    if (m_userManager) {
        if (const auto uid = m_userManager->currentUserId(); uid.has_value()) {
            m_syncEngine->setLocalUserId(*uid);
        }
        connect(m_userManager, &core::UserManager::loginSucceeded,
                this, [this]() {
                    if (const auto uid = m_userManager->currentUserId(); uid.has_value()) {
                        m_syncEngine->setLocalUserId(*uid);
                    }
                });
    }
    m_syncEngine->start();

    // Idem pour TransferService : chaque en-tete de transfert envoye doit
    // porter l'UUID local (DiscoveryService::localId()) pour que le
    // destinataire puisse resoudre peer_name par identifiant plutot que
    // par adresse IP (voir TransferManager::resolvePeerName()).
    if (m_transferService) {
        m_transferService->setLocalMachineId(m_discoveryService->localId());

        // Regroupe cote reception tous les fichiers d'un meme
        // correspondant dans un seul sous-dossier de receiveDirectory()
        // (ex. "LocaLink Transfers/laptop-marie/"), a la maniere d'un
        // explorateur de fichiers Windows organise par contact plutot
        // qu'un unique repertoire plat.
        //
        // CORRECTIF (dossiers dupliques pour un meme correspondant) : le
        // nom "lisible" annonce par DiscoveryService (peer.name) est en
        // realite le nom d'utilisateur *actuellement* connecte sur le
        // poste distant (cf. setLocalName() sur authenticationChanged,
        // juste au-dessus). Comme ce nom peut changer d'un transfert a
        // l'autre pour le meme peerMachineId (reconnexion sous un autre
        // compte, pair momentanement absent de DiscoveryService::peers()
        // au moment precis de la reception), l'utiliser directement pour
        // nommer le dossier faisait migrer les fichiers d'un correspondant
        // deja connu vers un nouveau sous-dossier a chaque changement,
        // au lieu de les regrouper durablement dans le meme. On fige donc
        // ici, dans la table Settings locale (cle "peer_folder_name:<uuid>"),
        // le premier nom lisible resolu pour un peerMachineId donne, et on
        // le reutilise ensuite systematiquement. Meme cle/convention que
        // core::TransferManager::resolvePeerName() pour que le nom du
        // sous-dossier physique et le peer_name affiche dans l'historique
        // restent toujours identiques pour un meme correspondant.
        network::DiscoveryService *discoveryService = m_discoveryService;
        database::DatabaseManager *dbManager = m_databaseManager.get();
        m_transferService->setPeerFolderNameResolver(
            [discoveryService, dbManager](const QHostAddress &peerAddress, const QString &peerMachineId) -> QString {
                const QString cacheKey = peerMachineId.isEmpty()
                    ? QString()
                    : QStringLiteral("peer_folder_name:%1").arg(peerMachineId);
                if (!cacheKey.isEmpty() && dbManager) {
                    database::SettingsRepository settingsRepository(dbManager->database());
                    const auto cached = settingsRepository.findByKey(cacheKey);
                    if (cached.has_value() && !cached->value().toString().isEmpty()) {
                        return cached->value().toString();
                    }
                }

                if (!discoveryService) {
                    return QString();
                }
                const QList<network::DiscoveredPeer> peers = discoveryService->peers();
                QString liveName;
                if (!peerMachineId.isEmpty()) {
                    for (const network::DiscoveredPeer &peer : peers) {
                        if (peer.id == peerMachineId) {
                            liveName = peer.name;
                            break;
                        }
                    }
                }
                if (liveName.isEmpty()) {
                    for (const network::DiscoveredPeer &peer : peers) {
                        if (peer.address.isEqual(peerAddress, QHostAddress::TolerantConversion)) {
                            liveName = peer.name;
                            break;
                        }
                    }
                }

                if (!cacheKey.isEmpty() && dbManager && !liveName.isEmpty()) {
                    database::SettingsRepository settingsRepository(dbManager->database());
                    settingsRepository.save(models::Settings(cacheKey, liveName));
                }
                return liveName;
            });
    }

    // ---------------------------------------------------------------------------
    // Releases 4-7 : diffusion réseau temps réel des changements de dossiers
    // FolderSyncService orchestre :
    //   • Release 4 : protocole dédié (folder_op / folder_hello /
    //                 folder_catchup_batch / folder_file_request)
    //   • Release 5/6 : broadcast immédiat à chaque folderReindexed
    //   • Release 7 : catch-up hors-ligne via folder_hello / catchup_batch
    // ---------------------------------------------------------------------------
    m_folderSyncService = new core::sync::FolderSyncService(
        m_databaseManager.get(), m_sharedFolderManager, this);
    m_folderSyncService->setMessagingServer(m_messagingServer);
    m_folderSyncService->setMessagingService(m_messagingService);
    m_folderSyncService->setTransferService(m_transferService);
    m_folderSyncService->setDiscoveryService(m_discoveryService);
    m_folderSyncService->setLocalMachineId(m_discoveryService->localId());
    m_folderSyncService->setUserManager(m_userManager);

    if (m_userManager) {
        if (const auto uid = m_userManager->currentUserId(); uid.has_value()) {
            m_folderSyncService->setLocalUserId(*uid);
        }
        // Connecter loginSucceeded pour mettre à jour m_localUserId après connexion
        // (initialize() s'exécute avant le login, donc currentUserId() est nullopt à ce stade)
        connect(m_userManager, &core::UserManager::loginSucceeded,
                this, [this]() {
                    if (const auto uid = m_userManager->currentUserId(); uid.has_value()) {
                        m_folderSyncService->setLocalUserId(*uid);
                    }
                });
    }

    // Release 5/6 : chaque reindexation locale est diffusée aux pairs.
    connect(m_syncEngine, &core::sync::SyncEngine::folderReindexed,
            m_folderSyncService, &core::sync::FolderSyncService::onLocalFolderReindexed);

    // NB : folderCreated -> SyncEngine::onFolderCreated (démarre la
    // surveillance d'un nouveau dossier partagé local) est déjà câblé à
    // l'intérieur même du constructeur de SyncEngine (cf. SyncEngine.cpp) --
    // pas besoin de le refaire ici. Un doublon existait à cet endroit
    // (le même signal connecté deux fois au même slot, donc onFolderCreated()
    // s'exécutait deux fois par création de dossier) ; retiré, sans effet
    // fonctionnel puisque watchFolder()/reindexFolder() sont idempotents,
    // mais inutilement coûteux et trompeur à la lecture.

    // Connecter folderRemoved pour arrêter la surveillance
    connect(m_sharedFolderManager, &core::SharedFolderManager::folderRemoved,
            m_syncEngine, &core::sync::SyncEngine::onFolderRemoved);

    // Issue A1/A2 : un acces accorde (creation de dossier partage avec
    // utilisateurs choisis, ou partage ulterieur) est annonce aux autres
    // machines du LAN -- sans ce connect, un dossier cree n'est jamais
    // propagé au-dela du poste createur (cf. core::SharedFolderManager::
    // createFolder(), core::sync::FolderSyncService::announceAccessGranted()).
    connect(m_sharedFolderManager, &core::SharedFolderManager::accessGranted,
            m_folderSyncService, &core::sync::FolderSyncService::announceAccessGranted);
    connect(m_sharedFolderManager, &core::SharedFolderManager::accessRevoked,
            m_folderSyncService, &core::sync::FolderSyncService::announceAccessRevoked);

    // Notifier quand un dossier partagé est créé
    //
    // NB : on ne peut pas se contenter d'ecouter folderCreated() : ce signal
    // n'est (re)emis que lorsque SharedFolderManager::registerRemoteFolder()
    // insere une NOUVELLE ligne SharedFolder. Si le dossier etait deja connu
    // localement (metadonnees recues via un folder_hello/catchup anterieur,
    // avant meme que cet utilisateur ait l'acces), grantAccess() ne re-emet
    // pas folderCreated -> aucune notification n'etait envoyee alors que
    // l'acces est bien nouveau pour lui. On notifie donc plutot sur
    // accessGrantedLocal(), qui est TOUJOURS emis, filtre sur l'utilisateur
    // local.
    //
    // isNewGrant filtre les ré-émissions idempotentes du même grant (rejoué
    // sans condition à chaque reconnexion/catchup hors ligne, cf.
    // core::sync::FolderSyncService::handleFolderAccessGranted()) : sans ce
    // filtre, l'utilisateur revoyait la notification "dossier partagé avec
    // vous" à chaque reconnexion pour un partage déjà connu.
    //
    // L'auto-provisionnement du chemin local (Documents/LocaLink Shared
    // Folders/<nom>) n'est PLUS déclenché automatiquement ici : il nécessite
    // désormais la confirmation explicite de l'utilisateur (dialogue de
    // partage, cf. core::SharedFolderContext::folderShareConfirmationRequested()
    // / acceptFolderShare()), pour ne pas commencer à remplir son disque
    // sans qu'il ait rien validé. Cf. folderLocalPathProvisioned ci-dessous
    // pour ce qui se passe une fois qu'il a accepté.
    connect(m_sharedFolderManager, &core::SharedFolderManager::accessGrantedLocal,
            this, [this](qint64 folderId, qint64 userId, bool isNewGrant) {
                if (!isNewGrant) {
                    return;
                }
                if (!m_userManager->currentUserId().has_value()
                    || static_cast<qint64>(*m_userManager->currentUserId()) != userId) {
                    return;
                }
                const auto folder = m_sharedFolderManager->getFolder(folderId);
                if (!folder.has_value()) return;

                const auto users = m_userManager->allUsers();
                auto it = std::find_if(users.begin(), users.end(),
                    [&folder](const models::User &u) { return u.id() == folder->ownerId(); });
                if (it != users.end()) {
                    m_notificationManager->onFolderCreated(folder->name(), it->name());
                }
            });

    // Une fois qu'un chemin local par défaut a été assigné à un dossier
    // partagé distant (SharedFolderManager::provisionDefaultLocalPath(),
    // déclenché par l'utilisateur en acceptant le dialogue de confirmation
    // de partage, cf. core::SharedFolderContext::acceptFolderShare()) :
    // lancer le resync réseau pour récupérer le contenu depuis le
    // propriétaire. Pas de notification séparée ici -- l'emplacement du
    // dossier est désormais communiqué une seule fois, fusionné avec le
    // compte de fichiers, dans la notification de fin de rafale (cf.
    // connexion de folderFilesReceived plus bas / NotificationManager::
    // onFolderFilesReceived()).
    connect(m_sharedFolderManager, &core::SharedFolderManager::folderLocalPathProvisioned,
            this, [this](qint64 folderId, const QString &localPath) {
                Q_UNUSED(localPath);
                const auto folder = m_sharedFolderManager->getFolder(folderId);
                if (!folder.has_value()) return;

                if (m_folderSyncService) {
                    m_folderSyncService->requestFolderResync(folder->uuid());
                }
            });


    // Notifier quand l'accès à un dossier partagé est révoqué
    connect(m_sharedFolderManager, &core::SharedFolderManager::accessRevokedLocal,
            this, [this](qint64 folderId, qint64 userId) {
                // Ne notifier que si c'est l'utilisateur local qui est révoqué
                if (m_userManager->currentUserId().has_value()
                    && static_cast<qint64>(*m_userManager->currentUserId()) == userId) {
                    const auto folder = m_sharedFolderManager->getFolder(folderId);
                    if (folderId > 0 && folder.has_value()) {
                        m_notificationManager->onFolderAccessRevoked(folder->name());
                    }
                }
            });

    // Release 7 : à chaque connexion au serveur, envoie un folder_hello
    // pour récupérer les opérations manquées (rattrapage hors-ligne).
    connect(m_messagingService, &network::MessagingService::connected,
            m_folderSyncService, &core::sync::FolderSyncService::onConnectedToServer);

    // CORRECTIF (bug "l'émetteur ne transmet pas ses changements au
    // destinataire") : dès qu'un canal de diffusion (re)devient disponible
    // -- un client se connecte à nous (SERVER), ou nous nous reconnectons à
    // un SERVER (CLIENT) -- on retente toute opération locale restée
    // bloquée faute de destinataire au moment de sa diffusion initiale (cf.
    // FolderSyncService::broadcastMessage()/retryPendingBroadcasts()). Sans
    // ce câblage, une telle opération ne pouvait être rattrapée qu'en
    // modifiant à nouveau un fichier du même dossier (nouveau
    // folderReindexed), potentiellement jamais.
    connect(m_messagingServer, &network::MessagingServer::clientConnected,
            m_folderSyncService, &core::sync::FolderSyncService::retryPendingBroadcasts);
    connect(m_messagingService, &network::MessagingService::connected,
            m_folderSyncService, &core::sync::FolderSyncService::retryPendingBroadcasts);

    // Rattrapage Users (cf. Application::sendUsersCatchupTo) : un poste qui
    // rejoint le reseau APRES la creation d'un compte ne le recevait jamais
    // (le "user_event" temps reel de broadcastUserEvent n'atteint que les
    // postes deja connectes au moment de la creation). On envoie donc a
    // CHAQUE machine autorisee qui s'identifie l'integralite des comptes
    // existants, meme principe que folder_catchup_batch pour les dossiers
    // partages -- y compris une machine toute neuve sans aucun compte
    // local (userUuid vide), le cas qui bloquait tout le monde sauf le
    // poste seede en premier (cf. debrief "chicken-and-egg" login/
    // rattrapage : sendUsersCatchupTo cible alors via le certificat).
    connect(m_messagingServer, &network::MessagingServer::clientIdentified,
            this, &Application::sendUsersCatchupTo);

    // Release 8 : intégration des fichiers reçus dans les dossiers partagés.
    // transferStarted permet de corréler le transferKey avec la demande en attente ;
    // transferCompleted déclenche la copie, l'upsert SharedFile et la SyncOperation.
    connect(m_transferService, &network::TransferService::transferStarted,
            m_folderSyncService, &core::sync::FolderSyncService::onTransferStarted);
    connect(m_transferService, &network::TransferService::transferCompleted,
            m_folderSyncService, &core::sync::FolderSyncService::onTransferCompleted);

    // Alimente la progression agrégée d'une rafale de synchronisation de
    // dossier (barre de progression globale de l'UI, cf. FolderSyncService::
    // folderTransferProgress()) : no-op pour les transferts P2P manuels
    // (isFolderTransfer() false), qui gardent leur suivi individuel existant
    // via core::TransferContext (activeTransfers).
    connect(m_transferService, &network::TransferService::transferProgress,
            m_folderSyncService, &core::sync::FolderSyncService::onTransferProgress);

    // Journal de bord : log des opérations distantes reçues.
    connect(m_folderSyncService, &core::sync::FolderSyncService::remoteOpReceived,
            this, [](const QString &folderUuid, const QString &opType,
                     const QString &relativePath, const QString & /*oldRelPath*/,
                     const QString &machineId, const QHostAddress & /*addr*/,
                     quint16 /*transferPort*/) {
                qDebug() << "[App] Folder op reçu :" << opType << relativePath
                         << "dans" << folderUuid << "de" << machineId;
            });

    connect(m_folderSyncService, &core::sync::FolderSyncService::catchupBatchReceived,
            this, [](const QVector<models::FileSyncOperation> &ops) {
                qDebug() << "[App] Catch-up batch reçu :" << ops.size() << "opérations";
            });

    connect(m_folderSyncService, &core::sync::FolderSyncService::fileIntegrated,
            this, [this](const QString &folderUuid, const QString &relativePath, bool wasConflict) {
                if (m_syncEngine && m_sharedFolderManager) {
                    const auto folder = m_sharedFolderManager->getFolderByUuid(folderUuid);
                    if (folder.has_value()) {
                        m_syncEngine->suppressWatcherChanges(folder->id());
                    }
                }
                qDebug() << "[App] Fichier intégré :" << relativePath
                         << "dans" << folderUuid
                         << (wasConflict ? "(conflit renommé)" : "");
            });

    connect(m_folderSyncService, &core::sync::FolderSyncService::conflictDetected,
            this, [](const QString &folderUuid, const QString &relativePath,
                     const QString &conflictPath) {
                qWarning() << "[App] Conflit détecté dans" << folderUuid
                           << ":" << relativePath << "→" << conflictPath;
            });

    // Une seule notification "N fichiers reçus" par rafale de synchronisation
    // de dossier partagé (cf. FolderSyncService::scheduleFolderNotification),
    // au lieu d'une notification par fichier (voir plus haut, connexion de
    // TransferService::transferCompleted). Le localPath est résolu ici
    // (plutôt que porté par le signal folderFilesReceived, qui ne le
    // connaît pas) pour fusionner en un seul message le compte de fichiers
    // ET l'emplacement -- auparavant ce dernier était annoncé séparément
    // par onFolderAutoProvisioned() dès l'acceptation du partage, avant même
    // que le contenu soit là.
    connect(m_folderSyncService, &core::sync::FolderSyncService::folderFilesReceived,
            this, [this](const QString &folderUuid, const QString &folderName, int fileCount) {
                QString localPath;
                if (const auto folder = m_sharedFolderManager->getFolderByUuid(folderUuid); folder.has_value()) {
                    localPath = folder->localPath();
                }
                m_notificationManager->onFolderFilesReceived(folderUuid, folderName, fileCount, localPath);
            });

    // Symétrique côté expéditeur : une seule notification "N fichiers
    // envoyés" par rafale d'envois répondant à des folder_file_request pour
    // un même dossier partagé (cf. FolderSyncService::scheduleFolderSentNotification),
    // au lieu d'une notification par fichier -- le filtre isFolderTransfer()
    // sur la connexion de TransferService::transferCompleted plus haut couvre
    // désormais aussi ces transferts sortants.
    connect(m_folderSyncService, &core::sync::FolderSyncService::folderFilesSent,
            m_notificationManager, &core::NotificationManager::onFolderFilesSent);
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

network::ElectionService *Application::electionService() const
{
    return m_electionService;
}

network::SyncService *Application::syncService() const
{
    return m_syncService;
}

database::DatabaseManager *Application::databaseManager() const
{
    return m_databaseManager.get();
}

QVariantList Application::electionHistory(int limit) const
{
    QVariantList result;
    if (!m_serverElectionRepository)
        return result;

    const auto entries = m_serverElectionRepository->logHistory(limit);
    result.reserve(static_cast<int>(entries.size()));
    for (const auto &entry : entries) {
        QVariantMap map;
        map.insert(QStringLiteral("event"), entry.event());
        map.insert(QStringLiteral("epoch"), entry.epoch());
        map.insert(QStringLiteral("machineUuid"), entry.machineUuid());
        map.insert(QStringLiteral("createdAt"), entry.createdAt());
        result.append(map);
    }
    return result;
}

bool Application::setElectionPriorityWeight(int weight)
{
    if (!m_electionService || !m_serverElectionRepository)
        return false;

    m_electionService->setPriorityWeight(weight);
    if (!m_serverElectionRepository->updatePriorityWeight(weight)) {
        qWarning() << "Impossible de persister priority_weight :"
                   << m_serverElectionRepository->lastError();
        return false;
    }
    return true;
}

bool Application::promoteToServer()
{
    if (!m_electionService)
        return false;

    if (m_electionService->role() == models::ServerRole::Server) {
        return false; // deja serveur officiel : rien a faire
    }

    // Reutilise le mecanisme existant (nouvel epoch + diffusion
    // server_promoted(temporary=false)) ; le handler roleChanged deja
    // branche dans initialize() persiste le role en base et demarre
    // MessagingServer automatiquement.
    m_electionService->reclaimAsOfficialServer();
    return true;
}

bool Application::demoteToClient()
{
    if (!m_electionService)
        return false;

    const models::ServerRole current = m_electionService->role();
    if (current != models::ServerRole::Server && current != models::ServerRole::TempServer) {
        return false; // deja Client : rien a faire
    }

    // Demission volontaire : le handler roleChanged deja branche dans
    // initialize() persiste le nouveau role en base et arrete
    // MessagingServer automatiquement (voir shouldListen ci-dessus).
    m_electionService->stepDownToClient();
    return true;
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

core::AuditManager *Application::auditManager() const
{
    return m_auditManager;
}

core::PermissionManager *Application::permissionManager() const
{
    return m_permissionManager;
}

network::VoiceService *Application::voiceService() const
{
    return m_voiceService;
}

core::CallHistoryManager *Application::callHistoryManager() const
{
    return m_callHistoryManager;
}

core::SharedFolderManager *Application::sharedFolderManager() const
{
    return m_sharedFolderManager;
}

core::sync::SyncEngine *Application::syncEngine() const
{
    return m_syncEngine;
}

core::sync::FolderSyncService *Application::folderSyncService() const
{
    return m_folderSyncService;
}

void Application::seedDefaultAdminIfNeeded()
{
    // Garde interne : un futur appelant ne doit pas pouvoir creer un admin
    // depuis un Client ou un TempServer avant la synchronisation.
    if (!m_electionService || m_electionService->role() != models::ServerRole::Server)
        return;

    // Plus de compte "admin"/"admin123" cree d'office (mot de passe connu de tous, replique a tout
    // le reseau) : l'ecran de connexion propose de creer le premier administrateur
    // (createInitialAdmin), avec un mot de passe choisi par la personne qui installe.
    emit initialAdminStateChanged();
}

bool Application::needsInitialAdmin() const
{
    return m_userManager && m_electionService
        && m_electionService->role() == models::ServerRole::Server
        && m_userManager->allUsers().empty();
}

QString Application::createInitialAdmin(const QString &name, const QString &password,
                                        const QString &confirmation)
{
    if (!needsInitialAdmin())
        return tr("Un compte existe déjà : connectez-vous avec un compte administrateur.");
    const QString trimmedName = name.trimmed();
    if (trimmedName.isEmpty())
        return tr("Choisissez un nom d'utilisateur.");
    if (password.size() < 8)
        return tr("Le mot de passe doit contenir au moins 8 caractères.");
    if (password != confirmation)
        return tr("Les deux mots de passe ne correspondent pas.");

    const auto admin = m_userManager->createUser(trimmedName, password, /*isAdmin=*/true);
    if (!admin.has_value())
        return tr("Création du compte impossible (code %1).").arg(static_cast<int>(m_userManager->lastError()));

    // A ce stade, le role Server/TempServer de ce poste est deja stabilise
    // (seedDefaultAdminIfNeeded n'est appele que sous cette condition, cf.
    // initialize() et le handler roleChanged), donc le signal userCreated
    // -> appendUserSyncLog passerait normalement par shouldWriteSyncLog()
    // sans probleme. On force neanmoins bypassRoleCheck=true pour couvrir
    // le cas ou ce seed a lieu juste avant que ElectionService n'ait fini
    // de propager son propre etat interne : c'est le tout premier
    // utilisateur de la base et il DOIT etre connu de tout futur pair.
    appendUserSyncLog(*admin, models::SyncOperation::Insert, /*bypassRoleCheck=*/true);
    emit initialAdminStateChanged();
    return QString();
}

bool Application::shouldWriteSyncLog() const
{
    if (!m_electionService || !m_syncLogRepository) {
        return false;
    }

    const models::ServerRole role = m_electionService->role();
    return role == models::ServerRole::Server || role == models::ServerRole::TempServer;
}

void Application::appendSyncLogEntry(const QString &tableName, const QString &recordUuid,
                                     const QString &operation, const QString &payloadJson,
                                     bool bypassRoleCheck)
{
    // CORRECTIF (root cause groupes/messages invisibles) : le compte
    // admin/seed est cree AVANT que le role Server/TempServer de ce poste
    // ne soit necessairement stabilise (cf. le seed plus haut dans
    // initialize()), donc shouldWriteSyncLog() le bloquait silencieusement
    // -- admin n'etait alors JAMAIS journalise dans SyncLog. Toute
    // nouvelle instance qui rejoint plus tard ne "connait" donc jamais
    // admin (owner/sender uuid introuvable), ce qui fait echouer/differer
    // indefiniment ses groupes et jeter silencieusement ses messages.
    // bypassRoleCheck permet aux appelants qui savent que cette identite
    // DOIT etre journalisee immediatement (le seed) de contourner ce
    // garde-fou de role, sans l'affaiblir pour le reste des appels
    // normaux (creation d'utilisateur via l'UI, messages, groupes).
    if (!bypassRoleCheck && !shouldWriteSyncLog()) {
        return;
    }
    if (bypassRoleCheck && (!m_syncLogRepository || !m_electionService)) {
        return;
    }

    models::SyncLogEntry entry;
    entry.setTableName(tableName);
    entry.setRecordUuid(recordUuid);
    entry.setOperation(operation);
    entry.setPayloadJson(payloadJson);
    entry.setLamportClock(m_syncLogRepository->highestLamportClock() + 1);
    entry.setEpoch(m_electionService->epoch());
    entry.setOriginMachineId(m_electionService->localMachineUuid());
    entry.setUpdatedAt(QDateTime::currentDateTimeUtc());

    if (!m_syncLogRepository->append(entry)) {
        qWarning() << "Impossible de journaliser SyncLog" << tableName << recordUuid
                   << m_syncLogRepository->lastError();
    }
}

bool Application::isLocalAdminUuid(const QString &userUuid) const
{
    if (!m_userManager || userUuid.trimmed().isEmpty())
        return false;
    for (const auto &user : m_userManager->allUsers()) {
        if (user.uuid() == userUuid)
            return user.isAdmin();
    }
    return false;
}

bool Application::isUserEventFromAdmin() const
{
    return m_messagingServer && isLocalAdminUuid(m_messagingServer->currentSenderUserUuid());
}

QString Application::userUuidForId(qint64 userId) const
{
    if (!m_userManager) {
        return QString();
    }
    for (const auto &user : m_userManager->allUsers()) {
        if (user.id() == userId) {
            return user.uuid();
        }
    }
    return QString();
}

QString Application::conversationUuidForId(qint64 conversationId) const
{
    if (!m_databaseManager || conversationId <= 0) {
        return QString();
    }
    QSqlQuery query(m_databaseManager->database());
    query.prepare(QStringLiteral("SELECT uuid FROM Conversations WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), conversationId);
    if (!query.exec() || !query.next()) {
        return QString();
    }
    return query.value(0).toString();
}

void Application::sendIdentifyIfReady()
{
    if (!m_messagingService || !m_messagingService->isConnected()) {
        return;
    }

    QJsonObject payload;
    payload.insert(QStringLiteral("type"), QStringLiteral("identify"));
    QString localUserUuid;
    if (m_userManager) {
        const auto uid = m_userManager->currentUserId();
        if (uid.has_value()) localUserUuid = userUuidForId(static_cast<qint64>(*uid));
    }
    payload.insert(QStringLiteral("userUuid"), localUserUuid);
    payload.insert(QStringLiteral("machine_uuid"), m_discoveryService ? m_discoveryService->localId() : QString());
    payload.insert(QStringLiteral("certificate_fingerprint"),
                  m_securityService ? m_securityService->identity().fingerprintSha256 : QString());
    m_messagingService->sendMessage(QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
}

void Application::handleIncomingPayload(const QString &message, bool relay)
{
    const QJsonDocument document = QJsonDocument::fromJson(message.toUtf8());
    if (document.isObject()) {
        const QString type = document.object().value(QStringLiteral("type")).toString();
        static const QSet<QString> servicePayloadTypes = {
            QStringLiteral("folder_hello"),
            QStringLiteral("folder_catchup_request"),
            QStringLiteral("folder_catchup_batch"),
            QStringLiteral("folder_op"),
            QStringLiteral("folder_operation"),
            QStringLiteral("folder_access_granted"),
            QStringLiteral("folder_access_grant"),
            QStringLiteral("folder_resync_request"),
            QStringLiteral("folder_file_request"),
            QStringLiteral("folder_file_ready"),
            QStringLiteral("sync_request"),
            QStringLiteral("sync_batch"),
            QStringLiteral("sync_ack")
        };

        if (servicePayloadTypes.contains(type)) {
            return;
        }
    }

    if (document.isObject()
        && document.object().value(QStringLiteral("type")).toString() == QStringLiteral("audit_event")) {
        const QJsonObject object = document.object();
        models::AuditLog entry;
        entry.setEventUuid(object.value(QStringLiteral("event_uuid")).toString());
        entry.setEventType(object.value(QStringLiteral("event_type")).toString());
        entry.setDescription(object.value(QStringLiteral("description")).toString());
        // Provenance ajoutee par CE poste a partir de la connexion reelle (certificat TLS verifie,
        // utilisateur identifie), jamais a partir du contenu du message : un pair pouvait sinon
        // ecrire n'importe quel acteur dans le journal d'audit des autres.
        QString origin = object.value(QStringLiteral("actor_label")).toString();
        if (relay && m_messagingServer) {
            const QString senderUuid = m_messagingServer->currentSenderUserUuid();
            const QString fingerprint = m_messagingServer->currentSenderFingerprint();
            origin = tr("%1 (rapporté par %2)")
                         .arg(origin.isEmpty() ? tr("inconnu") : origin,
                              senderUuid.isEmpty() ? fingerprint.left(16) : senderUuid);
        }
        entry.setActorLabel(origin);
        entry.setTimestamp(QDateTime::fromString(object.value(QStringLiteral("created_at")).toString(), Qt::ISODateWithMs));
        if (m_auditManager) m_auditManager->recordRemoteEvent(entry);
        if (relay && m_messagingServer) m_messagingServer->broadcastMessage(message);
        return;
    }

    // Rattrapage Users (type "users_catchup_batch", cf.
    // Application::sendUsersCatchupTo) : envoye UNIQUEMENT au client qui
    // vient de s'identifier (sendToUuids, jamais relaye/broadcast), donc
    // pas de garde "relay" ici contrairement a user_event. Reutilise le
    // meme chemin d'application (SyncLogRepository::applyUserEntry, deja
    // idempotent et LWW) qu'un "user_event" individuel : chaque entree du
    // batch a exactement la meme forme de payload.
    if (document.isObject()
        && document.object().value(QStringLiteral("type")).toString() == QStringLiteral("users_catchup_batch")) {
        // Le rattrapage des comptes n'est emis QUE par le serveur vers ses clients. Recu par le
        // serveur (relay) depuis un client, il servirait a injecter des comptes (y compris Admin,
        // avec l'empreinte de mot de passe de son choix) : refus systematique.
        if (relay) {
            qWarning() << "handleIncomingPayload: users_catchup_batch recu d'un client, refuse";
            if (m_auditManager)
                m_auditManager->logRefusedAttempt(QStringLiteral("Rattrapage de comptes envoyé par un client (refusé)"));
            return;
        }
        const QJsonArray entriesArray = document.object().value(QStringLiteral("entries")).toArray();
        bool anyApplied = false;
        for (const QJsonValue &value : entriesArray) {
            if (!value.isObject())
                continue;
            const QJsonObject object = value.toObject();

            models::SyncLogEntry entry;
            entry.setTableName(QStringLiteral("Users"));
            entry.setRecordUuid(object.value(QStringLiteral("recordUuid")).toString());
            entry.setOperation(object.value(QStringLiteral("operation")).toString());
            entry.setOriginMachineId(object.value(QStringLiteral("originMachineId")).toString());

            QJsonObject payload = object;
            payload.remove(QStringLiteral("recordUuid"));
            payload.remove(QStringLiteral("operation"));
            payload.remove(QStringLiteral("originMachineId"));
            entry.setPayloadJson(QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));

            if (m_syncLogRepository && m_syncLogRepository->applyUserEntry(entry)) {
                anyApplied = true;
            } else if (m_syncLogRepository) {
                qWarning() << "handleIncomingPayload: echec application entree de users_catchup_batch"
                           << m_syncLogRepository->lastError();
            }
        }
        if (anyApplied && m_userManager) {
            // Qt::QueuedConnection : meme precaution que pour user_event,
            // applyUserEntry() peut etre appele depuis le thread reseau.
            QMetaObject::invokeMethod(m_userManager, [this]() {
                m_userManager->emitUsersChanged();
            }, Qt::QueuedConnection);
        }
        return;
    }

    // Diffusion temps reel de la creation/mise a jour d'un utilisateur (type
    // "user_event", cf. Application::broadcastUserEvent) : sans ce relais,
    // un nouvel utilisateur cree sur un poste n'apparaissait chez les pairs
    // deja connectes qu'a la prochaine reconciliation SyncLog, c'est-a-dire
    // en pratique jamais avant un redemarrage de l'app (meme mecanisme que
    // le correctif deja en place pour "group_created"/"authorized_machine_event").
    if (document.isObject()
        && document.object().value(QStringLiteral("type")).toString() == QStringLiteral("user_event")) {
        // Cote serveur (relay), le changement vient d'un client : il n'est accepte que d'une
        // connexion identifiee comme un compte Admin connu ici. Sans ce controle, n'importe quel
        // poste autorise pouvait creer un Admin, changer le mot de passe ou le role d'un compte,
        // ou le supprimer, puis le faire relayer a tout le reseau. Cote client, le message vient
        // du serveur, dont le certificat a ete verifie : il fait autorite.
        if (relay && !isUserEventFromAdmin()) {
            qWarning() << "handleIncomingPayload: user_event refuse (emetteur non administrateur)";
            if (m_auditManager)
                m_auditManager->logRefusedAttempt(QStringLiteral("Modification de compte par un non-administrateur (refusée)"));
            return;
        }
        const QJsonObject object = document.object();
        models::SyncLogEntry entry;
        entry.setTableName(QStringLiteral("Users"));
        entry.setRecordUuid(object.value(QStringLiteral("recordUuid")).toString());
        entry.setOperation(object.value(QStringLiteral("operation")).toString());
        entry.setOriginMachineId(object.value(QStringLiteral("originMachineId")).toString());
        // payload : reutilise exactement les memes champs (name/ipAddress/
        // status/role/passwordHash/passwordSalt/updatedAt) que
        // Application::appendUserSyncLog, afin que
        // SyncLogRepository::applyUserEntry (deja idempotent et dote de la
        // logique anti-collision de nom) puisse s'appliquer telle quelle.
        QJsonObject payload = object;
        payload.remove(QStringLiteral("type"));
        payload.remove(QStringLiteral("recordUuid"));
        payload.remove(QStringLiteral("operation"));
        payload.remove(QStringLiteral("originMachineId"));
        entry.setPayloadJson(QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));

        const bool applied = m_syncLogRepository && m_syncLogRepository->applyUserEntry(entry);
        if (applied && m_userManager) {
            // Qt::QueuedConnection : meme precaution que pour
            // reconciliationCompleted plus haut, applyUserEntry() peut etre
            // appele depuis le thread reseau.
            QMetaObject::invokeMethod(m_userManager, [this]() {
                m_userManager->emitUsersChanged();
            }, Qt::QueuedConnection);
        } else if (!applied) {
            qWarning() << "handleIncomingPayload: echec application user_event"
                       << (m_syncLogRepository ? m_syncLogRepository->lastError() : QStringLiteral("(pas de SyncLogRepository)"));
        }
        if (relay && m_messagingServer) m_messagingServer->broadcastMessage(message);
        return;
    }

    // Diffusion temps reel des entrees ServerElectionLog (type
    // "server_election_event", cf. Application::broadcastServerElectionEvent) :
    // corrige la divergence silencieuse entre instances de ServerElection/
    // ServerElectionLog (celles-ci n'etaient jusque-la jamais repliquees,
    // contrairement a Users/Groups/AuthorizedMachines/AuditLogs).
    // applyRemoteLogEntry est idempotent sur log_uuid (rejeu/relais en
    // etoile sans risque de doublon). bumpEpochIfNewer n'ecrase jamais
    // current_role : le role de CE poste reste determine localement par son
    // propre ElectionService, jamais copie depuis un pair.
    if (document.isObject()
        && document.object().value(QStringLiteral("type")).toString() == QStringLiteral("server_election_event")) {
        const QJsonObject object = document.object();
        models::ServerElectionLogEntry entry;
        entry.setLogUuid(object.value(QStringLiteral("log_uuid")).toString());
        entry.setEvent(object.value(QStringLiteral("event")).toString());
        entry.setEpoch(object.value(QStringLiteral("epoch")).toInt());
        entry.setMachineUuid(object.value(QStringLiteral("machine_uuid")).toString());
        entry.setCreatedAt(QDateTime::fromString(object.value(QStringLiteral("created_at")).toString(), Qt::ISODate));

        const bool applied = m_serverElectionRepository && m_serverElectionRepository->applyRemoteLogEntry(entry);
        if (applied && m_serverElectionRepository) {
            m_serverElectionRepository->bumpEpochIfNewer(entry.epoch());
        } else if (!applied) {
            qWarning() << "handleIncomingPayload: echec application server_election_event"
                       << (m_serverElectionRepository ? m_serverElectionRepository->lastError()
                                                        : QStringLiteral("(pas de ServerElectionRepository)"));
        }
        if (relay && m_messagingServer) m_messagingServer->broadcastMessage(message);
        return;
    }

    // Messages de groupe en temps reel. CORRECTIF : ce traitement se trouvait APRES le bloc
    // "message" ci-dessous, qui se termine par un "return" inconditionnel -- il n'etait donc
    // JAMAIS execute. Consequence : la creation d'un groupe et l'ajout/retrait d'un membre
    // n'arrivaient aux autres postes qu'a la prochaine reconciliation complete (en pratique, au
    // redemarrage de l'application). On les traite desormais en premier, par type explicite.
    if (document.isObject()) {
        const QString type = document.object().value(QStringLiteral("type")).toString();

        if (type == QStringLiteral("group_created")) {
            if (const auto group = m_groupManager->receiveGroupCreated(message); group.has_value()) {
                m_notificationManager->onGroupCreated(*group);
            }
            // Relais aux SEULS membres annonces (le payload contient deja leurs uuid), plutot
            // qu'a tous les clients connectes : la composition d'un groupe ne regarde que ses
            // membres (meme principe que pour les messages, cf. plus bas).
            if (relay && m_messagingServer) {
                QStringList targets;
                const QJsonObject object = document.object();
                const QString ownerUuid = object.value(QStringLiteral("ownerUuid")).toString();
                if (!ownerUuid.isEmpty()) targets << ownerUuid;
                for (const auto &value : object.value(QStringLiteral("memberUuids")).toArray()) {
                    const QString uuid = value.toString();
                    if (!uuid.isEmpty()) targets << uuid;
                }
                targets.removeDuplicates();
                if (!targets.isEmpty()) m_messagingServer->sendToUuids(message, targets);
                else m_messagingServer->broadcastMessage(message);
            }
            return;
        }

        if (type == QStringLiteral("member_added") || type == QStringLiteral("member_removed")) {
            const QString groupUuid = document.object().value(QStringLiteral("groupUuid")).toString();
            // Destinataires releves AVANT application : pour un retrait, la personne concernee
            // doit encore recevoir l'annonce qui la retire du groupe.
            QStringList targets = groupMemberUuids(groupUuid);
            const QString memberUuid = document.object().value(QStringLiteral("memberUuid")).toString();
            if (!memberUuid.isEmpty()) targets << memberUuid;
            targets.removeDuplicates();

            const bool applied = type == QStringLiteral("member_added")
                ? m_groupManager->receiveMemberAdded(message)
                : m_groupManager->receiveMemberRemoved(message);
            if (!applied) {
                qWarning() << "handleIncomingPayload:" << type << "non applique :"
                           << m_groupManager->lastErrorString();
            }
            if (relay && m_messagingServer) {
                if (!targets.isEmpty()) m_messagingServer->sendToUuids(message, targets);
                else m_messagingServer->broadcastMessage(message);
            }
            return;
        }
    }

    // MessagingManager ne traite que les messages de type "message".
    // SyncService traite de son cote les messages de type "sync_request",
    // "sync_ack", "sync_batch" (connecte separement sur les memes signaux).
    // CORRECTIF : verifier si l'utilisateur local est reellement participant
    // de la conversation avant de persister et notifier localement. Sans
    // cette verification, le serveur (relay=true) persiste TOUS les messages
    // qui transitent par lui, meme ceux entre deux autres clients, et
    // notifie l'utilisateur connecte sur la machine serveur pour des
    // conversations qui ne le concernent pas.
    const bool shouldPersistLocally = m_messagingManager->isLocalUserParticipant(message);

    if (shouldPersistLocally) {
        m_messagingManager->receiveMessage(message);
    }

    if (relay && m_messagingServer) {
        // Rediffuse UNIQUEMENT aux destinataires reels (participants de
        // la conversation ou membres du groupe), et non plus a tous les
        // clients connectes (issue #2 : un tiers non concerne recevait
        // et persistait silencieusement le message dans sa propre
        // base). resolveTargetUuidsFromPayload() s'appuie sur les uuids
        // stables presents dans le payload (et, pour un groupe, sur
        // notre propre table Groups/GroupMembers resolue via
        // conversationUuid).
        const QStringList targetUuids = m_messagingManager->resolveTargetUuidsFromPayload(message);
        if (!targetUuids.isEmpty()) {
            m_messagingServer->sendToUuids(message, targetUuids);
        } else {
            // Repli de securite : mieux vaut sur-diffuser (comportement
            // historique) que perdre le message si on n'a pas su
            // resoudre le moindre destinataire.
            qWarning() << "handleIncomingPayload: aucun destinataire resolu, repli sur broadcastMessage()";
            m_messagingServer->broadcastMessage(message);
        }
    }
}

QStringList Application::groupMemberUuids(const QString &groupUuid) const
{
    QStringList uuids;
    if (groupUuid.isEmpty() || !m_databaseManager)
        return uuids;
    QSqlQuery query(m_databaseManager->database());
    query.prepare(QStringLiteral(
        "SELECT u.uuid FROM GroupMembers gm "
        "JOIN Users u ON u.id = gm.user_id "
        "JOIN Groups g ON g.id = gm.group_id "
        "WHERE g.uuid = :uuid AND u.uuid IS NOT NULL AND u.uuid <> ''"));
    query.bindValue(QStringLiteral(":uuid"), groupUuid);
    if (!query.exec()) {
        qWarning() << "groupMemberUuids: requete en echec" << query.lastError().text();
        return uuids;
    }
    while (query.next())
        uuids << query.value(0).toString();
    return uuids;
}

void Application::appendMessageSyncLog(const models::Message &message)
{
    // record_uuid = uuid propre du message (independant de son id local),
    // et les references croisees (senderUuid/conversationUuid) aussi en
    // uuid : cf. migration 011 et SyncLogRepository::applyMessageEntry, qui
    // resolvent ces uuid vers les id locaux du poste destinataire plutot
    // que de reutiliser tel quel l'id de la machine d'origine (id qui n'a
    // aucune raison de coincider entre deux bases SQLite independantes).
    if (message.uuid().isEmpty()) {
        qWarning() << "appendMessageSyncLog : message sans uuid, entree ignoree" << message.id();
        return;
    }

    const QString senderUuid = userUuidForId(message.senderId());
    const QString conversationUuid = conversationUuidForId(message.conversationId());
    if (senderUuid.isEmpty() || conversationUuid.isEmpty()) {
        qWarning() << "appendMessageSyncLog : sender/conversation non resolu en uuid, entree ignoree"
                   << message.id();
        return;
    }

    // uuids stables des deux participants de la conversation : necessaires
    // a SyncLogRepository::applyMessageEntry pour renseigner
    // participant1_id/participant2_id lors de la reconciliation (cf.
    // ensureConversationByUuid), sans quoi la conversation reconciliee
    // reste invisible dans MessagingManager::getUserConversations().
    QString participant1Uuid;
    QString participant2Uuid;
    if (m_databaseManager) {
        QSqlQuery convQuery(m_databaseManager->database());
        convQuery.prepare(QStringLiteral(
            "SELECT participant1_id, participant2_id FROM Conversations WHERE id = :id"));
        convQuery.bindValue(QStringLiteral(":id"), message.conversationId());
        if (convQuery.exec() && convQuery.next()) {
            participant1Uuid = userUuidForId(convQuery.value(0).toLongLong());
            participant2Uuid = userUuidForId(convQuery.value(1).toLongLong());
        }
    }

    QJsonObject payload;
    payload.insert(QStringLiteral("senderUuid"), senderUuid);
    payload.insert(QStringLiteral("conversationUuid"), conversationUuid);
    payload.insert(QStringLiteral("participant1Uuid"), participant1Uuid);
    payload.insert(QStringLiteral("participant2Uuid"), participant2Uuid);
    payload.insert(QStringLiteral("content"), message.content());
    payload.insert(QStringLiteral("isRead"), message.isRead());
    payload.insert(QStringLiteral("timestamp"),
                   message.timestamp().isValid()
                       ? message.timestamp().toUTC().toString(Qt::ISODate)
                       : QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    appendSyncLogEntry(QStringLiteral("Messages"),
                       message.uuid(),
                       models::SyncOperation::Insert,
                       QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
}

void Application::appendGroupSyncLog(const models::Group &group, const QString &operation)
{
    // Meme principe que appendMessageSyncLog ci-dessus : record_uuid = uuid
    // propre du groupe, et toutes les references croisees (ownerUuid,
    // conversationUuid, memberUuids) en uuid plutot qu'en id local.
    if (group.uuid().isEmpty()) {
        qWarning() << "appendGroupSyncLog : groupe sans uuid, entree ignoree" << group.name();
        return;
    }

    const QString ownerUuid = userUuidForId(group.ownerId());
    const QString conversationUuid = conversationUuidForId(group.conversationId());
    if (ownerUuid.isEmpty()) {
        qWarning() << "appendGroupSyncLog : owner non resolu en uuid, entree ignoree" << group.name();
        return;
    }

    QJsonArray memberUuids;
    for (qint64 memberId : group.memberIds()) {
        const QString memberUuid = userUuidForId(memberId);
        if (!memberUuid.isEmpty()) {
            memberUuids.append(memberUuid);
        }
    }

    QJsonObject payload;
    payload.insert(QStringLiteral("name"), group.name());
    payload.insert(QStringLiteral("ownerUuid"), ownerUuid);
    payload.insert(QStringLiteral("conversationUuid"), conversationUuid);
    payload.insert(QStringLiteral("memberUuids"), memberUuids);

    appendSyncLogEntry(QStringLiteral("Groups"),
                       group.uuid(),
                       operation,
                       QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
}

void Application::appendUserSyncLog(const models::User &user, const QString &operation, bool bypassRoleCheck)
{
    // Le uuid (pas l'id auto-incremente) sert de record_uuid : c'est ce que
    // SyncLogRepository::applyUserEntry utilise pour retrouver la bonne ligne
    // cote pair, l'id local n'ayant aucune raison de coincider entre postes
    // (cf. la note de reconciliation Users, section 1).
    if (user.uuid().isEmpty()) {
        qWarning() << "appendUserSyncLog : utilisateur sans uuid, entree ignoree" << user.name();
        return;
    }

    QJsonObject payload;
    payload.insert(QStringLiteral("name"), user.name());
    payload.insert(QStringLiteral("ipAddress"), user.ipAddress());
    payload.insert(QStringLiteral("status"), models::userStatusToString(user.status()));
    payload.insert(QStringLiteral("role"), models::userRoleToString(user.role()));
    payload.insert(QStringLiteral("passwordHash"), user.passwordHash());
    payload.insert(QStringLiteral("passwordSalt"), user.passwordSalt());
    payload.insert(QStringLiteral("updatedAt"),
                   user.updatedAt().isValid()
                       ? user.updatedAt().toUTC().toString(Qt::ISODate)
                       : QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    appendSyncLogEntry(QStringLiteral("Users"),
                       user.uuid(),
                       operation,
                       QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)),
                       bypassRoleCheck);
}

void Application::broadcastUserEvent(const models::User &user, const QString &operation)
{
    if (user.uuid().isEmpty()) {
        qWarning() << "broadcastUserEvent : utilisateur sans uuid, diffusion ignoree" << user.name();
        return;
    }
    if (!m_messagingService && !m_messagingServer) {
        return;
    }

    // Memes champs que appendUserSyncLog (cf. juste au-dessus), afin que
    // handleIncomingPayload() puisse construire un models::SyncLogEntry et
    // le passer tel quel a SyncLogRepository::applyUserEntry cote reception.
    QJsonObject payload;
    payload.insert(QStringLiteral("type"), QStringLiteral("user_event"));
    payload.insert(QStringLiteral("recordUuid"), user.uuid());
    payload.insert(QStringLiteral("operation"), operation);
    payload.insert(QStringLiteral("originMachineId"),
                   m_electionService ? m_electionService->localMachineUuid() : QString());
    payload.insert(QStringLiteral("name"), user.name());
    payload.insert(QStringLiteral("ipAddress"), user.ipAddress());
    payload.insert(QStringLiteral("status"), models::userStatusToString(user.status()));
    payload.insert(QStringLiteral("role"), models::userRoleToString(user.role()));
    payload.insert(QStringLiteral("passwordHash"), user.passwordHash());
    payload.insert(QStringLiteral("passwordSalt"), user.passwordSalt());
    payload.insert(QStringLiteral("updatedAt"),
                   user.updatedAt().isValid()
                       ? user.updatedAt().toUTC().toString(Qt::ISODate)
                       : QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    const QString jsonMessage = QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));

    // Envoi sur les deux canaux (cf. GroupManager::createGroup) : ce poste
    // peut etre le SERVER actif (m_messagingServer diffuse alors directement
    // a tous les clients connectes) OU un simple CLIENT (seul
    // m_messagingService, la connexion sortante vers le SERVER, permet
    // alors de faire parvenir l'evenement a qui que ce soit).
    if (m_messagingService && m_messagingService->isConnected()) {
        m_messagingService->sendMessage(jsonMessage);
    }
    if (m_messagingServer) {
        m_messagingServer->broadcastMessage(jsonMessage);
    }
}

void Application::sendUsersCatchupTo(const QString &userUuid, const QString &fingerprint, bool authorized)
{
    // Seul un poste qui ecoute reellement (Server/TempServer, donc dote
    // d'un MessagingServer actif) peut recevoir ce signal : un simple
    // Client n'a jamais de MessagingServer demarre (cf. shouldListen dans
    // le handler roleChanged de initialize()).
    if (!m_messagingServer || !m_userManager)
        return;
    if (!authorized)
        return; // machine pas encore autorisee : rien a lui envoyer
    if (userUuid.isEmpty() && fingerprint.isEmpty())
        return; // rien pour cibler cette connexion

    const std::vector<models::User> users = m_userManager->allUsers();
    if (users.empty())
        return;

    QJsonArray entries;
    for (const models::User &user : users) {
        if (user.uuid().isEmpty())
            continue; // meme garde que broadcastUserEvent/appendUserSyncLog

        // Meme forme de payload que broadcastUserEvent, afin que
        // handleIncomingPayload() applique chaque entree via exactement le
        // meme chemin ("user_event") deja idempotent et LWW (cf.
        // SyncLogRepository::applyUserEntry).
        QJsonObject entry;
        entry.insert(QStringLiteral("recordUuid"), user.uuid());
        // "UPDATE" et non un "upsert" inexistant : models::SyncOperation ne
        // connait que INSERT/UPDATE/DELETE (models/SyncLogEntry.h). Avec
        // "upsert", applyUserEntry() tombait dans sa branche "operation
        // inconnue" et ne faisait RIEN (tout en retournant true), rendant ce
        // rattrapage silencieusement inoperant. "UPDATE" convient ici car
        // applyUserEntry() retombe deja tout seul sur un INSERT quand le
        // compte n'existe pas encore localement (cf. SyncLogRepository.cpp),
        // exactement la semantique upsert voulue pour un catchup.
        entry.insert(QStringLiteral("operation"), models::SyncOperation::Update);
        entry.insert(QStringLiteral("originMachineId"),
                     m_electionService ? m_electionService->localMachineUuid() : QString());
        entry.insert(QStringLiteral("name"), user.name());
        entry.insert(QStringLiteral("ipAddress"), user.ipAddress());
        entry.insert(QStringLiteral("status"), models::userStatusToString(user.status()));
        entry.insert(QStringLiteral("role"), models::userRoleToString(user.role()));
        entry.insert(QStringLiteral("passwordHash"), user.passwordHash());
        entry.insert(QStringLiteral("passwordSalt"), user.passwordSalt());
        entry.insert(QStringLiteral("updatedAt"),
                     user.updatedAt().isValid()
                         ? user.updatedAt().toUTC().toString(Qt::ISODate)
                         : QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
        entries.append(entry);
    }

    if (entries.isEmpty())
        return;

    QJsonObject batch;
    batch.insert(QStringLiteral("type"), QStringLiteral("users_catchup_batch"));
    batch.insert(QStringLiteral("entries"), entries);

    const QString jsonMessage = QString::fromUtf8(QJsonDocument(batch).toJson(QJsonDocument::Compact));

    // Cible uniquement le client qui vient de s'identifier, jamais un
    // broadcast a tous : les autres postes deja connectes ont deja leur
    // propre copie a jour, pas besoin de la leur renvoyer. Un poste tout
    // neuf (userUuid vide, cf. commentaire de la fonction) ne peut etre
    // atteint que par son certificat, seul identifiant connu du serveur
    // avant tout login reussi.
    if (!userUuid.isEmpty()) {
        m_messagingServer->sendToUuids(jsonMessage, {userUuid});
    } else {
        m_messagingServer->sendToFingerprint(jsonMessage, fingerprint);
    }
}

void Application::broadcastServerElectionEvent(const QString &logUuid, const QString &event, int epoch,
                                                const QString &machineUuid, const QDateTime &createdAt)
{
    if (logUuid.isEmpty()) {
        qWarning() << "broadcastServerElectionEvent : log_uuid manquant, diffusion ignoree" << event;
        return;
    }
    if (!m_messagingService && !m_messagingServer) {
        return;
    }

    // Memes champs que models::ServerElectionLogEntry, afin que
    // handleIncomingPayload() puisse reconstruire l'entree telle quelle et
    // la passer a ServerElectionRepository::applyRemoteLogEntry (idempotent
    // sur log_uuid, cf. migration 032) cote reception.
    QJsonObject payload;
    payload.insert(QStringLiteral("type"), QStringLiteral("server_election_event"));
    payload.insert(QStringLiteral("log_uuid"), logUuid);
    payload.insert(QStringLiteral("event"), event);
    payload.insert(QStringLiteral("epoch"), epoch);
    payload.insert(QStringLiteral("machine_uuid"), machineUuid);
    payload.insert(QStringLiteral("created_at"),
                   createdAt.isValid()
                       ? createdAt.toUTC().toString(Qt::ISODate)
                       : QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    const QString jsonMessage = QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));

    // Envoi sur les deux canaux (cf. broadcastUserEvent) : ce poste peut
    // etre le SERVER actif (m_messagingServer diffuse alors directement a
    // tous les clients connectes) OU un simple CLIENT/TEMP_SERVER (seul
    // m_messagingService, la connexion sortante vers le SERVER, permet
    // alors de faire parvenir l'evenement a qui que ce soit).
    if (m_messagingService && m_messagingService->isConnected()) {
        m_messagingService->sendMessage(jsonMessage);
    }
    if (m_messagingServer) {
        m_messagingServer->broadcastMessage(jsonMessage);
    }
}

network::DiscoveryService *Application::discoveryService() const
{
    return m_discoveryService;
}

QString Application::pendingServerFingerprint() const { return m_pendingServerFingerprint; }
QString Application::pendingServerAddress() const { return m_pendingServerAddress; }
int Application::pendingServerPort() const { return m_pendingServerPort; }
int Application::pendingClientCount() const
{
    return m_permissionManager ? m_permissionManager->pendingClientCount() : 0;
}

bool Application::approvePendingServerCertificate()
{
    if (!m_permissionManager || !m_messagingService
        || m_pendingServerFingerprint.isEmpty() || m_pendingServerAddress.isEmpty())
        return false;

    const bool approved = m_permissionManager->approveServerCertificate(
        m_pendingServerFingerprint, m_pendingServerAddress, QStringLiteral("Serveur détecté"));
    if (approved) {
        // Le certificat est desormais approuve : plus de raison d'attendre
        // le reste du cooldown de reconciliation (cf. m_lastReconciliationAttemptMs
        // dans Application.h) avant une eventuelle reconciliation a venir.
        m_lastReconciliationAttemptMs = 0;
        // La QWebSocket precedente peut encore etre en fermeture au moment
        // du clic. Une reprise differee evite d'ouvrir pendant ClosingState.
        QTimer::singleShot(100, m_messagingService, [service = m_messagingService]() {
            service->retryLastHost();
        });
    }
    return approved;
}