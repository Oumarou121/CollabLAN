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

namespace core::sync {

namespace {

// Noms des types de messages (distingués du chat par le champ "type").
constexpr const char *kTypeFolderOp        = "folder_op";
constexpr const char *kTypeFolderHello     = "folder_hello";
constexpr const char *kTypeCatchupBatch    = "folder_catchup_batch";
constexpr const char *kTypeFileRequest     = "folder_file_request";

} // namespace

FolderSyncService::FolderSyncService(database::DatabaseManager *dbManager,
                                      core::SharedFolderManager *folderManager,
                                      QObject *parent)
    : QObject(parent)
    , m_repository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_folderManager(folderManager)
{
    // Initialise le curseur à latestId() pour ne pas re-diffuser les
    // opérations déjà présentes en base avant ce démarrage.
    m_lastBroadcastOpId = m_repository.latestId();
}

FolderSyncService::~FolderSyncService() = default;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

void FolderSyncService::setMessagingServer(network::MessagingServer *server)
{
    if (m_messagingServer == server) {
        return;
    }
    m_messagingServer = server;
    if (m_messagingServer) {
        connect(m_messagingServer, &network::MessagingServer::messageReceived,
                this, &FolderSyncService::onServerMessageReceived);
    }
}

void FolderSyncService::setMessagingService(network::MessagingService *service)
{
    if (m_messagingService == service) {
        return;
    }
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
    obj[QStringLiteral("type")]             = QString::fromLatin1(kTypeFolderOp);
    obj[QStringLiteral("folder_uuid")]      = folder.uuid();
    obj[QStringLiteral("folder_name")]      = folder.name();
    obj[QStringLiteral("op_type")]          = models::syncChangeTypeToString(op.type());
    obj[QStringLiteral("relative_path")]    = op.relativePath();
    obj[QStringLiteral("old_relative_path")] = op.oldRelativePath();
    obj[QStringLiteral("version")]          = op.version();
    obj[QStringLiteral("machine_id")]       = op.machineId();
    obj[QStringLiteral("op_id")]            = op.id();

    const quint16 transferPort = m_transferService ? m_transferService->port()
                                                   : network::TransferService::defaultPort();
    obj[QStringLiteral("transfer_port")] = static_cast<int>(transferPort);

    // Enrichit avec hash/taille (info denormalisée depuis SharedFiles).
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
    if (!m_folderManager || changeCount <= 0) {
        return;
    }

    const auto folderOpt = m_folderManager->getFolder(folderId);
    if (!folderOpt.has_value()) {
        return;
    }
    const models::SharedFolder &folder = *folderOpt;

    // Récupère les changeCount opérations les plus récentes du dossier
    // (relativePath hydraté via JOIN). On ne diffuse que celles dont
    // l'id > m_lastBroadcastOpId pour éviter les doublons.
    const auto ops = m_repository.getByFolderId(folderId, changeCount);
    // ops est trié décroissant (plus récent en premier) : on accumule
    // et on rebroadcast dans l'ordre chronologique (plus ancien d'abord).
    QVector<models::FileSyncOperation> newOps;
    for (const auto &op : ops) {
        if (op.id() <= m_lastBroadcastOpId) {
            break; // les suivants sont encore plus anciens
        }
        newOps.prepend(op); // remet dans l'ordre croissant
    }

    for (const auto &op : newOps) {
        if (op.id() > m_lastBroadcastOpId) {
            m_lastBroadcastOpId = op.id();
        }
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
// Réception des messages (côté SERVER et côté CLIENT)
// ---------------------------------------------------------------------------

void FolderSyncService::onServerMessageReceived(const QString &message,
                                                 const QHostAddress &senderAddress)
{
    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8());
    if (!doc.isObject()) {
        return;
    }
    const QJsonObject obj = doc.object();
    const QString type = obj[QStringLiteral("type")].toString();

    if (type == QString::fromLatin1(kTypeFolderOp)) {
        handleFolderOp(obj, senderAddress);
    } else if (type == QString::fromLatin1(kTypeFolderHello)) {
        handleFolderHello(obj);
    } else if (type == QString::fromLatin1(kTypeFileRequest)) {
        handleFolderFileRequest(obj, senderAddress);
    }
    // kTypeCatchupBatch n'est jamais émis par un CLIENT vers le SERVER.
}

void FolderSyncService::onClientMessageReceived(const QString &message)
{
    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8());
    if (!doc.isObject()) {
        return;
    }
    const QJsonObject obj = doc.object();
    const QString type = obj[QStringLiteral("type")].toString();

    if (type == QString::fromLatin1(kTypeFolderOp)) {
        handleFolderOp(obj, QHostAddress());
    } else if (type == QString::fromLatin1(kTypeCatchupBatch)) {
        handleFolderCatchupBatch(obj);
    }
    // folder_hello / folder_file_request ne sont jamais envoyés par le SERVER au CLIENT.
}

// ---------------------------------------------------------------------------
// Gestionnaires de messages entrants
// ---------------------------------------------------------------------------

void FolderSyncService::handleFolderOp(const QJsonObject &obj,
                                        const QHostAddress &senderAddress)
{
    const QString folderUuid     = obj[QStringLiteral("folder_uuid")].toString();
    const QString opType         = obj[QStringLiteral("op_type")].toString();
    const QString relativePath   = obj[QStringLiteral("relative_path")].toString();
    const QString oldRelPath     = obj[QStringLiteral("old_relative_path")].toString();
    const QString machineId      = obj[QStringLiteral("machine_id")].toString();
    const QString fileHash       = obj[QStringLiteral("file_hash")].toString();
    const int version            = obj[QStringLiteral("version")].toInt();
    const quint16 transferPort   = static_cast<quint16>(obj[QStringLiteral("transfer_port")].toInt(
                                        static_cast<int>(network::TransferService::defaultPort())));

    // Ignore les opérations émises par ce poste lui-même.
    if (machineId == m_machineId) {
        return;
    }

    qDebug() << "[FolderSync] Reçu folder_op" << opType << relativePath
             << "depuis" << machineId;

    emit remoteOpReceived(folderUuid, opType, relativePath, oldRelPath,
                          machineId, senderAddress, transferPort);

    // Release 6 — Pour Create/Update : demander le fichier si on possède
    // ce dossier localement mais pas (ou pas la bonne version de) ce fichier.
    if ((opType == QStringLiteral("Create") || opType == QStringLiteral("Update"))
        && m_folderManager)
    {
        // Cherche le dossier par UUID parmi les dossiers locaux.
        const auto folders = m_folderManager->getFolders();
        for (const auto &folder : folders) {
            if (folder.uuid() != folderUuid) {
                continue;
            }
            // Dossier trouvé localement : vérifier si le fichier est à jour.
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
                requestRemoteFile(folderUuid, relativePath, machineId);
            }
            break;
        }
    }
}

void FolderSyncService::handleFolderHello(const QJsonObject &obj)
{
    // Release 7 — Réponse côté SERVER : envoie les opérations depuis last_op_id.
    if (!m_folderManager) {
        return;
    }

    const qint64 lastOpId = static_cast<qint64>(obj[QStringLiteral("last_op_id")].toDouble());
    const quint16 selfTransferPort = m_transferService ? m_transferService->port()
                                                       : network::TransferService::defaultPort();

    QJsonArray opsArray;
    const auto folders = m_folderManager->getFolders();
    for (const auto &folder : folders) {
        // N'envoie que les opérations issues de dossiers dont CE poste est l'origine.
        if (!folder.isLocalOrigin()) {
            continue;
        }

        // getByFolderId trie décroissant (plus récent d'abord) ; on s'arrête
        // dès qu'on atteint un op_id <= lastOpId.
        const auto ops = m_repository.getByFolderId(folder.id(), 500);
        for (const auto &op : ops) {
            if (op.id() <= lastOpId) {
                break;
            }
            QJsonObject opObj = buildFolderOpJson(op, folder);
            // buildFolderOpJson inclut déjà folder_uuid, folder_name, etc.
            // On remplace "type" par le champ interne du batch (pas "folder_op").
            opObj.remove(QStringLiteral("type"));
            opObj[QStringLiteral("transfer_port")] = static_cast<int>(selfTransferPort);
            opsArray.append(opObj);
        }
    }

    QJsonObject batch;
    batch[QStringLiteral("type")]       = QString::fromLatin1(kTypeCatchupBatch);
    batch[QStringLiteral("operations")] = opsArray;

    const QString json = QString::fromUtf8(
        QJsonDocument(batch).toJson(QJsonDocument::Compact));
    broadcastMessage(json);
    qDebug() << "[FolderSync] folder_catchup_batch envoyé :" << opsArray.size() << "opérations";
}

void FolderSyncService::handleFolderCatchupBatch(const QJsonObject &obj)
{
    const QJsonArray opsArray = obj[QStringLiteral("operations")].toArray();
    if (opsArray.isEmpty()) {
        return;
    }

    QVector<models::FileSyncOperation> ops;
    ops.reserve(opsArray.size());
    for (const auto &value : opsArray) {
        if (!value.isObject()) {
            continue;
        }
        const QJsonObject opObj = value.toObject();

        models::FileSyncOperation op;
        op.setId(static_cast<qint64>(opObj[QStringLiteral("op_id")].toDouble()));
        op.setType(models::syncChangeTypeFromString(opObj[QStringLiteral("op_type")].toString()));
        op.setRelativePath(opObj[QStringLiteral("relative_path")].toString());
        op.setOldRelativePath(opObj[QStringLiteral("old_relative_path")].toString());
        op.setVersion(opObj[QStringLiteral("version")].toInt());
        op.setMachineId(opObj[QStringLiteral("machine_id")].toString());
        ops.append(op);

        // Auto-demande du fichier pour Create/Update (même logique que handleFolderOp).
        const QString folderUuid   = opObj[QStringLiteral("folder_uuid")].toString();
        const QString opType       = opObj[QStringLiteral("op_type")].toString();
        const QString relativePath = opObj[QStringLiteral("relative_path")].toString();
        const QString machineId    = opObj[QStringLiteral("machine_id")].toString();
        if ((opType == QStringLiteral("Create") || opType == QStringLiteral("Update"))
            && machineId != m_machineId && m_folderManager)
        {
            const auto folders = m_folderManager->getFolders();
            for (const auto &folder : folders) {
                if (folder.uuid() == folderUuid) {
                    requestRemoteFile(folderUuid, relativePath, machineId);
                    break;
                }
            }
        }
    }

    qDebug() << "[FolderSync] folder_catchup_batch reçu :" << ops.size() << "opérations";
    emit catchupBatchReceived(ops);
}

void FolderSyncService::handleFolderFileRequest(const QJsonObject &obj,
                                                 const QHostAddress &senderAddress)
{
    if (!m_transferService || !m_folderManager) {
        return;
    }

    const QString folderUuid        = obj[QStringLiteral("folder_uuid")].toString();
    const QString relativePath      = obj[QStringLiteral("relative_path")].toString();
    const QString requesterMachineId = obj[QStringLiteral("requester_machine_id")].toString();
    const quint16 requesterPort     = static_cast<quint16>(
                                          obj[QStringLiteral("requester_transfer_port")].toInt(
                                              static_cast<int>(network::TransferService::defaultPort())));

    // Résolution de l'adresse du pair : préférence au senderAddress (connexion
    // directe), sinon on cherche via DiscoveryService par machineId.
    QHostAddress targetAddress = senderAddress;
    if ((targetAddress.isNull() || targetAddress == QHostAddress::Any) && m_discoveryService) {
        const auto peers = m_discoveryService->peers();
        for (const auto &peer : peers) {
            if (peer.id == requesterMachineId) {
                targetAddress = peer.address;
                break;
            }
        }
    }
    if (targetAddress.isNull()) {
        qWarning() << "[FolderSync] folder_file_request : adresse introuvable pour" << requesterMachineId;
        return;
    }

    // Trouve le dossier et le chemin absolu du fichier demandé.
    const auto folders = m_folderManager->getFolders();
    for (const auto &folder : folders) {
        if (folder.uuid() != folderUuid || !folder.isLocalOrigin()) {
            continue;
        }
        const QString absPath = QDir::cleanPath(folder.localPath() + QDir::separator() + relativePath);
        if (!QFile::exists(absPath)) {
            qWarning() << "[FolderSync] folder_file_request : fichier introuvable :" << absPath;
            return;
        }

        const bool ok = m_transferService->sendFile(
            targetAddress, requesterPort, absPath,
            m_machineId, requesterMachineId);
        if (!ok) {
            qWarning() << "[FolderSync] sendFile échoué pour" << absPath;
        } else {
            qDebug() << "[FolderSync] Envoi de" << relativePath << "vers" << targetAddress;
        }
        return;
    }

    qWarning() << "[FolderSync] folder_file_request : dossier" << folderUuid << "introuvable localement";
}

// ---------------------------------------------------------------------------
// API publique : demande de fichier distant
// ---------------------------------------------------------------------------

void FolderSyncService::requestRemoteFile(const QString &folderUuid,
                                           const QString &relativePath,
                                           const QString &ownerMachineId)
{
    const quint16 myTransferPort = m_transferService ? m_transferService->port()
                                                     : network::TransferService::defaultPort();

    QJsonObject req;
    req[QStringLiteral("type")]                    = QString::fromLatin1(kTypeFileRequest);
    req[QStringLiteral("folder_uuid")]             = folderUuid;
    req[QStringLiteral("relative_path")]           = relativePath;
    req[QStringLiteral("requester_machine_id")]    = m_machineId;
    req[QStringLiteral("requester_transfer_port")] = static_cast<int>(myTransferPort);
    req[QStringLiteral("owner_machine_id")]        = ownerMachineId;

    const QString json = QString::fromUtf8(QJsonDocument(req).toJson(QJsonDocument::Compact));
    broadcastMessage(json);
    qDebug() << "[FolderSync] Demande de fichier :" << relativePath << "depuis" << ownerMachineId;
}

} // namespace core::sync
