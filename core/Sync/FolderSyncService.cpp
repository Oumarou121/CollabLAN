#include "FolderSyncService.h"

#include "core/SharedFolderManager.h"
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

void FolderSyncService::announceAccessGranted(qint64 folderId, qint64 userId,
                                               models::SharedFolderPermission permission)
{
    if (!m_folderManager) return;

    const auto folder = m_folderManager->getFolder(folderId);
    if (!folder.has_value()) return;

    const auto owner = m_userRepository.findById(static_cast<int>(folder->ownerId()));
    const auto grantedUser = m_userRepository.findById(static_cast<int>(userId));
    if (!owner.has_value() || !grantedUser.has_value()) {
        qWarning() << "[FolderSync] announceAccessGranted : proprietaire ou utilisateur introuvable, annonce annulee";
        return;
    }

    QJsonObject obj;
    obj[QStringLiteral("type")]              = QString::fromLatin1(kTypeAccessGranted);
    obj[QStringLiteral("folder_uuid")]       = folder->uuid();
    obj[QStringLiteral("folder_name")]       = folder->name();
    obj[QStringLiteral("owner_uuid")]        = owner->uuid();
    obj[QStringLiteral("user_uuid")]         = grantedUser->uuid();
    obj[QStringLiteral("permission")]        = models::sharedFolderPermissionToString(permission);
    obj[QStringLiteral("origin_machine_id")] = m_machineId;

    const QString json = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    broadcastMessage(json);
    qDebug() << "[FolderSync] Annonce d'acces diffusée : dossier" << folder->name()
             << "-> utilisateur" << grantedUser->name();
}

void FolderSyncService::onConnectedToServer()
{
    const qint64 lastOpId = m_repository.latestId();
    QJsonObject hello;
    hello[QStringLiteral("type")]        = QString::fromLatin1(kTypeFolderHello);
    hello[QStringLiteral("machine_id")]  = m_machineId;
    hello[QStringLiteral("last_op_id")] = lastOpId;
    const QString json = QString::fromUtf8(QJsonDocument(hello).toJson(QJsonDocument::Compact));
    sendMessageToServer(json);
    qDebug() << "[FolderSync] folder_hello envoyé, last_op_id =" << lastOpId;
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

    if (type == QString::fromLatin1(kTypeFolderOp))
        handleFolderOp(obj, senderAddress);
    else if (type == QString::fromLatin1(kTypeFolderHello))
        handleFolderHello(obj);
    else if (type == QString::fromLatin1(kTypeFileRequest))
        handleFolderFileRequest(obj, senderAddress);
    else if (type == QString::fromLatin1(kTypeAccessGranted)) {
        handleFolderAccessGranted(obj);
        // Relais vers les autres clients connectes : ce message peut nous
        // parvenir d'un CLIENT (via MessagingService -> serveur), qui ne
        // peut pas rejoindre directement les autres clients. Le SERVER
        // (hub, cf. doc de conception) doit donc le rediffuser. Sans danger
        // de boucle : handleFolderAccessGranted() s'auto-protege via
        // origin_machine_id == m_machineId, et un client ne rediffuse
        // jamais (seul onServerMessageReceived le fait).
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
    else if (type == QString::fromLatin1(kTypeAccessGranted))
        handleFolderAccessGranted(obj);
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
        for (const auto &folder : folders) {
            if (folder.uuid() != folderUuid) continue;
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
    } else if (opType == QStringLiteral("Delete")) {
        for (const auto &folder : m_folderManager->getFolders()) {
            if (folder.uuid() == folderUuid) {
                applyRemoteDelete(folder, relativePath, machineId);
                break;
            }
        }
    } else if (opType == QStringLiteral("Rename")) {
        for (const auto &folder : m_folderManager->getFolders()) {
            if (folder.uuid() == folderUuid) {
                applyRemoteRename(folder, oldRelPath, relativePath, machineId);
                break;
            }
        }
    }
}

void FolderSyncService::handleFolderHello(const QJsonObject &obj)
{
    if (!m_folderManager) return;
    const qint64 lastOpId = static_cast<qint64>(obj[QStringLiteral("last_op_id")].toDouble());
    const quint16 selfPort = m_transferService ? m_transferService->port()
                                               : network::TransferService::defaultPort();

    QJsonArray opsArray;
    const auto folders = m_folderManager->getFolders();
    for (const auto &folder : folders) {
        if (!folder.isLocalOrigin()) continue;
        const auto ops = m_repository.getByFolderId(folder.id(), 500);
        for (const auto &op : ops) {
            if (op.id() <= lastOpId) break;
            QJsonObject opObj = buildFolderOpJson(op, folder);
            opObj.remove(QStringLiteral("type"));
            opObj[QStringLiteral("transfer_port")] = static_cast<int>(selfPort);
            opsArray.append(opObj);
        }
    }

    QJsonObject batch;
    batch[QStringLiteral("type")]       = QString::fromLatin1(kTypeCatchupBatch);
    batch[QStringLiteral("operations")] = opsArray;
    const QString json = QString::fromUtf8(
        QJsonDocument(batch).toJson(QJsonDocument::Compact));
    broadcastMessage(json);
    qDebug() << "[FolderSync] folder_catchup_batch envoyé :" << opsArray.size() << "ops";
}

void FolderSyncService::handleFolderCatchupBatch(const QJsonObject &obj)
{
    const QJsonArray opsArray = obj[QStringLiteral("operations")].toArray();
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
        const QString fileHash     = opObj[QStringLiteral("file_hash")].toString();
        const int version          = opObj[QStringLiteral("version")].toInt();

        if (machineId == m_machineId || !m_folderManager) continue;

        if (opType == QStringLiteral("Create") || opType == QStringLiteral("Update")) {
            const auto folders = m_folderManager->getFolders();
            for (const auto &folder : folders) {
                if (folder.uuid() == folderUuid) {
                    requestRemoteFile(folderUuid, relativePath, machineId,
                                      folder.id(), folder.localPath(),
                                      fileHash, version);
                    break;
                }
            }
        } else if (opType == QStringLiteral("Delete")) {
            for (const auto &folder : m_folderManager->getFolders()) {
                if (folder.uuid() == folderUuid) {
                    applyRemoteDelete(folder, relativePath, machineId);
                    break;
                }
            }
        } else if (opType == QStringLiteral("Rename")) {
            for (const auto &folder : m_folderManager->getFolders()) {
                if (folder.uuid() == folderUuid) {
                    applyRemoteRename(folder, oldRelPath, relativePath, machineId);
                    break;
                }
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
        const QString absPath = QDir::cleanPath(
            folder.localPath() + QDir::separator() + relativePath);
        if (!QFile::exists(absPath)) {
            qWarning() << "[FolderSync] folder_file_request : fichier introuvable :" << absPath;
            return;
        }
        const bool ok = m_transferService->sendFile(
            targetAddress, requesterPort, absPath, m_machineId, requesterMachineId);
        if (!ok)
            qWarning() << "[FolderSync] sendFile échoué pour" << absPath;
        else
            qDebug() << "[FolderSync] Envoi de" << relativePath << "vers" << targetAddress;
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
    m_folderManager->grantAccess(folder->id(), grantedUser->id(), owner->id(), permission);

    qDebug() << "[FolderSync] Dossier partagé reçu :" << folder->name()
             << "-> accès accordé à" << grantedUser->name();
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
                                           const QString &/*recipientUuid*/,
                                           const QHostAddress &/*peerAddress*/,
                                           const QString &peerMachineId)
{
    if (!incoming) return; // On ne s'occupe que des réceptions.

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
    const auto it = m_activeByTransferKey.find(transferKey);
    if (it == m_activeByTransferKey.end()) return; // Pas un transfert folder-sync.

    const PendingFileTransfer pending = it.value();
    m_activeByTransferKey.erase(it);

    integrateReceivedFile(pending, filePath);
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

    models::FileSyncOperation op;
    op.setType(models::SyncChangeType::Delete);
    if (existing.has_value()) op.setFileId(existing->id());
    op.setRelativePath(relativePath);
    op.setMachineId(machineId);
    m_repository.insert(op);

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

    models::FileSyncOperation op;
    op.setType(models::SyncChangeType::Rename);
    if (existing.has_value()) op.setFileId(existing->id());
    op.setRelativePath(newRelativePath);
    op.setOldRelativePath(oldRelativePath);
    op.setMachineId(machineId);
    m_repository.insert(op);

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
    const bool isUpdate = existing.has_value() && !wasConflict;
    models::FileSyncOperation op;
    op.setType(isUpdate ? models::SyncChangeType::Update : models::SyncChangeType::Create);
    op.setFileId(upserted->id());
    op.setRelativePath(effectiveRelativePath);
    op.setVersion(upserted->version());
    op.setMachineId(pending.ownerMachineId);
    m_repository.insert(op);

    qDebug() << "[FolderSync] Fichier intégré :" << effectiveRelativePath
             << (wasConflict ? "(conflit)" : "");
    emit fileIntegrated(pending.folderUuid, effectiveRelativePath, wasConflict);
}

} // namespace core::sync
