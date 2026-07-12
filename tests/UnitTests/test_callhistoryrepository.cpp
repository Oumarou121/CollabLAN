#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "database/DatabaseManager.h"
#include "database/Repositories/CallHistoryRepository.h"
#include "database/Repositories/UserRepository.h"

class TestCallHistoryRepository : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_tempDir;
    database::DatabaseManager *m_dbManager = nullptr;
    int m_userId = -1;

    models::CallHistoryEntry makeEntry(models::CallDirection direction, const QString &address) const
    {
        models::CallHistoryEntry entry;
        entry.setLocalUserId(m_userId);
        entry.setDirection(direction);
        entry.setPeerAddress(address);
        entry.setPeerName(QStringLiteral("poste-test"));
        entry.setStatus(models::CallStatus::InProgress);
        entry.setStartedAt(QDateTime::currentDateTimeUtc());
        return entry;
    }

private slots:
    void init()
    {
        QVERIFY(m_tempDir.isValid());
        const QString dbPath = m_tempDir.filePath(
            QStringLiteral("test_%1.sqlite").arg(QRandomGenerator::global()->generate()));
        m_dbManager = new database::DatabaseManager(
            QStringLiteral("test_callhistoryrepo_connection_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(m_dbManager->open(dbPath));

        database::UserRepository userRepo(m_dbManager->database());
        models::User user;
        user.setName(QStringLiteral("callUser"));
        user.setPasswordHash(QStringLiteral("hash"));
        user.setPasswordSalt(QStringLiteral("salt"));
        m_userId = userRepo.create(user);
        QVERIFY(m_userId >= 0);
    }

    void cleanup()
    {
        delete m_dbManager;
        m_dbManager = nullptr;
    }

    void testCreateReturnsGeneratedIdWithInProgressStatus()
    {
        database::CallHistoryRepository repo(m_dbManager->database());

        const int id = repo.create(makeEntry(models::CallDirection::Outgoing, QStringLiteral("192.168.1.42")));
        QVERIFY2(id >= 0, qPrintable(repo.lastError()));

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QCOMPARE(found->peerAddress(), QStringLiteral("192.168.1.42"));
        QCOMPARE(found->direction(), models::CallDirection::Outgoing);
        QCOMPARE(found->status(), models::CallStatus::InProgress);
        QCOMPARE(found->localUserId(), m_userId);
        QVERIFY(!found->connectedAt().isValid());
        QVERIFY(!found->endedAt().isValid());
    }

    void testFindByIdMissingReturnsNullopt()
    {
        database::CallHistoryRepository repo(m_dbManager->database());
        QVERIFY(!repo.findById(9999).has_value());
    }

    void testCreateWithUnknownLocalUserPersists()
    {
        // Meme logique que Transfers (migration 012) : un appel recu avant
        // authentification, ou depuis/vers un poste sans compte local
        // resolu, doit malgre tout etre enregistre (local_user_id = -1
        // stocke comme NULL) plutot que rejete par la contrainte de cle
        // etrangere (PRAGMA foreign_keys=ON actif dans toute l'application).
        database::CallHistoryRepository repo(m_dbManager->database());
        models::CallHistoryEntry entry = makeEntry(models::CallDirection::Incoming, QStringLiteral("10.0.0.5"));
        entry.setLocalUserId(-1);

        const int id = repo.create(entry);
        QVERIFY2(id >= 0, qPrintable(repo.lastError()));

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QCOMPARE(found->localUserId(), -1);
    }

    void testMarkConnectedPersists()
    {
        database::CallHistoryRepository repo(m_dbManager->database());
        const int id = repo.create(makeEntry(models::CallDirection::Outgoing, QStringLiteral("192.168.1.10")));
        QVERIFY(id >= 0);

        const QDateTime connectedAt = QDateTime::currentDateTimeUtc();
        QVERIFY(repo.markConnected(id, connectedAt));

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QVERIFY(found->connectedAt().isValid());
        // Le statut reste InProgress tant que markEnded() n'a pas ete appele.
        QCOMPARE(found->status(), models::CallStatus::InProgress);
    }

    void testMarkEndedCompletedPersistsDuration()
    {
        database::CallHistoryRepository repo(m_dbManager->database());
        const int id = repo.create(makeEntry(models::CallDirection::Outgoing, QStringLiteral("192.168.1.11")));
        QVERIFY(id >= 0);

        const QDateTime connectedAt = QDateTime::currentDateTimeUtc();
        QVERIFY(repo.markConnected(id, connectedAt));
        const QDateTime endedAt = connectedAt.addSecs(90);

        QVERIFY(repo.markEnded(id, models::CallStatus::Completed, endedAt, 90));

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QCOMPARE(found->status(), models::CallStatus::Completed);
        QCOMPARE(found->durationSeconds(), 90);
        QVERIFY(found->endedAt().isValid());
    }

    void testMarkEndedMissedHasNoDuration()
    {
        database::CallHistoryRepository repo(m_dbManager->database());
        const int id = repo.create(makeEntry(models::CallDirection::Incoming, QStringLiteral("192.168.1.12")));
        QVERIFY(id >= 0);

        QVERIFY(repo.markEnded(id, models::CallStatus::Missed, QDateTime::currentDateTimeUtc(), std::nullopt));

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QCOMPARE(found->status(), models::CallStatus::Missed);
        QCOMPARE(found->durationSeconds(), -1);
    }

    void testFindByUserReturnsOnlyThatUsersCalls()
    {
        database::CallHistoryRepository repo(m_dbManager->database());
        QVERIFY(repo.create(makeEntry(models::CallDirection::Outgoing, QStringLiteral("192.168.1.20"))) >= 0);
        QVERIFY(repo.create(makeEntry(models::CallDirection::Incoming, QStringLiteral("192.168.1.21"))) >= 0);

        models::CallHistoryEntry otherUserEntry = makeEntry(models::CallDirection::Outgoing, QStringLiteral("192.168.1.22"));
        otherUserEntry.setLocalUserId(-1);
        QVERIFY(repo.create(otherUserEntry) >= 0);

        const auto userCalls = repo.findByUser(m_userId);
        QCOMPARE(static_cast<int>(userCalls.size()), 2);
    }

    void testFindAllOrdersMostRecentFirst()
    {
        database::CallHistoryRepository repo(m_dbManager->database());
        const int firstId = repo.create(makeEntry(models::CallDirection::Outgoing, QStringLiteral("192.168.1.30")));
        QVERIFY(firstId >= 0);
        const int secondId = repo.create(makeEntry(models::CallDirection::Outgoing, QStringLiteral("192.168.1.31")));
        QVERIFY(secondId >= 0);

        const auto all = repo.findAll();
        QVERIFY(static_cast<int>(all.size()) >= 2);
        QCOMPARE(all.front().id(), secondId);
    }

    void testRemoveDeletesEntry()
    {
        database::CallHistoryRepository repo(m_dbManager->database());
        const int id = repo.create(makeEntry(models::CallDirection::Outgoing, QStringLiteral("192.168.1.40")));
        QVERIFY(id >= 0);

        QVERIFY(repo.remove(id));
        QVERIFY(!repo.findById(id).has_value());
    }
};

QTEST_MAIN(TestCallHistoryRepository)
#include "test_callhistoryrepository.moc"
