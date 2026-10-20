#include "SyncService.h"

#include "Messaging/MessagingServer.h"
#include "Messaging/MessagingService.h"
#include "database/Repositories/SyncLogRepository.h"
#include "database/Repositories/ServerElectionRepository.h"
#include "models/SyncLogEntry.h"
#include "models/ServerElection.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <QMetaObject>
#include <QSet>

namespace network {

namespace {
constexpr const char *kMsgSyncRequest = "sync_request";
constexpr const char *kMsgSyncBatch = "sync_batch";
constexpr const char *kMsgSyncAck = "sync_ack";

QJsonObject entryToJson(const models::SyncLogEntry &entry)
{
    QJsonObject obj;
    obj.insert(QStringLiteral("entry_uuid"), entry.entryUuid());
    obj.insert(QStringLiteral("table_name"), entry.tableName());
    obj.insert(QStringLiteral("record_uuid"), entry.recordUuid());
    obj.insert(QStringLiteral("operation"), entry.operation());
    obj.insert(QStringLiteral("payload_json"), entry.payloadJson());
    obj.insert(QStringLiteral("lamport_clock"), entry.lamportClock());
    obj.insert(QStringLiteral("epoch"), entry.epoch());
    obj.insert(QStringLiteral("origin_machine_id"), entry.originMachineId());
    obj.insert(QStringLiteral("updated_at"), entry.updatedAt().toString(Qt::ISODate));
    return obj;
}

models::SyncLogEntry entryFromJson(const QJsonObject &obj)
{
    models::SyncLogEntry entry;
    entry.setEntryUuid(obj.value(QStringLiteral("entry_uuid")).toString());
    entry.setTableName(obj.value(QStringLiteral("table_name")).toString());
    entry.setRecordUuid(obj.value(QStringLiteral("record_uuid")).toString());
    entry.setOperation(obj.value(QStringLiteral("operation")).toString());
    entry.setPayloadJson(obj.value(QStringLiteral("payload_json")).toString());
    entry.setLamportClock(static_cast<qint64>(obj.value(QStringLiteral("lamport_clock")).toDouble()));
    entry.setEpoch(obj.value(QStringLiteral("epoch")).toInt());
    entry.setOriginMachineId(obj.value(QStringLiteral("origin_machine_id")).toString());
    entry.setUpdatedAt(QDateTime::fromString(obj.value(QStringLiteral("updated_at")).toString(), Qt::ISODate));
    return entry;
}

// Memes champs que Application::broadcastServerElectionEvent (canal temps
// reel "server_election_event"), reutilises ici pour le rattrapage par lot
// dans le sync_batch : les deux chemins alimentent en definitive
// ServerElectionRepository::applyRemoteLogEntry, idempotent sur log_uuid.
QJsonObject electionEntryToJson(const models::ServerElectionLogEntry &entry)
{
    QJsonObject obj;
    obj.insert(QStringLiteral("log_uuid"), entry.logUuid());
    obj.insert(QStringLiteral("event"), entry.event());
    obj.insert(QStringLiteral("epoch"), entry.epoch());
    obj.insert(QStringLiteral("machine_uuid"), entry.machineUuid());
    obj.insert(QStringLiteral("created_at"),
               entry.createdAt().isValid()
                   ? entry.createdAt().toUTC().toString(Qt::ISODate)
                   : QString());
    return obj;
}

models::ServerElectionLogEntry electionEntryFromJson(const QJsonObject &obj)
{
    models::ServerElectionLogEntry entry;
    entry.setLogUuid(obj.value(QStringLiteral("log_uuid")).toString());
    entry.setEvent(obj.value(QStringLiteral("event")).toString());
    entry.setEpoch(obj.value(QStringLiteral("epoch")).toInt());
    entry.setMachineUuid(obj.value(QStringLiteral("machine_uuid")).toString());
    entry.setCreatedAt(QDateTime::fromString(obj.value(QStringLiteral("created_at")).toString(), Qt::ISODate));
    return entry;
}
} // namespace

std::vector<models::SyncLogEntry> syncEntriesVisibleTo(const std::vector<models::SyncLogEntry> &entries,
                                                       const QString &userUuid)
{
    const auto payloadOf = [](const models::SyncLogEntry &entry) {
        return QJsonDocument::fromJson(entry.payloadJson().toUtf8()).object();
    };

    // 1er passage : groupes dont l'utilisateur est (ou a ete) membre, et leurs conversations.
    QSet<QString> groups;
    QSet<QString> groupConversations;
    if (!userUuid.isEmpty()) {
        for (const auto &entry : entries) {
            const QJsonObject payload = payloadOf(entry);
            if (entry.tableName() == QStringLiteral("Groups")) {
                bool member = payload.value(QStringLiteral("ownerUuid")).toString() == userUuid;
                for (const auto &value : payload.value(QStringLiteral("memberUuids")).toArray())
                    member = member || value.toString() == userUuid;
                if (member) {
                    groups.insert(entry.recordUuid());
                    groupConversations.insert(payload.value(QStringLiteral("conversationUuid")).toString());
                }
            } else if (entry.tableName() == QStringLiteral("GroupMembers")
                       && payload.value(QStringLiteral("memberUuid")).toString() == userUuid) {
                groups.insert(payload.value(QStringLiteral("groupUuid")).toString());
            }
        }
        // Conversations des groupes rejoints apres coup (ajout de membre) : relues sur l'entree Groups.
        for (const auto &entry : entries) {
            if (entry.tableName() == QStringLiteral("Groups") && groups.contains(entry.recordUuid()))
                groupConversations.insert(payloadOf(entry).value(QStringLiteral("conversationUuid")).toString());
        }
        groupConversations.remove(QString());
    }

    // 2e passage : selection.
    std::vector<models::SyncLogEntry> visible;
    for (const auto &entry : entries) {
        const QString table = entry.tableName();
        if (table == QStringLiteral("Users")) {
            visible.push_back(entry);
            continue;
        }
        if (userUuid.isEmpty())
            continue;
        const QJsonObject payload = payloadOf(entry);
        if (table == QStringLiteral("Groups")) {
            if (groups.contains(entry.recordUuid()))
                visible.push_back(entry);
        } else if (table == QStringLiteral("GroupMembers")) {
            if (groups.contains(payload.value(QStringLiteral("groupUuid")).toString()))
                visible.push_back(entry);
        } else if (table == QStringLiteral("Messages")) {
            const bool direct = payload.value(QStringLiteral("senderUuid")).toString() == userUuid
                || payload.value(QStringLiteral("participant1Uuid")).toString() == userUuid
                || payload.value(QStringLiteral("participant2Uuid")).toString() == userUuid;
            if (direct || groupConversations.contains(payload.value(QStringLiteral("conversationUuid")).toString()))
                visible.push_back(entry);
        }
        // Tout autre type d'entree : jamais envoye a un client (fail closed).
    }
    return visible;
}

SyncService::SyncService(database::SyncLogRepository *repository, QObject *parent)
    : QObject(parent)
    , m_repository(repository)
{
}

SyncService::~SyncService() = default;

void SyncService::setMessagingServer(MessagingServer *server)
{
    if (m_messagingServer == server) {
        return;
    }
    m_messagingServer = server;
    if (m_messagingServer) {
        connect(m_messagingServer, &MessagingServer::messageReceived,
                this, &SyncService::onServerMessageReceived);
    }
}

void SyncService::setMessagingService(MessagingService *service)
{
    if (m_messagingService == service) {
        return;
    }
    m_messagingService = service;
    if (m_messagingService) {
        connect(m_messagingService, &MessagingService::messageReceived,
                this, &SyncService::onClientMessageReceived);
    }
}

void SyncService::setServerElectionRepository(database::ServerElectionRepository *repository)
{
    m_electionRepository = repository;
}

void SyncService::setPermissionManager(QObject *manager)
{
    m_permissionManager = manager;
}

bool SyncService::requestReconciliation(int fromEpoch, const QString &localMachineUuid)
{
    if (!m_messagingService || !m_messagingService->isConnected()) {
        emit reconciliationFailed(QStringLiteral("MessagingService non connecte au TEMP_SERVER"));
        return false;
    }

    QJsonObject obj;
    obj.insert(QStringLiteral("type"), QString::fromLatin1(kMsgSyncRequest));
    obj.insert(QStringLiteral("from_epoch"), fromEpoch);
    obj.insert(QStringLiteral("requester_uuid"), localMachineUuid);

    return m_messagingService->sendMessage(QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact)));
}

void SyncService::onServerMessageReceived(const QString &message, const QHostAddress &senderAddress)
{
    Q_UNUSED(senderAddress);

    if (!m_repository) {
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8());
    if (!doc.isObject()) {
        return;
    }
    const QJsonObject obj = doc.object();
    const QString msg = obj.value(QStringLiteral("type")).toString();

    if (msg == QString::fromLatin1(kMsgSyncRequest)) {
        const int fromEpoch = obj.value(QStringLiteral("from_epoch")).toInt();
        auto entries = m_repository->entriesSinceEpoch(fromEpoch);

        // Le journal contient TOUS les messages prives et tous les groupes. Il n'est envoye en
        // entier qu'a un pair reconnu comme serveur (reconciliation SERVER <-> TEMP_SERVER) ;
        // un client ne recoit que ce qui concerne l'utilisateur identifie sur sa connexion.
        // Sans gestionnaire d'autorisations (tests unitaires isoles) : comportement historique.
        bool peerIsServer = !m_permissionManager;
        if (m_permissionManager && m_messagingServer) {
            QMetaObject::invokeMethod(m_permissionManager, "isTrustedServer", Qt::DirectConnection,
                                      Q_RETURN_ARG(bool, peerIsServer),
                                      Q_ARG(QString, m_messagingServer->currentSenderFingerprint()));
        }
        if (!peerIsServer && m_messagingServer)
            entries = syncEntriesVisibleTo(entries, m_messagingServer->currentSenderUserUuid());

        QJsonArray array;
        for (const auto &entry : entries) {
            array.append(entryToJson(entry));
        }

        QJsonObject batch;
        batch.insert(QStringLiteral("type"), QString::fromLatin1(kMsgSyncBatch));
        batch.insert(QStringLiteral("entries"), array);

        // Rattrapage ServerElectionLog (cf. setServerElectionRepository) :
        // couvre notamment HEARTBEAT_LOST/TEMP_PROMOTED, emis au moment
        // precis ou le pair n'etait pas encore reconnecte et donc jamais
        // recus via broadcastServerElectionEvent (canal temps reel best-effort).
        if (m_electionRepository) {
            const auto electionEntries = m_electionRepository->entriesSinceEpoch(fromEpoch);
            QJsonArray electionArray;
            for (const auto &entry : electionEntries) {
                electionArray.append(electionEntryToJson(entry));
            }
            batch.insert(QStringLiteral("election_entries"), electionArray);
        }

        // Reponse au SEUL demandeur (auparavant diffusee a tous les clients connectes).
        if (m_messagingServer) {
            m_messagingServer->replyToCurrentSender(
                QString::fromUtf8(QJsonDocument(batch).toJson(QJsonDocument::Compact)));
        }
        emit batchSentToPeer(static_cast<int>(entries.size()));
        return;
    }

    if (msg == QString::fromLatin1(kMsgSyncAck)) {
        const int mergedCount = obj.value(QStringLiteral("merged_count")).toInt();
        emit peerAcknowledgedReconciliation(mergedCount);
        return;
    }
}

void SyncService::onClientMessageReceived(const QString &message)
{
    if (!m_repository) {
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8());
    if (!doc.isObject()) {
        return;
    }
    const QJsonObject obj = doc.object();
    const QString msg = obj.value(QStringLiteral("type")).toString();

    if (msg != QString::fromLatin1(kMsgSyncBatch)) {
        return;
    }

    const QJsonArray array = obj.value(QStringLiteral("entries")).toArray();
    std::vector<models::SyncLogEntry> entries;
    entries.reserve(static_cast<size_t>(array.size()));
    for (const auto &value : array) {
        if (!value.isObject()) {
            emit reconciliationFailed(QStringLiteral("Entree sync_batch invalide (pas un objet JSON)"));
            return;
        }
        entries.push_back(entryFromJson(value.toObject()));
    }

    const int mergedCount = m_repository->applyBatch(entries);

    // Rattrapage ServerElectionLog : applyRemoteLogEntry est idempotent sur
    // log_uuid (INSERT OR IGNORE), donc rejouer une entree deja recue via le
    // canal temps reel (broadcastServerElectionEvent) ou une precedente
    // reconciliation ne cree pas de doublon.
    if (m_electionRepository && obj.contains(QStringLiteral("election_entries"))) {
        const QJsonArray electionArray = obj.value(QStringLiteral("election_entries")).toArray();
        for (const auto &value : electionArray) {
            if (!value.isObject()) {
                continue;
            }
            const models::ServerElectionLogEntry entry = electionEntryFromJson(value.toObject());
            if (!m_electionRepository->applyRemoteLogEntry(entry)) {
                qWarning() << "SyncService: echec application election_entries, log_uuid" << entry.logUuid();
            }
        }
    }

    emit reconciliationCompleted(mergedCount);

    if (m_messagingService) {
        QJsonObject ack;
        ack.insert(QStringLiteral("type"), QString::fromLatin1(kMsgSyncAck));
        ack.insert(QStringLiteral("merged_count"), mergedCount);
        m_messagingService->sendMessage(QString::fromUtf8(QJsonDocument(ack).toJson(QJsonDocument::Compact)));
    }
}

} // namespace network