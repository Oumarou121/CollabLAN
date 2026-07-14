#include "FolderSyncService.h"

#include "core/SharedFolderManager.h"
#include "core/UserManager.h"
#include "database/DatabaseManager.h"
#include "models/SharedFolder.h"
#include "models/SharedFile.h"
#include "models/SyncChangeType.h"
#include "Messaging/MessagingServer.h"
#include "Messaging/MessagingService.h"
#include "Transfer/TransferService.h"
#include "Discovery/DiscoveryService.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QDateTime>
#include <QCryptographicHash>

namespace core::sync {

namespace {

constexpr const char *kTypeFolderOp       = "folder_op";
constexpr const char *kTypeFolderHello    = "folder_hello";
constexpr const char *kTypeCatchupBatch   = "folder_catchup_batch";
constexpr const char *kTypeFileRequest    = "folder_file_request";
constexpr const char *kTypeAccessGranted  = "folder_access_granted";
constexpr const char *kTypeAccessRevoked  = "folder_access_revoked";
constexpr const char *kTypeResyncRequest  = "folder_resync_request";

} // namespace

FolderSyncService::FolderSyncService(database::DatabaseManager *dbManager,
                                      core::SharedFolderManager *folderManager,
                                      QObject *parent)
    : QObject(parent)
    , m_repository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_fileRepository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_accessRepository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_userRepository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_folderManager(folderManager)
{
    m_lastBroadcastOpId = m_repository.latestId();
}

FolderSyncService::~FolderSyncService() = default;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

void FolderSyncService::setMessagingServer(network::MessagingServer *server)
{
    if (m_messagingServer == server) return;
    m_messagingServer = server;
    if (m_messagingServer) {
        connect(m_messagingServer, &network::MessagingServer::messageReceived,
                this, &FolderSyncService::onServerMessageReceived);
    }
}

void FolderSyncService::setMessagingService(network::MessagingService *service)
{
    if (m_messagingService == service) return;
    m_messagingService = service;
    if (m_messagingService) {
        connect(m_messagingService, &network::MessagingService::messageReceived,
                this, &FolderSyncService::onClientMessageReceived);
    }
}

void FolderSyncService::setTransferService(network::TransferService *transfer)
{
    m_transferService = transfer;
}

void FolderSyncService::setDiscoveryService(network::DiscoveryService *discovery)
{
    m_discoveryService = discovery;
}

void FolderSyncService::setLocalMachineId(const QString &machineId)
{
    m_machineId = machineId;
}

void FolderSyncService::setLocalUserId(qint64 userId)
{
    m_localUserId = userId;
}

void FolderSyncService::setUserManager(core::UserManager *userManager)
{
    m_userManager = userManager;
}

// ---------------------------------------------------------------------------
// Helpers d'autorisation
// ---------------------------------------------------------------------------

models::SharedFolderPermission FolderSyncService::effectivePermission(
    const models::SharedFolder &folder, const QString &peerMachineId) const
{
    // Résolution machineId → utilisateur (uuid = identifiant réseau du compte).
    const auto user = m_userRepository.findByUuid(peerMachineId);
    if (!user.has_value()) {
        // Identité non résolue (aucun compte local ne correspond au machineId).
        // Politique "fail-open" : on ne peut pas confirmer une révocation pour
        // un utilisateur inconnu -- on laisse passer plutôt que de bloquer
        // arbitrairement un pair légitime dont le compte n'est pas enregistré
        // localement. La sécurité périmètre repose sur l'isolation du LAN.
        return models::SharedFolderPermission::Write;
    }
    // Le propriétaire du dossier a toujours accès complet.
    if (user->id() == static_cast<int>(folder.ownerId())) {
        return models::SharedFolderPermission::Write;
    }
    // Pour un utilisateur connu, interroge les droits explicites.
    // None = révocation confirmée → le pair est bloqué.
    return m_accessRepository.permissionFor(folder.id(), user->id());
}

void FolderSyncService::cleanupRevokedFolder(const models::SharedFolder &folder)
{
    if (!m_folderManager) return;

    // Supprime les fichiers locaux indexés pour ce dossier.
    const auto files = m_folderManager->getFiles(folder.id());
    for (const auto &file : files) {
        const QString absPath = QDir::cleanPath(
            folder.localPath() + QDir::separator() + file.relativePath());
        if (QFile::exists(absPath)) {
            QFile::remove(absPath);
        }
    }

    // Supprime l'enregistrement du dossier (cascade : SharedFiles + accès).
    m_folderManager->removeFolder(folder.id());

    qDebug() << "[FolderSync] Dossier révoqué nettoyé localement :" << folder.name()
             << "(" << files.size() << "fichiers supprimés)";
}

// ---------------------------------------------------------------------------
// Envoi de messages
// ---------------------------------------------------------------------------

void FolderSyncService::broadcastMessage(const QString &json)
{
    if (m_messagingServer && m_messagingServer->isRunning()) {
        m_messagingServer->broadcastMessage(json);
    } else if (m_messagingService && m_messagingService->isConnected()) {
        m_messagingService->sendMessage(json);
    }
}

void FolderSyncService::sendMessageToServer(const QString &json)
{
    if (m_messagingService && m_messagingService->isConnected()) {
        m_messagingService->sendMessage(json);
    }
}

// ---------------------------------------------------------------------------
// Release 5/6 — Diffusion des changements locaux
// ---------------------------------------------------------------------------

QJsonObject FolderSyncService::buildFolderOpJson(const models::FileSyncOperation &op,
                                                  const models::SharedFolder &folder) const
{
    QJsonObject obj;
    obj[QStringLiteral("type")]              = QString::fromLatin1(kTypeFolderOp);
    obj[QStringLiteral("folder_uuid")]       = folder.uuid();
    obj[QStringLiteral("folder_name")]       = folder.name();
    obj[QStringLiteral("op_type")]           = models::syncChangeTypeToString(op.type());
    obj[QStringLiteral("relative_path")]     = op.relativePath();
    obj[QStringLiteral("old_relative_path")] = op.oldRelativePath();
    obj[QStringLiteral("version")]           = op.version();
    obj[QStringLiteral("machine_id")]        = op.machineId();
    obj[QStringLiteral("op_id")]             = op.id();
    // Ajouter user_uuid pour la vérification des permissions effectivePermission()
    // (machine_id est un identifiant de machine, pas de compte utilisateur)
    if (m_userManager) {
        obj[QStringLiteral("user_uuid")] = m_userManager->currentUserUuid();
    }

    const quint16 transferPort = m_transferService
        ? m_transferService->port()
        : network::TransferService::defaultPort();
    obj[QStringLiteral("transfer_port")] = static_cast<int>(transferPort);

    const auto files = m_folderManager ? m_folderManager->getFiles(folder.id())
                                       : QVector<models::SharedFile>();
    for (const auto &f : files) {
        if (f.relativePath() == op.relativePath()) {
            obj[QStringLiteral("file_hash")] = f.hash();
            obj[QStringLiteral("file_size")] = f.size();
            break;
        }
    }

    return obj;
}

void FolderSyncService::onLocalFolderReindexed(qint64 folderId, int changeCount)
{
    if (!m_folderManager || changeCount <= 0) return;

    const auto folderOpt = m_folderManager->getFolder(folderId);
    if (!folderOpt.has_value()) return;
    const models::SharedFolder &folder = *folderOpt;

    const auto ops = m_repository.getByFolderId(folderId, changeCount);
    QVector<models::FileSyncOperation> newOps;
    for (const auto &op : ops) {
        if (op.id() <= m_lastBroadcastOpId) break;
        newOps.prepend(op);
    }

    for (const auto &op : newOps) {
        if (op.id() > m_lastBroadcastOpId) m_lastBroadcastOpId = op.id();
        const QString json = QString::fromUtf8(
            QJsonDocument(buildFolderOpJson(op, folder)).toJson(QJsonDocument::Compact));
        broadcastMessage(json);
        qDebug() << "[FolderSync] Diffusé" << models::syncChangeTypeToString(op.type())
                 << op.relativePath() << "depuis" << folder.name();
    }
}

// ---------------------------------------------------------------------------
// Release 7 — Connexion au serveur : envoi du folder_hello
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Annonce d'un acces accorde (creation de dossier partage visible par
// d'autres utilisateurs -- meme poste ou autre machine du LAN)
// ---------------------------------------------------------------------------

std::optional<QJsonObject> FolderSyncService::buildAccessGrantedJson(qint64 folderId, qint64 userId,
                                                                      models::SharedFolderPermission permission) const
{
    if (!m_folderManager) return std::nullopt;

    const auto folder = m_folderManager->getFolder(folderId);
    if (!folder.has_value()) return std::nullopt;

    const auto owner = m_userRepository.findById(static_cast<int>(folder->ownerId()));
    const auto grantedUser = m_userRepository.findById(static_cast<int>(userId));
    if (!owner.has_value() || !grantedUser.has_value()) {
        return std::nullopt;
    }

    QJsonObject obj;
    obj[QStringLiteral("type")]              = QString::fromLatin1(kTypeAccessGranted);
    obj[QStringLiteral("folder_uuid")]       = folder->uuid();
    obj[QStringLiteral("folder_name")]       = folder->name();
    obj[QStringLiteral("owner_uuid")]        = owner->uuid();
    obj[QStringLiteral("user_uuid")]         = grantedUser->uuid();
    obj[QStringLiteral("permission")]        = models::sharedFolderPermissionToString(permission);
    obj[QStringLiteral("origin_machine_id")] = m_machineId;
    return obj;
}

void FolderSyncService::announceAccessGranted(qint64 folderId, qint64 userId,
                                               models::SharedFolderPermission permission)
{
    const auto obj = buildAccessGrantedJson(folderId, userId, permission);
    if (!obj.has_value()) {
        qWarning() << "[FolderSync] announceAccessGranted : proprietaire ou utilisateur introuvable, annonce annulee";
        return;
    }

    const QString json = QString::fromUtf8(QJsonDocument(*obj).toJson(QJsonDocument::Compact));
    broadcastMessage(json);
    qDebug() << "[FolderSync] Annonce d'acces diffusée : dossier" << (*obj)[QStringLiteral("folder_name")].toString()
             << "-> utilisateur uuid" << (*obj)[QStringLiteral("user_uuid")].toString();
}

void FolderSyncService::announceAccessRevoked(qint64 folderId, qint64 userId)
{
    if (!m_folderManager) return;

    // A la difference de announceAccessGranted(), la ligne SharedFolderAccess
    // a deja ete supprimee quand ce slot est appele (connecte sur
    // SharedFolderManager::accessRevoked, emis APRES le revoke() DB) : on ne
    // peut donc pas relire la permission, mais on n'en a pas besoin pour
    // notifier une revocation.
    const auto folder = m_folderManager->getFolder(folderId);
    if (!folder.has_value()) return;
    const auto revokedUser = m_userRepository.findById(static_cast<int>(userId));
    if (!revokedUser.has_value()) return;

    QJsonObject obj;
    obj[QStringLiteral("type")]              = QString::fromLatin1(kTypeAccessRevoked);
    obj[QStringLiteral("folder_uuid")]       = folder->uuid();
    obj[QStringLiteral("user_uuid")]         = revokedUser->uuid();
    obj[QStringLiteral("origin_machine_id")] = m_machineId;

    const QString json = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    broadcastMessage(json);
    qDebug() << "[FolderSync] Annonce de révocation diffusée : dossier" << folder->name()
             << "-> utilisateur" << revokedUser->name();
}

void FolderSyncService::onConnectedToServer()
{
    const qint64 lastOpId = m_repository.latestId();
    const qint64 lastAccessId = m_accessRepository.latestId();
    QJsonObject hello;
    hello[QStringLiteral("type")]          = QString::fromLatin1(kTypeFolderHello);
    hello[QStringLiteral("machine_id")]    = m_machineId;
    hello[QStringLiteral("last_op_id")]    = lastOpId;
    hello[QStringLiteral("last_access_id")] = lastAccessId;
    const QString json = QString::fromUtf8(QJsonDocument(hello).toJson(QJsonDocument::Compact));
    sendMessageToServer(json);
    qDebug() << "[FolderSync] folder_hello envoyé, last_op_id =" << lastOpId
             << "last_access_id =" << lastAccessId;
}

// ---------------------------------------------------------------------------
// Réception des messages
// ---------------------------------------------------------------------------

void FolderSyncService::onServerMessageReceived(const QString &message,
                                                 const QHostAddress &senderAddress)
{
    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8());
    if (!doc.isObject()) return;
    const QJsonObject obj = doc.object();
    const QString type = obj[QStringLiteral("type")].toString();

    if (type == QString::fromLatin1(kTypeFolderOp)) {
        handleFolderOp(obj, senderAddress);
        // Relais vers les autres clients connectes : SYMETRIQUE du correctif
        // anti-boucle deja applique a folder_access_granted/revoked/resync_request
        // ci-dessous. Sans ce relais, un CLIENT (non-SERVER) qui partage un
        // dossier voit son folder_op applique UNIQUEMENT sur le SERVER lui-meme
        // (qui le recoit via MessagingService -> sendMessage) : les AUTRES
        // clients connectes au meme hub ne recoivent jamais l'operation en
        // temps reel, et donc jamais le fichier associe (aucun folder_file_request
        // n'est jamais emis de leur cote) tant qu'un partage ulterieur ne
        // redeclenche pas un reindex complet. On ne relaie que si l'operation
        // ne vient pas de nous-memes (meme garde que pour les autres types),
        // pour eviter de renvoyer l'echo au client qui vient de l'emettre --
        // c'est sans risque : handleFolderOp() ignore deja localement toute
        // operation dont machine_id == m_machineId (ligne ci-dessus).
        const QString opMachineId = obj[QStringLiteral("machine_id")].toString();
        if (opMachineId != m_machineId
            && m_messagingServer && m_messagingServer->isRunning()) {
            m_messagingServer->broadcastMessage(message);
        }
    }
    else if (type == QString::fromLatin1(kTypeFolderHello))
        handleFolderHello(obj);
    else if (type == QString::fromLatin1(kTypeFileRequest))
        handleFolderFileRequest(obj, senderAddress);
    else if (type == QString::fromLatin1(kTypeAccessGranted)) {
        handleFolderAccessGranted(obj);
        // Relais vers les autres clients connectes : ce message peut nous
        // parvenir d'un CLIENT (via MessagingService -> serveur), qui ne
        // peut pas rejoindre directement les autres clients. Le SERVER
        // (hub, cf. doc de conception) doit donc le rediffuser.
        //
        // ATTENTION boucle : l'ancien commentaire affirmait que
        // handleFolderAccessGranted() suffisait a proteger contre les
        // boucles via son test origin_machine_id == m_machineId. C'est FAUX
        // : ce test ne protege que l'EFFET local (ne pas re-appliquer sa
        // propre annonce), pas la RE-DIFFUSION reseau ci-dessous, qui etait
        // inconditionnelle. Des que deux machines sont connectees l'une a
        // l'autre (chacune server + client de l'autre, cf. topologie
        // mesh/re-election), le message repart indefiniment dans les deux
        // sens (observe en pratique : rafale infinie de folder_access_granted
        // dans les logs, qui finit par saturer/faire planter la connexion
        // avant que les vrais folder_op/folder_file_request ne passent).
        //
        // On ne relaie donc que si l'annonce ne vient pas de nous-memes.
        const QString originMachineId = obj[QStringLiteral("origin_machine_id")].toString();
        if (originMachineId != m_machineId
            && m_messagingServer && m_messagingServer->isRunning()) {
            m_messagingServer->broadcastMessage(message);
        }
    }
    else if (type == QString::fromLatin1(kTypeAccessRevoked)) {
        handleFolderAccessRevoked(obj);
        // Meme correctif anti-boucle que pour kTypeAccessGranted ci-dessus.
        const QString originMachineId = obj[QStringLiteral("origin_machine_id")].toString();
        if (originMachineId != m_machineId
            && m_messagingServer && m_messagingServer->isRunning()) {
            m_messagingServer->broadcastMessage(message);
        }
    }
    else if (type == QString::fromLatin1(kTypeResyncRequest)) {
        handleFolderResyncRequest(obj);
        // Relais vers les autres clients (le proprietaire du dossier peut
        // etre un autre client de ce hub, pas nous) ; meme garde anti-boucle.
        const QString requesterMachineId = obj[QStringLiteral("requester_machine_id")].toString();
        if (requesterMachineId != m_machineId
            && m_messagingServer && m_messagingServer->isRunning()) {
            m_messagingServer->broadcastMessage(message);
        }
    }
    else if (type == QString::fromLatin1(kTypeCatchupBatch)) {
        // BUG CRITIQUE (relais manquant) : quand le PROPRIETAIRE d'un dossier
        // est un CLIENT (pas nous), sa reponse a un folder_resync_request
        // (construite dans handleFolderResyncRequest(), qui reutilise ce meme
        // type de message) part via broadcastMessage() -> sendMessageToServer()
        // cote CLIENT proprietaire, puisqu'il ne peut pas joindre directement
        // les autres clients. Ce cas n'etait pas gere ici du tout : le message
        // arrivait sur le SERVER et etait silencieusement ignore (aucun des
        // "else if" precedents ne correspondait), donc jamais retransmis au
        // demandeur d'origine -- les fichiers d'un dossier partage par un
        // CLIENT (par opposition au SERVER, qui diffuse directement a tous
        // les clients connectes sans passer par ce relais) n'etaient donc
        // jamais recus par les autres pairs. C'est la cause du bug "les
        // fichiers ne sont pas partages quand ce n'est pas le SERVER qui
        // fait le partage de dossier".
        //
        // On applique aussi localement (utile si CE poste est lui-meme
        // destinataire d'une partie du contenu) : handleFolderCatchupBatch()
        // et ses sous-appels sont deja idempotents (registerRemoteFolder(),
        // grantAccess(), verification de hash avant requestRemoteFile()).
        // Pas de garde anti-boucle par origin_machine_id necessaire ici : ce
        // message est une reponse ponctuelle a une demande, jamais rediffuse
        // en retour par ses destinataires (contrairement a folder_op/
        // folder_access_granted qui peuvent repartir dans l'autre sens en
        // topologie mesh).
        handleFolderCatchupBatch(obj);
        if (m_messagingServer && m_messagingServer->isRunning()) {
            m_messagingServer->broadcastMessage(message);
        }
    }
}

void FolderSyncService::onClientMessageReceived(const QString &message)
{
    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8());
    if (!doc.isObject()) return;
    const QJsonObject obj = doc.object();
    const QString type = obj[QStringLiteral("type")].toString();

    if (type == QString::fromLatin1(kTypeFolderOp))
        handleFolderOp(obj, QHostAddress());
    else if (type == QString::fromLatin1(kTypeCatchupBatch))
        handleFolderCatchupBatch(obj);
    else if (type == QString::fromLatin1(kTypeFileRequest))
        // CORRECTIF : sans ce cas, un CLIENT propriétaire d'un fichier ignorait
        // silencieusement toute demande folder_file_request provenant du SERVER
        // (ce type n'était traité que côté onServerMessageReceived). Le SERVER
        // ne recevait donc jamais les octets du fichier : le placeholder créé par
        // registerCatchupPlaceholder() (taille 0 par défaut) n'était jamais
        // complété et le fichier n'était jamais écrit sur le disque -- c'est la
        // cause du bug "fichiers reçus par le serveur toujours à 0 Ko". On passe
        // QHostAddress() (l'adresse du serveur n'est pas connue ici, contrairement
        // à handleFolderOp ci-dessus) : handleFolderFileRequest() se rabat alors
        // sur m_discoveryService pour résoudre requester_machine_id en adresse IP.
        handleFolderFileRequest(obj, QHostAddress());
    else if (type == QString::fromLatin1(kTypeAccessGranted))
        handleFolderAccessGranted(obj);
    else if (type == QString::fromLatin1(kTypeAccessRevoked))
        handleFolderAccessRevoked(obj);
    else if (type == QString::fromLatin1(kTypeResyncRequest))
        handleFolderResyncRequest(obj);
}

// ---------------------------------------------------------------------------
// Gestionnaires de messages entrants
// ---------------------------------------------------------------------------

void FolderSyncService::handleFolderOp(const QJsonObject &obj,
                                        const QHostAddress &senderAddress)
{
    const QString folderUuid   = obj[QStringLiteral("folder_uuid")].toString();
    const QString opType       = obj[QStringLiteral("op_type")].toString();
    const QString relativePath = obj[QStringLiteral("relative_path")].toString();
    const QString oldRelPath   = obj[QStringLiteral("old_relative_path")].toString();
    const QString machineId    = obj[QStringLiteral("machine_id")].toString();
    const QString userUuid     = obj[QStringLiteral("user_uuid")].toString();
    const QString fileHash     = obj[QStringLiteral("file_hash")].toString();
    const int version          = obj[QStringLiteral("version")].toInt();
    const quint16 transferPort = static_cast<quint16>(
        obj[QStringLiteral("transfer_port")].toInt(
            static_cast<int>(network::TransferService::defaultPort())));

    if (machineId == m_machineId) return;

    qDebug() << "[FolderSync] Reçu folder_op" << opType << relativePath << "de" << machineId;

    emit remoteOpReceived(folderUuid, opType, relativePath, oldRelPath,
                          machineId, senderAddress, transferPort);

    if (!m_folderManager) return;

    if (opType == QStringLiteral("Create") || opType == QStringLiteral("Update")) {
        const auto folders = m_folderManager->getFolders();
        bool folderKnownLocally = false;
        for (const auto &folder : folders) {
            if (folder.uuid() != folderUuid) continue;
            folderKnownLocally = true;
            // ── Vérification d'accès : ignorer les ops d'un pair non autorisé ──
            // Utiliser user_uuid si disponible (plus fiable que machineId pour les permissions)
            const QString peerIdentifier = userUuid.isEmpty() ? machineId : userUuid;
            if (effectivePermission(folder, peerIdentifier) == models::SharedFolderPermission::None) {
                qWarning() << "[FolderSync] folder_op ignoré : accès révoqué pour" << peerIdentifier;
                break;
            }
            bool needsUpdate = true;
            if (!fileHash.isEmpty()) {
                const auto files = m_folderManager->getFiles(folder.id());
                for (const auto &f : files) {
                    if (f.relativePath() == relativePath && f.hash() == fileHash
                        && f.version() >= version) {
                        needsUpdate = false;
                        break;
                    }
                }
            }
            if (needsUpdate) {
                requestRemoteFile(folderUuid, relativePath, machineId,
                                  folder.id(), folder.localPath(),
                                  fileHash, version);
            }
            break;
        }
        // CORRECTIF (course folder_op / folder_access_granted) : un partage
        // immediat a la creation (SharedFolderManager::createFolder() avec
        // authorizedUserIds) peut diffuser les folder_op de contenu initial
        // avant que le folder_access_granted correspondant n'ait ete traite
        // ici (registerRemoteFolder() pas encore appele) -- observe en
        // pratique dans les logs serveur (op_id de creation recus plusieurs
        // messages AVANT le folder_access_granted du meme dossier). Avant ce
        // correctif, ces operations initiales etaient silencieusement
        // perdues : la boucle ci-dessus ne trouve aucun dossier correspondant
        // et ne demande donc jamais le fichier, sans le moindre avertissement.
        // On ne peut pas les rattraper nous-memes tout de suite (le dossier
        // n'existe pas encore localement), mais on peut demander un
        // rattrapage cible : si un folder_access_granted arrive ensuite pour
        // ce dossier, handleFolderAccessGranted() enregistrera le dossier et
        // (si nous sommes le beneficiaire) redemandera deja un resync -- ce
        // qui suffit dans la plupart des cas. Ce garde-fou couvre le cas
        // residuel ou ce folder_op est le tout premier signal que nous
        // recevons pour ce dossier (p. ex. si le folder_access_granted a ete
        // perdu/retarde independamment) : on demande directement le contenu
        // au proprietaire des qu'il aura ete enregistre.
        if (!folderKnownLocally) {
            qWarning() << "[FolderSync] folder_op" << opType << relativePath
                       << "reçu pour un dossier encore inconnu localement ("
                       << folderUuid << ") -- demande de rattrapage ciblé";
            QJsonObject req;
            req[QStringLiteral("type")]                = QString::fromLatin1(kTypeResyncRequest);
            req[QStringLiteral("folder_uuid")]          = folderUuid;
            req[QStringLiteral("requester_machine_id")] = m_machineId;
            req[QStringLiteral("since_op_id")]          = 0;
            const QString json = QString::fromUtf8(QJsonDocument(req).toJson(QJsonDocument::Compact));
            broadcastMessage(json);
        }
    } else if (opType == QStringLiteral("Delete")) {
        for (const auto &folder : m_folderManager->getFolders()) {
            if (folder.uuid() != folderUuid) continue;
            const QString peerIdentifier = userUuid.isEmpty() ? machineId : userUuid;
            if (effectivePermission(folder, peerIdentifier) == models::SharedFolderPermission::None) {
                qWarning() << "[FolderSync] folder_op Delete ignoré : accès révoqué pour" << peerIdentifier;
                break;
            }
            applyRemoteDelete(folder, relativePath, machineId);
            break;
        }
    } else if (opType == QStringLiteral("Rename")) {
        for (const auto &folder : m_folderManager->getFolders()) {
            if (folder.uuid() != folderUuid) continue;
            const QString peerIdentifier = userUuid.isEmpty() ? machineId : userUuid;
            if (effectivePermission(folder, peerIdentifier) == models::SharedFolderPermission::None) {
                qWarning() << "[FolderSync] folder_op Rename ignoré : accès révoqué pour" << peerIdentifier;
                break;
            }
            applyRemoteRename(folder, oldRelPath, relativePath, machineId);
            break;
        }
    }
}

void FolderSyncService::handleFolderHello(const QJsonObject &obj)
{
    if (!m_folderManager) return;
    const qint64 lastOpId = static_cast<qint64>(obj[QStringLiteral("last_op_id")].toDouble());
    const qint64 lastAccessId = static_cast<qint64>(obj[QStringLiteral("last_access_id")].toDouble());
    const QString requesterMachineId = obj[QStringLiteral("machine_id")].toString();
    const quint16 selfPort = m_transferService ? m_transferService->port()
                                               : network::TransferService::defaultPort();

    QJsonArray opsArray;
    const auto folders = m_folderManager->getFolders();
    for (const auto &folder : folders) {
        // PAS de filtre isLocalOrigin() ici (correctif) : ce SERVER a pu
        // accumuler de l'historique (SyncOperations) pour un dossier dont
        // l'origine est un AUTRE poste -- des qu'il a lui-meme telecharge/
        // applique au moins une operation distante sur ce dossier (cf.
        // integrateReceivedFile(), applyRemoteDelete(), applyRemoteRename(),
        // registerCatchupPlaceholder(), qui inserent toutes dans m_repository
        // quel que soit folder.originMachineId()). Filtrer sur isLocalOrigin()
        // faisait que le SERVER ne rattrapait QUE les dossiers qu'il avait
        // lui-meme crees : un client qui se (re)connecte ne recevait alors
        // aucun historique pour les dossiers partages par un AUTRE client,
        // meme si le SERVER avait deja recu/relaye ces operations pendant que
        // ce client etait hors-ligne. La verification d'acces ci-dessous reste
        // la seule garde necessaire (elle s'applique deja independamment de
        // l'origine du dossier).

        // ── Vérification d'accès : n'envoyer le rattrapage que si le pair
        //    qui se connecte a (encore) accès à ce dossier.
        if (!requesterMachineId.isEmpty()
            && effectivePermission(folder, requesterMachineId) == models::SharedFolderPermission::None) {
            qDebug() << "[FolderSync] folder_hello : rattrapage refusé pour"
                     << requesterMachineId << "sur le dossier" << folder.name();
            continue;
        }

        const auto ops = m_repository.getByFolderId(folder.id(), 500);
        for (const auto &op : ops) {
            if (op.id() <= lastOpId) break;
            QJsonObject opObj = buildFolderOpJson(op, folder);
            opObj.remove(QStringLiteral("type"));
            opObj[QStringLiteral("transfer_port")] = static_cast<int>(selfPort);
            opsArray.append(opObj);
        }
    }

    // Rattrapage hors-ligne des annonces de partage (issue "share pas reçu
    // si le SERVER etait hors-ligne au moment du grantAccess") : le SERVER
    // rejoue tous les acces qu'IL connait localement (accordes par lui-meme
    // OU deja reçus/appliques via handleFolderAccessGranted pendant qu'il
    // etait en ligne) et qui sont plus recents que le curseur du CLIENT qui
    // se connecte. Cela couvre le cas ou le CLIENT (ou le SERVER) etait
    // hors-ligne au moment de l'annonce initiale -- des qu'il se reconnecte,
    // il rattrape les acces manques sans qu'une nouvelle action de partage
    // soit necessaire.
    QJsonArray accessArray;
    for (const auto &access : m_accessRepository.getSinceId(lastAccessId, 500)) {
        const auto accessJson = buildAccessGrantedJson(access.folderId(), access.userId(), access.permission());
        if (accessJson.has_value()) {
            QJsonObject entry = *accessJson;
            entry.remove(QStringLiteral("type"));
            accessArray.append(entry);
        }
    }

    QJsonObject batch;
    batch[QStringLiteral("type")]         = QString::fromLatin1(kTypeCatchupBatch);
    batch[QStringLiteral("operations")]   = opsArray;
    batch[QStringLiteral("access_grants")] = accessArray;
    const QString json = QString::fromUtf8(
        QJsonDocument(batch).toJson(QJsonDocument::Compact));
    broadcastMessage(json);
    qDebug() << "[FolderSync] folder_catchup_batch envoyé :" << opsArray.size() << "ops,"
             << accessArray.size() << "access_grants";
}

void FolderSyncService::handleFolderCatchupBatch(const QJsonObject &obj)
{
    const QJsonArray opsArray = obj[QStringLiteral("operations")].toArray();

    // Rattrapage des annonces de partage manquees (cf. handleFolderHello()) :
    // chaque entree est traitee exactement comme une annonce temps reel
    // (handleFolderAccessGranted() est idempotent -- registerRemoteFolder()
    // et grantAccess() le sont deja).
    //
    // IMPORTANT : ce traitement doit avoir lieu AVANT la boucle sur
    // `operations` ci-dessous. Sur une machine qui decouvre ce dossier
    // partage pour la premiere fois, le dossier n'existe pas encore
    // localement tant que registerRemoteFolder() (declenche ici) n'a pas
    // ete appele -- si on traite les operations en premier, la recherche
    // "folder.uuid() != folderUuid" ne trouve jamais de correspondance et
    // chaque Create/Update/Delete/Rename est silencieusement ignore, sans
    // le moindre avertissement (aucun fichier n'est alors jamais demande).
    const QJsonArray accessArray = obj[QStringLiteral("access_grants")].toArray();
    for (const auto &value : accessArray) {
        if (!value.isObject()) continue;
        handleFolderAccessGranted(value.toObject());
    }
    if (!accessArray.isEmpty()) {
        qDebug() << "[FolderSync] folder_catchup_batch : " << accessArray.size() << "access_grants rattrapés";
    }

    if (opsArray.isEmpty()) return;

    QVector<models::FileSyncOperation> ops;
    ops.reserve(opsArray.size());
    for (const auto &value : opsArray) {
        if (!value.isObject()) continue;
        const QJsonObject opObj = value.toObject();

        models::FileSyncOperation op;
        op.setId(static_cast<qint64>(opObj[QStringLiteral("op_id")].toDouble()));
        op.setType(models::syncChangeTypeFromString(opObj[QStringLiteral("op_type")].toString()));
        op.setRelativePath(opObj[QStringLiteral("relative_path")].toString());
        op.setOldRelativePath(opObj[QStringLiteral("old_relative_path")].toString());
        op.setVersion(opObj[QStringLiteral("version")].toInt());
        op.setMachineId(opObj[QStringLiteral("machine_id")].toString());
        ops.append(op);

        const QString folderUuid   = opObj[QStringLiteral("folder_uuid")].toString();
        const QString opType       = opObj[QStringLiteral("op_type")].toString();
        const QString relativePath = opObj[QStringLiteral("relative_path")].toString();
        const QString oldRelPath   = opObj[QStringLiteral("old_relative_path")].toString();
        const QString machineId    = opObj[QStringLiteral("machine_id")].toString();
        const QString userUuid     = opObj[QStringLiteral("user_uuid")].toString();
        const QString fileHash     = opObj[QStringLiteral("file_hash")].toString();
        const int version          = opObj[QStringLiteral("version")].toInt();

        if (machineId == m_machineId || !m_folderManager) continue;

        if (opType == QStringLiteral("Create") || opType == QStringLiteral("Update")) {
            const auto folders = m_folderManager->getFolders();
            for (const auto &folder : folders) {
                if (folder.uuid() != folderUuid) continue;
                const QString peerIdentifier = userUuid.isEmpty() ? machineId : userUuid;
                if (effectivePermission(folder, peerIdentifier) == models::SharedFolderPermission::None) {
                    qWarning() << "[FolderSync] catchup op ignoré : accès révoqué pour" << peerIdentifier;
                    break;
                }
                // CORRECTIF (historique dupliqué/faux côté destinataire) :
                // contrairement à handleFolderOp() (traitement temps réel),
                // cette branche ne vérifiait jamais si le fichier annoncé
                // était déjà présent localement avec le même hash/version
                // avant de (re)télécharger ou de (re)créer un placeholder.
                // Un folder_catchup_batch est renvoyé à CHAQUE folder_hello
                // (reconnexion d'un pair quelconque) et contient TOUTES les
                // opérations depuis le curseur connu -- sans ce garde-fou,
                // un fichier déjà reçu et inchangé était re-demandé/re-placé
                // à chaque reconnexion, ajoutant une nouvelle ligne
                // SyncOperations (registerCatchupPlaceholder()/
                // integrateReceivedFile() insèrent toujours une nouvelle
                // ligne, jamais une mise à jour) : l'historique grossissait
                // indéfiniment avec des entrées redondantes, horodatées au
                // moment du traitement local (donc sans rapport avec la date
                // réelle de l'événement côté expéditeur).
                //
                // CORRECTIF 2 (régression "fichiers toujours à 0 Ko") : une
                // comparaison hash/version identique à celle de handleFolderOp()
                // ne suffit PAS ici, car registerCatchupPlaceholder() enregistre
                // volontairement le hash ANNONCÉ (fileHash) sur une ligne
                // SharedFiles dont le contenu réel est absent (0 octet, cf. son
                // commentaire "size reste a 0"). Résultat : dès qu'un placeholder
                // existait déjà (dossier distant sans localPath), la comparaison
                // hash/version le trouvait "déjà à jour" et needsUpdate passait à
                // false -- y compris APRÈS que l'utilisateur ait choisi un
                // localPath (setFolderLocalPath() -> requestFolderResync()), ce
                // qui empêchait alors définitivement le vrai contenu d'être
                // téléchargé (requestRemoteFile() jamais appelé). Le hash/version
                // en base ne peut donc être considéré comme "à jour" que si le
                // fichier existe RÉELLEMENT sur disque à l'emplacement attendu ;
                // sans localPath, aucun contenu réel n'est de toute façon possible
                // (le hash connu ne peut provenir que d'un placeholder).
                bool needsUpdate = true;
                if (!fileHash.isEmpty()) {
                    const auto files = m_folderManager->getFiles(folder.id());
                    for (const auto &f : files) {
                        if (f.relativePath() == relativePath && f.hash() == fileHash
                            && f.version() >= version) {
                            if (folder.localPath().isEmpty()) {
                                needsUpdate = false;
                            } else {
                                const QString expectedAbsPath = QDir::cleanPath(
                                    folder.localPath() + QDir::separator() + relativePath);
                                needsUpdate = !QFile::exists(expectedAbsPath);
                            }
                            break;
                        }
                    }
                }
                if (!needsUpdate) {
                    break;
                }
                // Pour les dossiers distants (localPath vide), on ne peut pas
                // télécharger les fichiers tant qu'un chemin local n'est pas défini.
                // On crée juste la métadonnée dans SharedFiles (+ l'entrée
                // d'historique correspondante) pour que le dossier ne
                // paraisse pas vide dans l'UI ; le contenu réel et le hash
                // définitif seront complétés par le resync déclenché dès que
                // setFolderLocalPath() sera appelé (cf. requestFolderResync()).
                if (folder.localPath().isEmpty()) {
                    qWarning() << "[FolderSync] catchup op : dossier distant sans localPath, métadonnée seule pour" << relativePath;
                    registerCatchupPlaceholder(folder, relativePath, fileHash, version, machineId);
                    break;
                }
                requestRemoteFile(folderUuid, relativePath, machineId,
                                  folder.id(), folder.localPath(),
                                  fileHash, version);
                break;
            }
        } else if (opType == QStringLiteral("Delete")) {
            for (const auto &folder : m_folderManager->getFolders()) {
                if (folder.uuid() != folderUuid) continue;
                const QString peerIdentifier = userUuid.isEmpty() ? machineId : userUuid;
                if (effectivePermission(folder, peerIdentifier) == models::SharedFolderPermission::None) {
                    qWarning() << "[FolderSync] catchup Delete ignoré : accès révoqué pour" << peerIdentifier;
                    break;
                }
                applyRemoteDelete(folder, relativePath, machineId);
                break;
            }
        } else if (opType == QStringLiteral("Rename")) {
            for (const auto &folder : m_folderManager->getFolders()) {
                if (folder.uuid() != folderUuid) continue;
                const QString peerIdentifier = userUuid.isEmpty() ? machineId : userUuid;
                if (effectivePermission(folder, peerIdentifier) == models::SharedFolderPermission::None) {
                    qWarning() << "[FolderSync] catchup Rename ignoré : accès révoqué pour" << peerIdentifier;
                    break;
                }
                applyRemoteRename(folder, oldRelPath, relativePath, machineId);
                break;
            }
        }
    }

    qDebug() << "[FolderSync] folder_catchup_batch reçu :" << ops.size() << "ops";
    emit catchupBatchReceived(ops);
}

void FolderSyncService::handleFolderFileRequest(const QJsonObject &obj,
                                                 const QHostAddress &senderAddress)
{
    if (!m_transferService || !m_folderManager) return;

    const QString folderUuid         = obj[QStringLiteral("folder_uuid")].toString();
    const QString relativePath       = obj[QStringLiteral("relative_path")].toString();
    const QString requesterMachineId = obj[QStringLiteral("requester_machine_id")].toString();
    const quint16 requesterPort      = static_cast<quint16>(
        obj[QStringLiteral("requester_transfer_port")].toInt(
            static_cast<int>(network::TransferService::defaultPort())));

    QHostAddress targetAddress = senderAddress;
    if ((targetAddress.isNull() || targetAddress == QHostAddress::Any) && m_discoveryService) {
        const auto peers = m_discoveryService->peers();
        for (const auto &peer : peers) {
            if (peer.id == requesterMachineId) { targetAddress = peer.address; break; }
        }
    }
    if (targetAddress.isNull()) {
        qWarning() << "[FolderSync] folder_file_request : adresse introuvable pour" << requesterMachineId;
        return;
    }

    const auto folders = m_folderManager->getFolders();
    for (const auto &folder : folders) {
        if (folder.uuid() != folderUuid || !folder.isLocalOrigin()) continue;

        // ── Vérification d'accès (Release 9 — dossiers en lecture seule) ───
        // Le contenu réel des fichiers n'est transféré qu'aux pairs ayant un
        // accès Write : Read ne permet que de voir les métadonnées/la liste
        // des fichiers (cf. SharedFolderManager, doc de conception), pas de
        // récupérer les octets. None (révoqué ou jamais accordé) est refusé
        // pour la même raison -- canWrite() couvre les deux cas en un seul
        // test (None et Read renvoient tous deux false).
        const auto perm = effectivePermission(folder, requesterMachineId);
        if (!models::canWrite(perm)) {
            qWarning() << "[FolderSync] folder_file_request : accès refusé (lecture seule ou révoqué) pour"
                       << requesterMachineId << "sur le dossier" << folder.name();
            return;
        }
        // ──────────────────────────────────────────────────────────────────

        const QString absPath = QDir::cleanPath(
            folder.localPath() + QDir::separator() + relativePath);
        if (!QFile::exists(absPath)) {
            qWarning() << "[FolderSync] folder_file_request : fichier introuvable :" << absPath;
            return;
        }
        const bool ok = m_transferService->sendFile(
            targetAddress, requesterPort, absPath, m_machineId, requesterMachineId);
        if (!ok) {
            qWarning() << "[FolderSync] sendFile échoué pour" << absPath;
        } else {
            qDebug() << "[FolderSync] Envoi de" << relativePath << "vers" << targetAddress;

            // Enregistre cette réponse à un folder_file_request pour que
            // onTransferStarted() puisse corréler le transfert SORTANT
            // correspondant : cela permet à isFolderTransfer() de le
            // reconnaître et de le regrouper dans une seule notification
            // "N fichiers envoyés" (scheduleFolderSentNotification) au lieu
            // d'une notification par fichier (cf. NotificationManager::
            // onTransferCompleted, appelé sinon pour chaque fichier envoyé).
            const QString fileName = QFileInfo(absPath).fileName();
            const QString pendingKey = requesterMachineId + QStringLiteral("::") + fileName;
            m_pendingOutgoingByKey.insert(pendingKey, folderUuid);
        }
        return;
    }
    qWarning() << "[FolderSync] folder_file_request : dossier" << folderUuid << "introuvable";
}

void FolderSyncService::handleFolderAccessGranted(const QJsonObject &obj)
{
    if (!m_folderManager) return;

    const QString originMachineId = obj[QStringLiteral("origin_machine_id")].toString();
    if (originMachineId == m_machineId) return; // notre propre annonce (deja appliquee localement)

    const QString userUuid = obj[QStringLiteral("user_uuid")].toString();
    const auto grantedUser = m_userRepository.findByUuid(userUuid);
    if (!grantedUser.has_value()) {
        // Utilisateur inconnu sur ce poste (cas normal : la plupart des
        // machines du LAN n'hebergent pas tous les comptes) -- rien a
        // faire ici, ce poste n'est simplement pas destinataire.
        return;
    }

    const QString ownerUuid = obj[QStringLiteral("owner_uuid")].toString();
    const auto owner = m_userRepository.findByUuid(ownerUuid);
    if (!owner.has_value()) {
        qWarning() << "[FolderSync] folder_access_granted : proprietaire" << ownerUuid << "inconnu localement, annonce ignoree";
        return;
    }

    const QString folderUuid = obj[QStringLiteral("folder_uuid")].toString();
    auto folder = m_folderManager->getFolderByUuid(folderUuid);
    if (!folder.has_value()) {
        folder = m_folderManager->registerRemoteFolder(
            folderUuid, obj[QStringLiteral("folder_name")].toString(), owner->id(), originMachineId);
        if (!folder.has_value()) {
            qWarning() << "[FolderSync] folder_access_granted : echec de l'enregistrement du dossier" << folderUuid;
            return;
        }
    }

    const auto permission = models::stringToSharedFolderPermission(obj[QStringLiteral("permission")].toString())
        .value_or(models::SharedFolderPermission::Read);
    // Ne pas diffuser sur le réseau (broadcastNetwork = false) pour éviter la boucle
    // (le message a déjà été reçu et traité via le réseau)
    m_folderManager->grantAccess(folder->id(), grantedUser->id(), owner->id(), permission, false);

    qDebug() << "[FolderSync] Dossier partagé reçu :" << folder->name()
             << "-> accès accordé à" << grantedUser->name();

    // announceAccessGranted() ne diffuse que les METADONNEES du dossier
    // (uuid/nom/permission) : aucun contenu n'est pousse a ce stade. Le seul
    // mecanisme qui envoie le contenu existant est le folder_catchup_batch
    // construit par handleFolderHello(), qui ne se declenche qu'a la
    // (re)connexion (onConnectedToServer()). Resultat observe : si l'acces
    // est accorde alors que le beneficiaire est deja connecte (cas normal
    // d'un partage "live"), le dossier apparait cote destinataire mais reste
    // vide indefiniment, tant qu'aucune reconnexion ne survient.
    //
    // Si c'est NOUS (l'utilisateur local de cette machine) qui venons de
    // recevoir l'acces a ce dossier distant, on ne peut pas attendre une
    // hypothetique reconnexion : on demande immediatement au proprietaire un
    // rattrapage cible pour CE dossier, sans attendre folder_hello.
    qDebug() << "[FolderSync] Vérification resync request: m_localUserId=" << m_localUserId
             << "grantedUser->id()=" << grantedUser->id()
             << "folder->isLocalOrigin()=" << folder->isLocalOrigin();
    if (m_localUserId > 0
        && static_cast<qint64>(grantedUser->id()) == m_localUserId
        && !folder->isLocalOrigin()) {
        QJsonObject req;
        req[QStringLiteral("type")]                = QString::fromLatin1(kTypeResyncRequest);
        req[QStringLiteral("folder_uuid")]          = folder->uuid();
        req[QStringLiteral("requester_machine_id")] = m_machineId;
        req[QStringLiteral("since_op_id")]          = 0;
        const QString json = QString::fromUtf8(QJsonDocument(req).toJson(QJsonDocument::Compact));
        broadcastMessage(json);
        qDebug() << "[FolderSync] folder_resync_request envoyé pour récupérer le contenu de"
                 << folder->name();
    } else {
        qDebug() << "[FolderSync] folder_resync_request NON envoyé (conditions non remplies)";
    }
}

void FolderSyncService::requestFolderResync(const QString &folderUuid)
{
    if (!m_folderManager) {
        qWarning() << "[FolderSync] requestFolderResync: FolderManager non disponible";
        return;
    }

    const auto folder = m_folderManager->getFolderByUuid(folderUuid);
    if (!folder.has_value()) {
        qWarning() << "[FolderSync] requestFolderResync: dossier introuvable" << folderUuid;
        return;
    }

    if (folder->isLocalOrigin()) {
        qWarning() << "[FolderSync] requestFolderResync: dossier local, pas besoin de resync" << folder->name();
        return;
    }

    if (folder->localPath().isEmpty()) {
        qWarning() << "[FolderSync] requestFolderResync: dossier distant sans localPath" << folder->name();
        return;
    }

    // Envoyer un resync request au propriétaire du dossier
    QJsonObject req;
    req[QStringLiteral("type")]                = QString::fromLatin1(kTypeResyncRequest);
    req[QStringLiteral("folder_uuid")]          = folder->uuid();
    req[QStringLiteral("requester_machine_id")] = m_machineId;
    req[QStringLiteral("since_op_id")]          = 0;
    const QString json = QString::fromUtf8(QJsonDocument(req).toJson(QJsonDocument::Compact));
    broadcastMessage(json);
    qDebug() << "[FolderSync] folder_resync_request envoyé pour récupérer le contenu de" << folder->name();
}

void FolderSyncService::handleFolderResyncRequest(const QJsonObject &obj)
{
    qDebug() << "[FolderSync] handleFolderResyncRequest appelé";
    if (!m_folderManager) return;

    const QString folderUuid         = obj[QStringLiteral("folder_uuid")].toString();
    const QString requesterMachineId = obj[QStringLiteral("requester_machine_id")].toString();
    const qint64 sinceOpId = static_cast<qint64>(obj[QStringLiteral("since_op_id")].toDouble());

    qDebug() << "[FolderSync] folder_resync_request: folderUuid=" << folderUuid
             << "requesterMachineId=" << requesterMachineId
             << "sinceOpId=" << sinceOpId;

    if (folderUuid.isEmpty() || requesterMachineId.isEmpty() || requesterMachineId == m_machineId)
        return;

    const auto folder = m_folderManager->getFolderByUuid(folderUuid);
    // Seul le propriétaire (origine locale du dossier) peut répondre : c'est
    // la seule machine à détenir le contenu réel sur disque.
    if (!folder.has_value()) {
        qDebug() << "[FolderSync] folder_resync_request: dossier introuvable";
        return;
    }
    if (!folder->isLocalOrigin()) {
        qDebug() << "[FolderSync] folder_resync_request: dossier non local (nous ne sommes pas le propriétaire)";
        return;
    }

    if (effectivePermission(*folder, requesterMachineId) == models::SharedFolderPermission::None) {
        qDebug() << "[FolderSync] folder_resync_request refusé (accès révoqué) pour" << requesterMachineId
                 << "sur le dossier" << folder->name();
        return;
    }

    const quint16 selfPort = m_transferService ? m_transferService->port()
                                               : network::TransferService::defaultPort();

    QJsonArray opsArray;
    const auto ops = m_repository.getByFolderId(folder->id(), 500);
    for (const auto &op : ops) {
        if (op.id() <= sinceOpId) break;
        QJsonObject opObj = buildFolderOpJson(op, *folder);
        opObj.remove(QStringLiteral("type"));
        opObj[QStringLiteral("transfer_port")] = static_cast<int>(selfPort);
        opsArray.append(opObj);
    }

    // Si aucune opération n'existe encore (dossier fraîchement créé),
    // on génère les opérations Create pour les fichiers existants
    if (opsArray.isEmpty()) {
        qDebug() << "[FolderSync] folder_resync_request : aucune opération trouvée, génération depuis les fichiers existants";
        const auto files = m_folderManager->getFiles(folder->id());
        for (const auto &file : files) {
            QJsonObject opObj;
            opObj[QStringLiteral("folder_uuid")] = folder->uuid();
            opObj[QStringLiteral("folder_name")] = folder->name();
            opObj[QStringLiteral("op_type")] = QStringLiteral("Create");
            opObj[QStringLiteral("relative_path")] = file.relativePath();
            opObj[QStringLiteral("old_relative_path")] = QString();
            opObj[QStringLiteral("file_hash")] = file.hash();
            opObj[QStringLiteral("file_size")] = static_cast<qint64>(file.size());
            opObj[QStringLiteral("version")] = file.version();
            opObj[QStringLiteral("machine_id")] = m_machineId;
            opObj[QStringLiteral("transfer_port")] = static_cast<int>(selfPort);
            // user_uuid sera ajouté par buildFolderOpJson si nécessaire
            opsArray.append(opObj);
        }
    }

    if (opsArray.isEmpty()) return; // dossier vraiment vide, rien à rattraper

    // Réutilise le format folder_catchup_batch existant : le destinataire
    // (handleFolderCatchupBatch) sait déjà demander chaque fichier manquant
    // via requestRemoteFile() pour chaque opération Create/Update reçue.
    QJsonObject batch;
    batch[QStringLiteral("type")]          = QString::fromLatin1(kTypeCatchupBatch);
    batch[QStringLiteral("operations")]    = opsArray;
    batch[QStringLiteral("access_grants")] = QJsonArray(); // déjà géré par folder_access_granted
    const QString json = QString::fromUtf8(QJsonDocument(batch).toJson(QJsonDocument::Compact));
    broadcastMessage(json);
    qDebug() << "[FolderSync] folder_resync_request : rattrapage ciblé envoyé pour" << folder->name()
             << "(" << opsArray.size() << "opération(s)) vers" << requesterMachineId;
}

void FolderSyncService::handleFolderAccessRevoked(const QJsonObject &obj)
{
    if (!m_folderManager) return;

    const QString originMachineId = obj[QStringLiteral("origin_machine_id")].toString();
    if (originMachineId == m_machineId) return; // notre propre annonce (deja appliquee localement)

    const QString userUuid = obj[QStringLiteral("user_uuid")].toString();
    const auto revokedUser = m_userRepository.findByUuid(userUuid);
    if (!revokedUser.has_value()) return; // utilisateur inconnu sur ce poste

    const QString folderUuid = obj[QStringLiteral("folder_uuid")].toString();
    const auto folder = m_folderManager->getFolderByUuid(folderUuid);
    if (!folder.has_value()) return; // dossier inconnu sur ce poste

    const bool weAreRevoked = (m_localUserId > 0
                                && static_cast<qint64>(revokedUser->id()) == m_localUserId);

    if (weAreRevoked) {
        // Cette machine est révoquée : supprimer les fichiers locaux du dossier
        // et retirer son enregistrement. Les données appartiennent au propriétaire
        // du dossier ; nous n'avons plus le droit de les conserver.
        qDebug() << "[FolderSync] Notre accès au dossier" << folder->name()
                 << "a été révoqué — nettoyage local en cours";
        cleanupRevokedFolder(*folder); // supprime aussi l'accès via removeFolder
    } else {
        // Un autre utilisateur a été révoqué ; on met simplement à jour la DB
        // locale, SANS rediffuser (broadcastNetwork=false) : cet évènement
        // provient déjà du réseau, le rediffuser créerait une boucle infinie
        // entre pairs (cf. commentaire dans SharedFolderManager::revokeAccess()).
        m_folderManager->revokeAccess(folder->id(), revokedUser->id(), false);
        qDebug() << "[FolderSync] Révocation reçue : dossier" << folder->name()
                 << "-> utilisateur" << revokedUser->name();
    }
}

// ---------------------------------------------------------------------------
// API publique : demande de fichier distant (surcharge publique simple)
// ---------------------------------------------------------------------------

void FolderSyncService::requestRemoteFile(const QString &folderUuid,
                                           const QString &relativePath,
                                           const QString &ownerMachineId)
{
    // Version sans métadonnées : la PendingFileTransfer ne contiendra pas folderId
    // ni localFolderPath → integrateReceivedFile ne sera pas appelé.
    requestRemoteFile(folderUuid, relativePath, ownerMachineId,
                      0, QString(), QString(), 0);
}

// ---------------------------------------------------------------------------
// Release 8 — Suivi des demandes + intégration des fichiers reçus
// ---------------------------------------------------------------------------

void FolderSyncService::requestRemoteFile(const QString &folderUuid,
                                           const QString &relativePath,
                                           const QString &ownerMachineId,
                                           qint64 folderId,
                                           const QString &localFolderPath,
                                           const QString &incomingHash,
                                           int incomingVersion)
{
    const quint16 myPort = m_transferService ? m_transferService->port()
                                             : network::TransferService::defaultPort();

    QJsonObject req;
    req[QStringLiteral("type")]                    = QString::fromLatin1(kTypeFileRequest);
    req[QStringLiteral("folder_uuid")]             = folderUuid;
    req[QStringLiteral("relative_path")]           = relativePath;
    req[QStringLiteral("requester_machine_id")]    = m_machineId;
    req[QStringLiteral("requester_transfer_port")] = static_cast<int>(myPort);
    req[QStringLiteral("owner_machine_id")]        = ownerMachineId;

    const QString json = QString::fromUtf8(QJsonDocument(req).toJson(QJsonDocument::Compact));
    broadcastMessage(json);

    // Enregistre la demande en attente pour corréler avec TransferService.
    if (folderId > 0 && !localFolderPath.isEmpty()) {
        const QString fileName = QFileInfo(relativePath).fileName();
        const QString pendingKey = ownerMachineId + QStringLiteral("::") + fileName;

        PendingFileTransfer pending;
        pending.folderUuid       = folderUuid;
        pending.relativePath     = relativePath;
        pending.folderId         = folderId;
        pending.localFolderPath  = localFolderPath;
        pending.ownerMachineId   = ownerMachineId;
        pending.incomingHash     = incomingHash;
        pending.incomingVersion  = incomingVersion;
        m_pendingByKey.insert(pendingKey, pending);
    }

    qDebug() << "[FolderSync] Demande de fichier :" << relativePath << "de" << ownerMachineId;
}

void FolderSyncService::onTransferStarted(const QString &transferKey,
                                           const QString &fileName,
                                           qint64 /*fileSize*/,
                                           bool incoming,
                                           qint64 /*resumeOffset*/,
                                           const QString &/*senderUuid*/,
                                           const QString &recipientUuid,
                                           const QHostAddress &/*peerAddress*/,
                                           const QString &peerMachineId)
{
    if (!incoming) {
        // Sens ENVOI : cherche une réponse à folder_file_request en attente
        // dont le destinataire (recipientUuid porte ici le machineId du
        // demandeur, cf. handleFolderFileRequest()) et le nom de fichier
        // correspondent à ce transfert sortant.
        const QString pendingKey = recipientUuid + QStringLiteral("::") + fileName;
        const auto it = m_pendingOutgoingByKey.find(pendingKey);
        if (it == m_pendingOutgoingByKey.end()) return;

        m_activeOutgoingByTransferKey.insert(transferKey, it.value());
        m_pendingOutgoingByKey.erase(it);

        qDebug() << "[FolderSync] Transfert sortant" << transferKey << "corrélé à" << fileName;
        return;
    }

    // Cherche une demande en attente dont l'expéditeur et le nom de fichier
    // correspondent à ce transfert entrant.
    const QString pendingKey = peerMachineId + QStringLiteral("::") + fileName;
    const auto it = m_pendingByKey.find(pendingKey);
    if (it == m_pendingByKey.end()) return;

    // Corrèle : associe le transferKey à la PendingFileTransfer.
    m_activeByTransferKey.insert(transferKey, it.value());
    m_pendingByKey.erase(it);

    qDebug() << "[FolderSync] Transfert" << transferKey << "corrélé à" << fileName;
}

void FolderSyncService::onTransferCompleted(const QString &transferKey,
                                             const QString &filePath)
{
    // Sens ENVOI : réponse à un folder_file_request qui vient de se terminer
    // -- regroupe en une seule notification "N fichiers envoyés" plutôt que
    // d'intégrer quoi que ce soit (rien à intégrer, ce fichier existait déjà
    // localement puisque c'est nous qui l'avons envoyé).
    const auto oit = m_activeOutgoingByTransferKey.find(transferKey);
    if (oit != m_activeOutgoingByTransferKey.end()) {
        const QString folderUuid = oit.value();
        m_activeOutgoingByTransferKey.erase(oit);
        scheduleFolderSentNotification(folderUuid);
        return;
    }

    const auto it = m_activeByTransferKey.find(transferKey);
    if (it == m_activeByTransferKey.end()) return; // Pas un transfert folder-sync.

    const PendingFileTransfer pending = it.value();
    m_activeByTransferKey.erase(it);

    integrateReceivedFile(pending, filePath);
}

bool FolderSyncService::isFolderTransfer(const QString &transferKey) const
{
    return m_activeByTransferKey.contains(transferKey)
        || m_activeOutgoingByTransferKey.contains(transferKey);
}

void FolderSyncService::scheduleFolderNotification(const QString &folderUuid)
{
    m_pendingNotifyCounts[folderUuid] = m_pendingNotifyCounts.value(folderUuid, 0) + 1;

    QTimer *timer = m_notifyTimers.value(folderUuid, nullptr);
    if (!timer) {
        timer = new QTimer(this);
        timer->setSingleShot(true);
        connect(timer, &QTimer::timeout, this, [this, folderUuid]() {
            const int count = m_pendingNotifyCounts.take(folderUuid);
            if (count <= 0) return;

            QString folderName = folderUuid;
            if (m_folderManager) {
                if (const auto folder = m_folderManager->getFolderByUuid(folderUuid); folder.has_value()) {
                    folderName = folder->name();
                }
            }
            emit folderFilesReceived(folderUuid, folderName, count);
        });
        m_notifyTimers.insert(folderUuid, timer);
    }
    // Redémarre le minuteur à chaque fichier reçu : la notification ne part
    // qu'une fois la rafale terminée (~800ms de silence), plutôt qu'une par
    // fichier (cf. NotificationManager::onTransferCompleted).
    timer->start(800);
}

void FolderSyncService::scheduleFolderSentNotification(const QString &folderUuid)
{
    m_pendingSentCounts[folderUuid] = m_pendingSentCounts.value(folderUuid, 0) + 1;

    QTimer *timer = m_sentNotifyTimers.value(folderUuid, nullptr);
    if (!timer) {
        timer = new QTimer(this);
        timer->setSingleShot(true);
        connect(timer, &QTimer::timeout, this, [this, folderUuid]() {
            const int count = m_pendingSentCounts.take(folderUuid);
            if (count <= 0) return;

            QString folderName = folderUuid;
            if (m_folderManager) {
                if (const auto folder = m_folderManager->getFolderByUuid(folderUuid); folder.has_value()) {
                    folderName = folder->name();
                }
            }
            emit folderFilesSent(folderUuid, folderName, count);
        });
        m_sentNotifyTimers.insert(folderUuid, timer);
    }
    // Même logique anti-rebond que scheduleFolderNotification() : redémarre
    // le minuteur à chaque fichier envoyé, la notification ne part qu'une
    // fois la rafale terminée (~800ms de silence), plutôt qu'une par fichier.
    timer->start(800);
}

// ---------------------------------------------------------------------------
// Application des Delete / Rename distants (complète le Release 6 : jusqu'ici
// seuls Create/Update étaient appliqués côté récepteur).
// ---------------------------------------------------------------------------

void FolderSyncService::applyRemoteDelete(const models::SharedFolder &folder,
                                           const QString &relativePath,
                                           const QString &machineId)
{
    const QString absPath = QDir::cleanPath(
        folder.localPath() + QDir::separator() + relativePath);
    if (QFile::exists(absPath) && !QFile::remove(absPath)) {
        qWarning() << "[FolderSync] Suppression distante : échec de la suppression sur disque :" << absPath;
    }

    if (!m_fileRepository.markDeleted(folder.id(), relativePath)) {
        qWarning() << "[FolderSync] Suppression distante : markDeleted échoué pour" << relativePath;
    }

    const auto existing = m_fileRepository.findByRelativePath(folder.id(), relativePath);

    // CORRECTIF (diagnostic) : file_id est NOT NULL + FK vers SharedFiles(id)
    // dans le schema (migration 018/021) -- sans ligne SharedFiles connue,
    // toute tentative d'insert() echoue silencieusement (le code precedent
    // n'en verifiait jamais le resultat), laissant SyncOperations vide sans
    // le moindre indice dans les logs. On journalise desormais explicitement
    // ce cas plutot que de tenter un insert voue a l'echec.
    if (existing.has_value()) {
        models::FileSyncOperation op;
        op.setType(models::SyncChangeType::Delete);
        op.setFileId(existing->id());
        op.setRelativePath(relativePath);
        op.setMachineId(machineId);
        if (!m_repository.insert(op).has_value()) {
            qWarning() << "[FolderSync] SyncOperations insert (Delete) échoué pour" << relativePath
                       << "-- erreur SQL:" << m_repository.lastError();
        }
    } else {
        qWarning() << "[FolderSync] Suppression distante : aucune ligne SharedFiles connue pour"
                   << relativePath << "-- opération non journalisée (file_id requis)";
    }

    qDebug() << "[FolderSync] Suppression distante appliquée :" << relativePath;
    emit fileIntegrated(folder.uuid(), relativePath, false);
}

void FolderSyncService::applyRemoteRename(const models::SharedFolder &folder,
                                           const QString &oldRelativePath,
                                           const QString &newRelativePath,
                                           const QString &machineId)
{
    const QString oldAbsPath = QDir::cleanPath(
        folder.localPath() + QDir::separator() + oldRelativePath);
    const QString newAbsPath = QDir::cleanPath(
        folder.localPath() + QDir::separator() + newRelativePath);

    QDir().mkpath(QFileInfo(newAbsPath).absolutePath());

    if (QFile::exists(oldAbsPath)) {
        if (QFile::exists(newAbsPath)) {
            QFile::remove(newAbsPath);
        }
        if (!QFile::rename(oldAbsPath, newAbsPath)) {
            qWarning() << "[FolderSync] Renommage distant : échec du renommage sur disque :"
                       << oldAbsPath << "->" << newAbsPath;
        }
    }

    if (!m_fileRepository.renameFile(folder.id(), oldRelativePath, newRelativePath)) {
        qWarning() << "[FolderSync] Renommage distant : renameFile échoué pour" << oldRelativePath;
    }

    const auto existing = m_fileRepository.findByRelativePath(folder.id(), newRelativePath);

    if (existing.has_value()) {
        models::FileSyncOperation op;
        op.setType(models::SyncChangeType::Rename);
        op.setFileId(existing->id());
        op.setRelativePath(newRelativePath);
        op.setOldRelativePath(oldRelativePath);
        op.setMachineId(machineId);
        if (!m_repository.insert(op).has_value()) {
            qWarning() << "[FolderSync] SyncOperations insert (Rename) échoué pour" << newRelativePath
                       << "-- erreur SQL:" << m_repository.lastError();
        }
    } else {
        qWarning() << "[FolderSync] Renommage distant : aucune ligne SharedFiles connue pour"
                   << newRelativePath << "-- opération non journalisée (file_id requis)";
    }

    qDebug() << "[FolderSync] Renommage distant appliqué :" << oldRelativePath << "->" << newRelativePath;
    emit fileIntegrated(folder.uuid(), newRelativePath, false);
}

// ---------------------------------------------------------------------------
// Intégration d'un fichier reçu (Release 8)
// ---------------------------------------------------------------------------

QString FolderSyncService::computeHash(const QString &filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) return QString();
    QCryptographicHash hasher(QCryptographicHash::Sha256);
    if (!hasher.addData(&file)) return QString();
    return QString::fromLatin1(hasher.result().toHex());
}

QString FolderSyncService::makeConflictPath(const QString &relativePath,
                                             const QString &shortMachineId)
{
    const QFileInfo fi(relativePath);
    const QString baseName  = fi.completeBaseName();
    const QString suffix    = fi.suffix();
    const QString dir       = fi.path(); // "" or "Docs" etc.

    const QString conflictName = suffix.isEmpty()
        ? QStringLiteral("%1 (%2)").arg(baseName, shortMachineId)
        : QStringLiteral("%1 (%2).%3").arg(baseName, shortMachineId, suffix);

    return (dir.isEmpty() || dir == QStringLiteral("."))
        ? conflictName
        : dir + QStringLiteral("/") + conflictName;
}

void FolderSyncService::registerCatchupPlaceholder(const models::SharedFolder &folder,
                                                     const QString &relativePath,
                                                     const QString &fileHash,
                                                     int version,
                                                     const QString &machineId)
{
    const auto existing = m_fileRepository.findByRelativePath(folder.id(), relativePath);

    models::SharedFile placeholder(0, folder.id(), relativePath);
    placeholder.setHash(fileHash);
    placeholder.setVersion(version > 0 ? version : 1);
    placeholder.setDeleted(false);
    // size reste a 0 (valeur par defaut) : le contenu reel n'est pas
    // encore present sur ce poste (voir commentaire d'appel).
    //
    // CORRECTIF : lastModified etait laisse a sa valeur par defaut
    // (QDateTime() -- invalide, aucun timespec). SharedFileRepository::upsert()
    // bind ensuite file.lastModified().toUTC().toString(Qt::ISODate) tel quel ;
    // avec un QDateTime invalide cette conversion est fragile (le champ SQL
    // last_modified est NOT NULL avec DEFAULT datetime('now'), mais un DEFAULT
    // ne s'applique QUE si la colonne est absente de l'INSERT -- ici on la
    // fournit explicitement, meme vide/invalide). On utilise donc l'heure
    // courante en attendant la vraie date du fichier, qui sera de toute facon
    // ecrasee par integrateReceivedFile() une fois le contenu reel telecharge.
    placeholder.setLastModified(QDateTime::currentDateTimeUtc());

    const auto upserted = m_fileRepository.upsert(placeholder);
    if (!upserted.has_value()) {
        // CORRECTIF : on affichait un avertissement muet, sans jamais dire
        // POURQUOI l'upsert echouait -- ce qui rendait ce bug (silencieux et
        // systematique sur certains postes/bases) impossible a diagnostiquer
        // depuis les logs utilisateur. lastError() expose le vrai message SQL.
        qWarning() << "[FolderSync] placeholder SharedFile échoué pour" << relativePath
                   << "-- erreur SQL:" << m_fileRepository.lastError();
        return;
    }

    // CORRECTIF (historique "Créé" + "Modifié" simultanés côté destinataire) :
    // cette fonction ne fait qu'enregistrer une ligne SharedFiles "creuse"
    // (taille 0, aucun contenu réel) pour qu'un dossier distant sans
    // localPath n'apparaisse pas vide dans l'UI -- ce n'est PAS un
    // événement réel du point de vue de l'utilisateur (aucun fichier n'a
    // encore été reçu). On n'insère donc plus ici d'entrée SyncOperations :
    // l'unique entrée d'historique légitime pour ce fichier sera créée par
    // integrateReceivedFile() lorsque le contenu réel sera effectivement
    // téléchargé (cf. requestFolderResync() une fois localPath défini).
    //
    // Avant ce correctif, un op "Create" était inséré ici, PUIS un second op
    // "Update" était inséré par integrateReceivedFile() dès que le vrai
    // fichier arrivait -- car ce dernier trouvait la ligne SharedFiles
    // placeholder créée ci-dessus et la traitait comme "déjà existante"
    // (existing.has_value() == true). Résultat visible : "Créé" et
    // "Modifié" apparaissaient tous les deux, horodatés au même instant,
    // pour un seul et même fichier fraîchement reçu.
    Q_UNUSED(existing);
}

void FolderSyncService::integrateReceivedFile(const PendingFileTransfer &pending,
                                               const QString &sourcePath)
{
    // 1. Hash du fichier reçu.
    const QString receivedHash = computeHash(sourcePath);
    if (receivedHash.isEmpty()) {
        qWarning() << "[FolderSync] Impossible de hasher" << sourcePath;
        return;
    }

    // 2. Chemin cible absolu.
    const QString targetAbsPath = QDir::cleanPath(
        pending.localFolderPath + QDir::separator() + pending.relativePath);

    // CORRECTIF (historique "Créé" + "Modifié" simultanés côté destinataire) :
    // capturé AVANT toute copie/suppression ci-dessous, car ces opérations
    // vont justement créer/écraser ce fichier. Sert à distinguer une vraie
    // mise à jour (contenu déjà présent physiquement) d'une première
    // réception (aucun octet réel encore sur disque), indépendamment de la
    // ligne SharedFiles qui, elle, peut n'être qu'un placeholder "creux"
    // (taille 0) posé par registerCatchupPlaceholder() lors d'un rattrapage
    // pour un dossier distant sans localPath -- ce placeholder ne doit pas
    // faire passer cette réception pour une "Update".
    const bool hadRealContentOnDisk = QFile::exists(targetAbsPath);

    // 3. Détection de conflit (Release 8).
    bool wasConflict = false;
    QString effectiveRelativePath = pending.relativePath;

    const auto existing = m_fileRepository.findByRelativePath(
        pending.folderId, pending.relativePath);

    if (existing.has_value()
        && !existing->hash().isEmpty()
        && existing->hash() != receivedHash
        && QFile::exists(targetAbsPath))
    {
        // Conflit : une version locale différente existe déjà.
        // On renomme le fichier reçu plutôt que d'écraser.
        const QString shortId = pending.ownerMachineId.left(6);
        effectiveRelativePath = makeConflictPath(pending.relativePath, shortId);
        const QString conflictAbsPath = QDir::cleanPath(
            pending.localFolderPath + QDir::separator() + effectiveRelativePath);

        // Crée les répertoires parents si nécessaire.
        QDir().mkpath(QFileInfo(conflictAbsPath).absolutePath());

        if (!QFile::copy(sourcePath, conflictAbsPath)) {
            qWarning() << "[FolderSync] Copie conflit échouée vers" << conflictAbsPath;
            return;
        }

        wasConflict = true;
        qWarning() << "[FolderSync] Conflit détecté :" << pending.relativePath
                   << "→" << effectiveRelativePath;
        emit conflictDetected(pending.folderUuid, pending.relativePath, effectiveRelativePath);
    }
    else
    {
        // Pas de conflit : copie normale vers le chemin cible.
        // Crée les répertoires parents si nécessaire.
        QDir().mkpath(QFileInfo(targetAbsPath).absolutePath());

        // Supprime l'ancienne version si elle existe (update).
        if (QFile::exists(targetAbsPath)) {
            QFile::remove(targetAbsPath);
        }

        if (!QFile::copy(sourcePath, targetAbsPath)) {
            qWarning() << "[FolderSync] Copie échouée vers" << targetAbsPath;
            return;
        }
    }

    // 4. Infos du fichier final sur disque.
    const QString finalAbsPath = QDir::cleanPath(
        pending.localFolderPath + QDir::separator() + effectiveRelativePath);
    const QFileInfo fi(finalAbsPath);

    // 5. Upsert SharedFile.
    models::SharedFile sharedFile(0, pending.folderId, effectiveRelativePath);
    sharedFile.setHash(receivedHash);
    sharedFile.setSize(fi.size());
    sharedFile.setLastModified(fi.lastModified());
    // Version : utilise la version annoncée si disponible, sinon incrémente.
    sharedFile.setVersion(pending.incomingVersion > 0 ? pending.incomingVersion : 1);
    sharedFile.setDeleted(false);

    const auto upserted = m_fileRepository.upsert(sharedFile);
    if (!upserted.has_value()) {
        qWarning() << "[FolderSync] upsert SharedFile échoué pour" << effectiveRelativePath;
        return;
    }

    // 6. Insert FileSyncOperation.
    // CORRECTIF : anciennement `existing.has_value() && !wasConflict`, ce qui
    // considérait à tort une ligne SharedFiles placeholder (posée par
    // registerCatchupPlaceholder(), sans contenu réel) comme une "mise à
    // jour". On se base désormais sur la présence RÉELLE du fichier sur
    // disque avant cette intégration -- seul indicateur fiable qu'un
    // contenu existait déjà localement.
    const bool isUpdate = hadRealContentOnDisk && !wasConflict;
    models::FileSyncOperation op;
    op.setType(isUpdate ? models::SyncChangeType::Update : models::SyncChangeType::Create);
    op.setFileId(upserted->id());
    op.setRelativePath(effectiveRelativePath);
    op.setVersion(upserted->version());
    op.setMachineId(pending.ownerMachineId);
    // CORRECTIF (diagnostic) : le résultat de insert() n'était jamais
    // vérifié -- un échec SQL (table manquante, contrainte FK, etc.)
    // passait totalement inaperçu, laissant SyncOperations vide sans
    // aucune trace exploitable dans les logs malgré une intégration de
    // fichier par ailleurs réussie (SharedFiles à jour, fichier sur disque).
    if (!m_repository.insert(op).has_value()) {
        qWarning() << "[FolderSync] SyncOperations insert échoué pour" << effectiveRelativePath
                   << "-- erreur SQL:" << m_repository.lastError();
    }

    qDebug() << "[FolderSync] Fichier intégré :" << effectiveRelativePath
             << (wasConflict ? "(conflit)" : "");
    emit fileIntegrated(pending.folderUuid, effectiveRelativePath, wasConflict);
    scheduleFolderNotification(pending.folderUuid);
}

} // namespace core::sync