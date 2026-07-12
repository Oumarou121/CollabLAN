#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QRandomGenerator>
#include <QJsonDocument>
#include <QJsonObject>
#include <QHostAddress>
#include <QDateTime>

#include "database/DatabaseManager.h"
#include "database/Repositories/SyncLogRepository.h"
#include "database/Repositories/UserRepository.h"
#include "models/User.h"
#include "models/SyncLogEntry.h"
#include "Sync/SyncService.h"
#include "Messaging/MessagingServer.h"
#include "Messaging/MessagingService.h"
#include "Security/SecurityService.h"

using network::SyncService;
using network::MessagingServer;
using network::MessagingService;
using network::SecurityService;

/*
 * Test d'integration bout-en-bout de la reconciliation post-panne
 * (HYBRID_SERVER_FAILOVER.md, section 7) pour la table Users :
 *
 *  - Un TEMP_SERVER (SyncLog + SQLite propres) a, pendant la panne, cree un
 *    compte puis change son role en Admin : deux vraies entrees SyncLog,
 *    comme le ferait Application::appendUserSyncLog en production.
 *  - Le SERVER officiel (SQLite vierge, ne connait pas ce compte) se
 *    connecte au TEMP_SERVER via un vrai MessagingService/MessagingServer
 *    WebSocket+TLS (pas de mock), demande la reconciliation, recoit le
 *    sync_batch, et fusionne via SyncLogRepository::applyBatch(), qui
 *    route les entrees "Users" vers applyUserEntry (LWW par uuid).
 *
 * Sert aussi de garde non-regression pour le bug corrige dans
 * MessagingServer::start() (la cle privee TLS n'etait jamais configuree :
 * sans ce correctif, connectToHost() echoue et ce test timeout).
 */
class TestSyncServiceIntegration : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<SecurityService> m_securityService;

    struct Node {
        std::unique_ptr<QTemporaryDir> dir;
        std::unique_ptr<database::DatabaseManager> dbManager;
        std::unique_ptr<database::SyncLogRepository> syncLog;
    };

    Node makeNode(const QString &label)
    {
        Node node;
        node.dir = std::make_unique<QTemporaryDir>();
        node.dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-syncintegration-%1-%2")
                .arg(label)
                .arg(QRandomGenerator::global()->generate()));
        const bool opened = node.dbManager->open(node.dir->filePath(QStringLiteral("test.db")));
        Q_ASSERT(opened);
        node.syncLog = std::make_unique<database::SyncLogRepository>(node.dbManager->database());
        return node;
    }

    static QString userPayload(const models::User &user, const QString &updatedAtIso)
    {
        QJsonObject payload;
        payload.insert(QStringLiteral("name"), user.name());
        payload.insert(QStringLiteral("ipAddress"), user.ipAddress());
        payload.insert(QStringLiteral("status"), models::userStatusToString(user.status()));
        payload.insert(QStringLiteral("role"), models::userRoleToString(user.role()));
        payload.insert(QStringLiteral("passwordHash"), user.passwordHash());
        payload.insert(QStringLiteral("passwordSalt"), user.passwordSalt());
        payload.insert(QStringLiteral("updatedAt"), updatedAtIso);
        return QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));
    }

private slots:
    void initTestCase()
    {
        m_securityService = std::make_unique<SecurityService>(QTemporaryDir().path());
        QVERIFY(m_securityService->initialize());
    }

    void reconciliationReplaysUserRoleChangeFromTempServer()
    {
        Node tempServer = makeNode(QStringLiteral("temp"));
        Node officialServer = makeNode(QStringLiteral("official"));

        // --- Etat du TEMP_SERVER a l'issue de la panne -----------------
        database::UserRepository tempUsers(tempServer.dbManager->database());

        models::User carol;
        carol.setName(QStringLiteral("carol"));
        carol.setPasswordHash(QStringLiteral("hash"));
        carol.setPasswordSalt(QStringLiteral("salt"));
        carol.setRole(models::UserRole::User);
        const QDateTime createdAt = QDateTime::currentDateTimeUtc().addSecs(-60);
        carol.setUpdatedAt(createdAt);

        const int carolId = tempUsers.create(carol);
        QVERIFY(carolId >= 0);
        const auto createdCarol = tempUsers.findById(carolId);
        QVERIFY(createdCarol.has_value());
        QVERIFY(!createdCarol->uuid().isEmpty());

        // Entree INSERT (simule Application::appendUserSyncLog a la creation).
        {
            models::SyncLogEntry entry;
            entry.setEntryUuid(QStringLiteral("entry-insert-carol"));
            entry.setTableName(QStringLiteral("Users"));
            entry.setRecordUuid(createdCarol->uuid());
            entry.setOperation(models::SyncOperation::Insert);
            entry.setPayloadJson(userPayload(*createdCarol, createdAt.toString(Qt::ISODate)));
            entry.setLamportClock(1);
            entry.setEpoch(5);
            entry.setOriginMachineId(QStringLiteral("temp-server-uuid"));
            entry.setUpdatedAt(createdAt);
            QVERIFY(tempServer.syncLog->append(entry));
        }

        // Puis promotion en Admin par l'admin connecte au TEMP_SERVER
        // (updated_at plus recent que la creation).
        const QDateTime roleChangeAt = QDateTime::currentDateTimeUtc();
        models::User promotedCarol = *createdCarol;
        promotedCarol.setRole(models::UserRole::Admin);
        promotedCarol.setUpdatedAt(roleChangeAt);
        {
            models::SyncLogEntry entry;
            entry.setEntryUuid(QStringLiteral("entry-update-carol-role"));
            entry.setTableName(QStringLiteral("Users"));
            entry.setRecordUuid(createdCarol->uuid());
            entry.setOperation(models::SyncOperation::Update);
            entry.setPayloadJson(userPayload(promotedCarol, roleChangeAt.toString(Qt::ISODate)));
            entry.setLamportClock(2);
            entry.setEpoch(5);
            entry.setOriginMachineId(QStringLiteral("temp-server-uuid"));
            entry.setUpdatedAt(roleChangeAt);
            QVERIFY(tempServer.syncLog->append(entry));
        }

        // Le SERVER officiel ne connait pas encore ce compte.
        QVERIFY(!database::UserRepository(officialServer.dbManager->database())
                     .findByUuid(createdCarol->uuid())
                     .has_value());

        // --- Reseau reel : WebSocket + TLS, pas de mock ----------------
        MessagingServer tempMessagingServer(m_securityService.get());
        QVERIFY(tempMessagingServer.start(28401));

        MessagingService officialMessagingClient(m_securityService.get());

        SyncService tempSyncService(tempServer.syncLog.get());
        tempSyncService.setMessagingServer(&tempMessagingServer);

        SyncService officialSyncService(officialServer.syncLog.get());
        officialSyncService.setMessagingService(&officialMessagingClient);

        QSignalSpy connectedSpy(&officialMessagingClient, &MessagingService::connected);
        QVERIFY(officialMessagingClient.connectToHost(QHostAddress::LocalHost, 28401));
        QVERIFY(connectedSpy.wait(5000));

        QSignalSpy reconciliationSpy(&officialSyncService, &SyncService::reconciliationCompleted);
        QSignalSpy ackSpy(&tempSyncService, &SyncService::peerAcknowledgedReconciliation);

        QVERIFY(officialSyncService.requestReconciliation(0, QStringLiteral("official-server-uuid")));

        QVERIFY(reconciliationSpy.wait(5000));
        QCOMPARE(reconciliationSpy.count(), 1);
        QCOMPARE(reconciliationSpy.first().at(0).toInt(), 2); // insert + update

        QVERIFY(ackSpy.wait(5000));
        QCOMPARE(ackSpy.count(), 1);
        QCOMPARE(ackSpy.first().at(0).toInt(), 2);

        // --- Assertion finale : le SERVER officiel a bien applique le --
        // --- changement de role fait pendant la panne (LWW par uuid). -
        const auto merged = database::UserRepository(officialServer.dbManager->database())
                                 .findByUuid(createdCarol->uuid());
        QVERIFY(merged.has_value());
        QCOMPARE(merged->name(), QStringLiteral("carol"));
        QCOMPARE(merged->role(), models::UserRole::Admin);

        officialMessagingClient.disconnectFromHost();
        tempMessagingServer.stop();
    }
};

QTEST_MAIN(TestSyncServiceIntegration)
#include "test_syncserviceintegration.moc"