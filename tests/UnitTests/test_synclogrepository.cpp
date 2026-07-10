#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "SyncLogRepository.h"
#include "DatabaseManager.h"
#include "models/SyncLogEntry.h"

using database::SyncLogRepository;

class TestSyncLogRepository : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<database::DatabaseManager> m_dbManager;
    std::unique_ptr<SyncLogRepository> m_repository;

    void freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        QVERIFY(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-synclogrepository-%1").arg(QRandomGenerator::global()->generate()));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        QVERIFY(opened);

        m_repository = std::make_unique<SyncLogRepository>(m_dbManager->database());
    }

    models::SyncLogEntry makeEntry(const QString &uuid, int epoch, qint64 lamport,
                                    const QString &originMachineId = QStringLiteral("machine-a"))
    {
        models::SyncLogEntry entry;
        entry.setEntryUuid(uuid);
        entry.setTableName(QStringLiteral("Messages"));
        entry.setRecordUuid(QStringLiteral("record-%1").arg(uuid));
        entry.setOperation(models::SyncOperation::Insert);
        entry.setPayloadJson(QStringLiteral("{\"content\":\"hello\"}"));
        entry.setLamportClock(lamport);
        entry.setEpoch(epoch);
        entry.setOriginMachineId(originMachineId);
        entry.setUpdatedAt(QDateTime::currentDateTimeUtc());
        return entry;
    }

private slots:
    void cleanup()
    {
        m_repository.reset();
        if (m_dbManager) {
            m_dbManager->close();
        }
        m_dbManager.reset();
        m_dir.reset();
    }

    void appendAndRetrieveSinceEpoch()
    {
        freshDatabase();

        QVERIFY(m_repository->append(makeEntry(QStringLiteral("uuid-1"), 3, 1)));
        QVERIFY(m_repository->append(makeEntry(QStringLiteral("uuid-2"), 4, 2)));
        QVERIFY(m_repository->append(makeEntry(QStringLiteral("uuid-0"), 2, 0)));

        const auto entries = m_repository->entriesSinceEpoch(3);
        QCOMPARE(entries.size(), static_cast<size_t>(2));
        QCOMPARE(entries[0].entryUuid(), QStringLiteral("uuid-1"));
        QCOMPARE(entries[1].entryUuid(), QStringLiteral("uuid-2"));
    }

    void applyBatchIsIdempotent()
    {
        freshDatabase();

        std::vector<models::SyncLogEntry> batch = {
            makeEntry(QStringLiteral("uuid-a"), 5, 10),
            makeEntry(QStringLiteral("uuid-b"), 5, 11),
        };

        const int firstPass = m_repository->applyBatch(batch);
        QCOMPARE(firstPass, 2);

        // Rejouer le meme lot (sync_batch retransmis) ne doit rien dupliquer.
        const int secondPass = m_repository->applyBatch(batch);
        QCOMPARE(secondPass, 0);

        QCOMPARE(m_repository->entriesSinceEpoch(0).size(), static_cast<size_t>(2));
    }

    void highestLamportClockTracksMax()
    {
        freshDatabase();

        QCOMPARE(m_repository->highestLamportClock(), static_cast<qint64>(0));

        m_repository->append(makeEntry(QStringLiteral("uuid-x"), 1, 7));
        m_repository->append(makeEntry(QStringLiteral("uuid-y"), 1, 3));

        QCOMPARE(m_repository->highestLamportClock(), static_cast<qint64>(7));
    }

    void peerSyncStateRoundTrip()
    {
        freshDatabase();

        QCOMPARE(m_repository->lastSyncedEpoch(QStringLiteral("temp-server-uuid")), 0);

        QVERIFY(m_repository->markPeerSynced(QStringLiteral("temp-server-uuid"), 6));
        QCOMPARE(m_repository->lastSyncedEpoch(QStringLiteral("temp-server-uuid")), 6);

        // Une nouvelle reconciliation met a jour la meme ligne (upsert).
        QVERIFY(m_repository->markPeerSynced(QStringLiteral("temp-server-uuid"), 8));
        QCOMPARE(m_repository->lastSyncedEpoch(QStringLiteral("temp-server-uuid")), 8);
    }
};

QTEST_GUILESS_MAIN(TestSyncLogRepository)
#include "test_synclogrepository.moc"
