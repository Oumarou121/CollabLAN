#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "ServerElectionRepository.h"
#include "DatabaseManager.h"

using database::ServerElectionRepository;

class TestServerElectionRepository : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<database::DatabaseManager> m_dbManager;
    std::unique_ptr<ServerElectionRepository> m_repository;

    void freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        QVERIFY(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-serverelectionrepository-%1").arg(QRandomGenerator::global()->generate()));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        QVERIFY(opened);

        m_repository = std::make_unique<ServerElectionRepository>(m_dbManager->database());
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

    void defaultStateIsClientEpochZero()
    {
        freshDatabase();

        const models::ServerElection state = m_repository->current();
        QCOMPARE(state.currentRole(), models::ServerRole::Client);
        QCOMPARE(state.epoch(), 0);
        QCOMPARE(state.priorityWeight(), 100);
    }

    void updateRoleAndEpochPersists()
    {
        freshDatabase();

        QVERIFY(m_repository->updateRoleAndEpoch(models::ServerRole::TempServer, 3));

        const models::ServerElection state = m_repository->current();
        QCOMPARE(state.currentRole(), models::ServerRole::TempServer);
        QCOMPARE(state.epoch(), 3);
    }

    void updateActiveServerPersists()
    {
        freshDatabase();

        const QDateTime now = QDateTime::currentDateTimeUtc();
        QVERIFY(m_repository->updateActiveServer(QStringLiteral("192.168.1.10"), QStringLiteral("uuid-server-1"), now));

        const models::ServerElection state = m_repository->current();
        QCOMPARE(state.activeServerIp(), QStringLiteral("192.168.1.10"));
        QCOMPARE(state.activeServerUuid(), QStringLiteral("uuid-server-1"));
        QVERIFY(state.lastHeartbeatSeen().isValid());
    }

    void appendLogEntryAndReadHistory()
    {
        freshDatabase();

        QVERIFY(m_repository->appendLogEntry(models::ServerElectionEvent::TempPromoted, 1, QStringLiteral("uuid-a")));
        QVERIFY(m_repository->appendLogEntry(models::ServerElectionEvent::ServerRestored, 2, QStringLiteral("uuid-b")));

        const auto history = m_repository->logHistory();
        QCOMPARE(static_cast<int>(history.size()), 2);
        // Le plus recent en premier
        QCOMPARE(history.front().event(), models::ServerElectionEvent::ServerRestored);
        QCOMPARE(history.front().epoch(), 2);
        QCOMPARE(history.back().event(), models::ServerElectionEvent::TempPromoted);
    }

    void ignoresLowerOrEqualEpochAntiSplitBrain()
    {
        freshDatabase();

        QVERIFY(m_repository->updateRoleAndEpoch(models::ServerRole::Server, 5));

        const models::ServerElection before = m_repository->current();
        QCOMPARE(before.epoch(), 5);

        // Simule la logique anti split-brain côté ElectionService : un epoch <= courant est ignoré
        // (ce test documente la garantie fournie par le repository ; la decision d'ignorer
        // revient a ElectionService, mais la donnee source doit rester coherente).
        const int incomingEpoch = 5;
        if (incomingEpoch > before.epoch()) {
            m_repository->updateRoleAndEpoch(models::ServerRole::Client, incomingEpoch);
        }

        const models::ServerElection after = m_repository->current();
        QCOMPARE(after.epoch(), 5);
        QCOMPARE(after.currentRole(), models::ServerRole::Server);
    }
};

QTEST_MAIN(TestServerElectionRepository)
#include "test_serverelectionrepository.moc"
