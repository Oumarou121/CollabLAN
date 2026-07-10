#include "SyncService.h"

#include "Messaging/MessagingServer.h"
#include "Messaging/MessagingService.h"
#include "database/Repositories/SyncLogRepository.h"
#include "models/SyncLogEntry.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>

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
} // namespace

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
        const auto entries = m_repository->entriesSinceEpoch(fromEpoch);

        QJsonArray array;
        for (const auto &entry : entries) {
            array.append(entryToJson(entry));
        }

        QJsonObject batch;
        batch.insert(QStringLiteral("type"), QString::fromLatin1(kMsgSyncBatch));
        batch.insert(QStringLiteral("entries"), array);

        if (m_messagingServer) {
            m_messagingServer->broadcastMessage(
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
    emit reconciliationCompleted(mergedCount);

    if (m_messagingService) {
        QJsonObject ack;
        ack.insert(QStringLiteral("type"), QString::fromLatin1(kMsgSyncAck));
        ack.insert(QStringLiteral("merged_count"), mergedCount);
        m_messagingService->sendMessage(QString::fromUtf8(QJsonDocument(ack).toJson(QJsonDocument::Compact)));
    }
}

} // namespace network
