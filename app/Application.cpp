#include "Application.h"

#include <QDebug>
#include <QHostAddress>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlQuery>
#include <QVariantMap>
#include <QVariantList>

#include "DatabaseManager.h"
#include "UserManager.h"
#include "MessagingManager.h"
#include "GroupManager.h"
#include "TransferManager.h"
#include "NotificationManager.h"
#include "AuditManager.h"
#include "CallHistoryManager.h"
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
#include "database/Repositories/ServerElectionRepository.h"
#include "database/Repositories/SyncLogRepository.h"
#include "database/Repositories/GroupRepository.h"
#include "models/ServerElection.h"
#include "models/Message.h"
#include "models/Group.h"
#include "models/SyncLogEntry.h"

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
    // utilise "collablan_db" pour tout le monde, ce qui casse silencieusement
    // (connexion partagee/ecrasee) des qu'on instancie plusieurs Application
    // dans le meme process, comme le font les tests d'integration multi-
    // postes (HYBRID_SERVER_FAILOVER.md section 9, etape 3).
    m_databaseManager = std::make_unique<database::DatabaseManager>(
        QStringLiteral("collablan_db_%1").arg(reinterpret_cast<quintptr>(this)));
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

    connect(m_messagingManager, &core::MessagingManager::messageSent,
            this, &Application::appendMessageSyncLog);
    connect(m_messagingManager, &core::MessagingManager::messageReceived,
            this, &Application::appendMessageSyncLog);

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
            });
    connect(m_userManager, &core::UserManager::userUpdated,
            this, [this](const models::User &user) {
                appendUserSyncLog(user, models::SyncOperation::Update);
            });
    connect(m_userManager, &core::UserManager::userDeleted,
            this, [this](const QString &uuid, int id) {
                Q_UNUSED(id)
                appendSyncLogEntry(QStringLiteral("Users"), uuid, models::SyncOperation::Delete, QString());
            });
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
                    return; // deja connecte au bon serveur, rien a faire
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

                m_messagingService->disconnectFromHost();
                if (!m_messagingService->connectToHost(newServerAddress, newServerPort)) {
                    qWarning() << "Reconnexion au nouveau serveur actif impossible :" << newServerAddress << newServerPort;
                }
            });

    connect(m_electionService, &network::ElectionService::heartbeatLost,
            this, [this]() {
                m_serverElectionRepository->appendLogEntry(models::ServerElectionEvent::HeartbeatLost,
                                                           m_electionService->epoch(),
                                                           m_electionService->activeServerUuid());
            });

    connect(m_electionService, &network::ElectionService::serverPromoted,
            this, [this](int epoch, const QString &machineUuid, bool temporary) {
                m_serverElectionRepository->updateRoleAndEpoch(m_electionService->role(), epoch);
                m_serverElectionRepository->updateActiveServer(m_electionService->activeServerAddress().toString(),
                                                               machineUuid,
                                                               QDateTime::currentDateTimeUtc());
                m_serverElectionRepository->appendLogEntry(temporary ? models::ServerElectionEvent::TempPromoted
                                                                      : models::ServerElectionEvent::ServerRestored,
                                                           epoch,
                                                           machineUuid);
            });

    connect(m_electionService, &network::ElectionService::reconciliationRequired,
            this, [this](const QString &tempServerUuid) {
                const QHostAddress tempServerAddress = m_electionService->activeServerAddress();
                const quint16 tempServerPort = m_electionService->activeServerPort();
                if (tempServerAddress.isNull() || tempServerPort == 0) {
                    qWarning() << "Reconciliation impossible: adresse/port TEMP_SERVER inconnu pour" << tempServerUuid;
                    return;
                }

                const int fromEpoch = m_electionService->epoch();
                const QString localUuid = m_electionService->localMachineUuid();
                connect(m_messagingService, &network::MessagingService::connected,
                        m_syncService, [this, fromEpoch, localUuid]() {
                            m_syncService->requestReconciliation(fromEpoch, localUuid);
                        }, Qt::SingleShotConnection);

                if (!m_messagingService->connectToHost(tempServerAddress, tempServerPort)) {
                    qWarning() << "Reconciliation impossible: connexion au TEMP_SERVER refusee"
                               << tempServerAddress << tempServerPort;
                }
            });

    connect(m_syncService, &network::SyncService::reconciliationCompleted,
            this, [this](int mergedEntryCount) {
                qDebug() << "Reconciliation terminee, entrees fusionnees:" << mergedEntryCount;
                m_serverElectionRepository->appendLogEntry(models::ServerElectionEvent::ServerReconciled,
                                                           m_electionService->epoch(),
                                                           m_electionService->activeServerUuid());
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
            this, [](const QString &reason) {
                qWarning() << "Reconciliation echouee:" << reason;
            });

    if (!m_electionService->start()) {
        qWarning() << "Impossible de demarrer ElectionService";
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

    // Initialiser le PermissionManager pour la gestion des rôles (issue #67)
    // et des machines autorisées (issue #68).
    m_permissionManager = new core::PermissionManager(m_databaseManager.get(), this);

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
    m_discoveryService->setPermissionManager(m_permissionManager);
    m_discoveryService->setTransferPort(static_cast<quint16>(messagingServerPort + 1));
    m_discoveryService->setSignalingPort(static_cast<quint16>(messagingServerPort + 2));
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
            }, Qt::QueuedConnection);
    connect(m_discoveryService, &network::DiscoveryService::peerLost,
            m_notificationManager, [this](const network::DiscoveredPeer &peer) {
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
                });
    }

    if (!m_discoveryService->start()) {
        qWarning() << "Impossible de demarrer DiscoveryService (port deja utilise ?)";
    }

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

    // TransferManager a ete instancie plus haut (avant DiscoveryService) :
    // on ne peut lui fournir la resolution de peer_name (migration #015)
    // qu'a partir d'ici, une fois m_discoveryService pret.
    if (m_transferManager) {
        m_transferManager->setDiscoveryService(m_discoveryService);
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

bool Application::shouldWriteSyncLog() const
{
    if (!m_electionService || !m_syncLogRepository) {
        return false;
    }

    const models::ServerRole role = m_electionService->role();
    return role == models::ServerRole::Server || role == models::ServerRole::TempServer;
}

void Application::appendSyncLogEntry(const QString &tableName, const QString &recordUuid,
                                     const QString &operation, const QString &payloadJson)
{
    if (!shouldWriteSyncLog()) {
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

void Application::handleIncomingPayload(const QString &message, bool relay)
{
    // MessagingManager ne traite que les messages de type "message".
    // SyncService traite de son cote les messages de type "sync_request",
    // "sync_ack", "sync_batch" (connecte separement sur les memes signaux).
    if (m_messagingManager->receiveMessage(message)) {
        if (relay && m_messagingServer) {
            // Rediffuse a tous les clients connectes a NOTRE serveur (y
            // compris, potentiellement, vers l'expediteur d'origine : sans
            // gravite, MessagingManager::receiveMessage() deduplique par
            // uuid, cf. m_repository.findByUuid ci-dessus). C'est ce relais
            // qui manquait : jusqu'ici le SERVER se contentait de persister
            // le message dans SA PROPRE base sans jamais le retransmettre,
            // si bien qu'un destinataire connecte en CLIENT au meme SERVER
            // ne le recevait jamais.
            m_messagingServer->broadcastMessage(message);
        }
        return;
    }

    // Pas un message : peut-etre la creation d'un groupe diffusee en
    // temps reel par un autre poste (type "group_created", cf.
    // GroupManager::createGroup) - sans ce relais, les autres membres
    // n'apprenaient l'existence du groupe qu'a la prochaine
    // reconciliation SyncLog.
    if (const auto group = m_groupManager->receiveGroupCreated(message); group.has_value()) {
        m_notificationManager->onGroupCreated(*group);
        if (relay && m_messagingServer) {
            m_messagingServer->broadcastMessage(message);
        }
        return;
    }

    // Ce n'est pas forcément une erreur : peut-être un message de sync
    qDebug() << "Message ignore par MessagingManager/GroupManager (probablement message de sync) :" << message.left(100);
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

void Application::appendUserSyncLog(const models::User &user, const QString &operation)
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
                       QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)));
}