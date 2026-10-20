#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>
#include <QSqlQuery>

#include "SyncLogRepository.h"
#include "DatabaseManager.h"
#include "models/SyncLogEntry.h"
#include "database/Repositories/UserRepository.h"
#include "models/User.h"

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

        QSqlQuery seedUser(m_dbManager->database());
        // uuid renseigne : SyncLogRepository::applyMessageEntry/applyGroupEntry
        // resolvent l'expediteur/le proprietaire par uuid (cf. migration 011),
        // jamais par id local, puisque celui-ci n'a aucune raison de coincider
        // entre deux machines.
        QVERIFY(seedUser.exec(QStringLiteral(
            "INSERT INTO Users (id, name, password_hash, password_salt, uuid) "
            "VALUES (1, 'phase4-user', 'hash', 'salt', 'user-uuid-1')")));
    }

    models::SyncLogEntry makeEntry(const QString &uuid, int epoch, qint64 lamport,
                                    const QString &originMachineId = QStringLiteral("machine-a"))
    {
        models::SyncLogEntry entry;
        entry.setEntryUuid(uuid);
        entry.setTableName(QStringLiteral("Messages"));
        const qint64 messageId = 1000 + lamport;
        entry.setRecordUuid(QString::number(messageId));
        entry.setOperation(models::SyncOperation::Insert);
        // senderUuid/conversationUuid : applyMessageEntry resout l'expediteur
        // et la conversation par uuid, pas par id local (cf. migration 011).
        entry.setPayloadJson(QStringLiteral(
            R"json({"senderUuid":"user-uuid-1","conversationUuid":"conv-uuid-1","content":"hello","timestamp":"2026-01-01T00:00:00Z","isRead":false})json"));
        entry.setLamportClock(lamport);
        entry.setEpoch(epoch);
        entry.setOriginMachineId(originMachineId);
        entry.setUpdatedAt(QDateTime::currentDateTimeUtc());
        return entry;
    }

    models::SyncLogEntry makeUserEntry(const QString &entryUuid, const QString &recordUuid,
                                        const QString &operation, const QString &name,
                                        const QString &updatedAt,
                                        const QString &role = QStringLiteral("User"))
    {
        models::SyncLogEntry entry;
        entry.setEntryUuid(entryUuid);
        entry.setTableName(QStringLiteral("Users"));
        entry.setRecordUuid(recordUuid);
        entry.setOperation(operation);
        entry.setPayloadJson(QStringLiteral(
            R"json({"name":"%1","ipAddress":"192.168.1.10","status":"Offline","role":"%2","passwordHash":"h","passwordSalt":"s","updatedAt":"%3"})json")
            .arg(name, role, updatedAt));
        entry.setLamportClock(1);
        entry.setEpoch(1);
        entry.setOriginMachineId(QStringLiteral("temp-server"));
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


    void applyBatchReplaysSupportedDomainRows()
    {
        freshDatabase();

        models::SyncLogEntry message = makeEntry(QStringLiteral("uuid-message"), 7, 20);

        models::SyncLogEntry group;
        group.setEntryUuid(QStringLiteral("uuid-group"));
        group.setTableName(QStringLiteral("Groups"));
        group.setRecordUuid(QStringLiteral("group-uuid-42"));
        group.setOperation(models::SyncOperation::Insert);
        // ownerUuid/conversationUuid/memberUuids : applyGroupEntry resout le
        // proprietaire et les membres par uuid, jamais par id local
        // (cf. migration 011). La conversation est creee a la volee par
        // ensureConversationByUuid si conv-uuid-group n'existe pas encore.
        group.setPayloadJson(QStringLiteral(
            R"json({"name":"Secours","ownerUuid":"user-uuid-1","conversationUuid":"conv-uuid-group","memberUuids":["user-uuid-1"]})json"));
        group.setLamportClock(21);
        group.setEpoch(7);
        group.setOriginMachineId(QStringLiteral("temp-server"));
        group.setUpdatedAt(QDateTime::currentDateTimeUtc());

        QCOMPARE(m_repository->applyBatch({message, group}), 2);

        // Les ids locaux (AUTOINCREMENT) n'ont aucune raison de coincider
        // avec ceux de la machine d'origine : on retrouve les lignes par
        // leur uuid stable (entry.recordUuid()), comme le fait le code de
        // reconciliation lui-meme.
        QSqlQuery messageQuery(m_dbManager->database());
        QVERIFY(messageQuery.exec(QStringLiteral("SELECT content FROM Messages WHERE uuid = '1020'")));
        QVERIFY(messageQuery.next());
        QCOMPARE(messageQuery.value(0).toString(), QStringLiteral("hello"));

        QSqlQuery groupQuery(m_dbManager->database());
        QVERIFY(groupQuery.exec(QStringLiteral(
            "SELECT g.name, c.uuid FROM Groups g "
            "JOIN Conversations c ON c.id = g.conversation_id "
            "WHERE g.uuid = 'group-uuid-42'")));
        QVERIFY(groupQuery.next());
        QCOMPARE(groupQuery.value(0).toString(), QStringLiteral("Secours"));
        QCOMPARE(groupQuery.value(1).toString(), QStringLiteral("conv-uuid-group"));

        QSqlQuery memberQuery(m_dbManager->database());
        QVERIFY(memberQuery.exec(QStringLiteral(
            "SELECT 1 FROM GroupMembers gm "
            "JOIN Groups g ON g.id = gm.group_id "
            "WHERE g.uuid = 'group-uuid-42' AND gm.user_id = 1")));
        QVERIFY(memberQuery.next());
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

    void applyUserEntryInsertsNewAccount()
    {
        freshDatabase();

        const auto entry = makeUserEntry(QStringLiteral("uuid-user-insert"),
                                          QStringLiteral("record-uuid-1"),
                                          models::SyncOperation::Insert,
                                          QStringLiteral("nouvel-utilisateur"),
                                          QStringLiteral("2026-01-01T00:00:00Z"));

        QCOMPARE(m_repository->applyBatch({entry}), 1);

        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral("SELECT name FROM Users WHERE uuid = 'record-uuid-1'")));
        QVERIFY(query.next());
        QCOMPARE(query.value(0).toString(), QStringLiteral("nouvel-utilisateur"));
    }

    void applyUserEntryInsertIsIdempotent()
    {
        freshDatabase();

        const auto entry = makeUserEntry(QStringLiteral("uuid-user-insert2"),
                                          QStringLiteral("record-uuid-2"),
                                          models::SyncOperation::Insert,
                                          QStringLiteral("bob"),
                                          QStringLiteral("2026-01-01T00:00:00Z"));

        QCOMPARE(m_repository->applyBatch({entry}), 1);

        // Rejeu du meme lot (sync_batch retransmis) : SyncLog l'ignore deja
        // via entry_uuid, mais applyUserEntry lui-meme doit aussi rester
        // idempotent (uuid deja connu) si jamais rappele directement.
        QSqlQuery countBefore(m_dbManager->database());
        QVERIFY(countBefore.exec(QStringLiteral("SELECT COUNT(*) FROM Users WHERE uuid = 'record-uuid-2'")));
        QVERIFY(countBefore.next());
        QCOMPARE(countBefore.value(0).toInt(), 1);
    }

    void applyUserEntryRenamesOnNameCollision()
    {
        freshDatabase();

        // "phase4-user" existe deja (seed de freshDatabase).
        const auto entry = makeUserEntry(QStringLiteral("uuid-user-collision"),
                                          QStringLiteral("record-uuid-3"),
                                          models::SyncOperation::Insert,
                                          QStringLiteral("phase4-user"),
                                          QStringLiteral("2026-01-01T00:00:00Z"));

        QCOMPARE(m_repository->applyBatch({entry}), 1);

        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral("SELECT name FROM Users WHERE uuid = 'record-uuid-3'")));
        QVERIFY(query.next());
        QVERIFY(query.value(0).toString().startsWith(QStringLiteral("phase4-user*conflict*")));

        QSqlQuery logQuery(m_dbManager->database());
        QVERIFY(logQuery.exec(QStringLiteral(
            "SELECT COUNT(*) FROM ServerElectionLog WHERE event = 'USER_NAME_CONFLICT'")));
        QVERIFY(logQuery.next());
        QCOMPARE(logQuery.value(0).toInt(), 1);
    }

    void applyUserEntryUpdateWinsWhenNewer()
    {
        freshDatabase();

        const auto insertEntry = makeUserEntry(QStringLiteral("uuid-user-u1"),
                                                QStringLiteral("record-uuid-4"),
                                                models::SyncOperation::Insert,
                                                QStringLiteral("carol"),
                                                QStringLiteral("2026-01-01T00:00:00Z"),
                                                QStringLiteral("User"));
        QCOMPARE(m_repository->applyBatch({insertEntry}), 1);

        const auto updateEntry = makeUserEntry(QStringLiteral("uuid-user-u2"),
                                                QStringLiteral("record-uuid-4"),
                                                models::SyncOperation::Update,
                                                QStringLiteral("carol"),
                                                QStringLiteral("2026-01-02T00:00:00Z"),
                                                QStringLiteral("Admin"));
        QCOMPARE(m_repository->applyBatch({updateEntry}), 1);

        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral("SELECT role FROM Users WHERE uuid = 'record-uuid-4'")));
        QVERIFY(query.next());
        // Le stockage canonique est en minuscules (cf. models::userRoleToString) ;
        // on compare via l'enum plutot que la casse brute du payload, comme le
        // fait test_syncserviceintegration.cpp.
        const auto storedRole = models::stringToUserRole(query.value(0).toString());
        QVERIFY(storedRole.has_value());
        QCOMPARE(*storedRole, models::UserRole::Admin);
    }

    // Lot 1 securite : un role absent ne retrograde jamais un compte.
    void applyUserEntryUpdateWithoutRoleKeepsExistingRole()
    {
        freshDatabase();
        QCOMPARE(m_repository->applyBatch({makeUserEntry(QStringLiteral("e-r1"), QStringLiteral("rec-admin-a"),
            models::SyncOperation::Insert, QStringLiteral("dana"), QStringLiteral("2026-01-01T00:00:00Z"), QStringLiteral("Admin"))}), 1);
        QCOMPARE(m_repository->applyBatch({makeUserEntry(QStringLiteral("e-r2"), QStringLiteral("rec-admin-b"),
            models::SyncOperation::Insert, QStringLiteral("eric"), QStringLiteral("2026-01-01T00:00:00Z"), QStringLiteral("Admin"))}), 1);
        QCOMPARE(m_repository->applyBatch({makeUserEntry(QStringLiteral("e-r3"), QStringLiteral("rec-admin-a"),
            models::SyncOperation::Update, QStringLiteral("dana"), QStringLiteral("2026-01-02T00:00:00Z"), QString())}), 1);

        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral("SELECT role FROM Users WHERE uuid = 'rec-admin-a'")));
        QVERIFY(query.next());
        QCOMPARE(models::stringToUserRole(query.value(0).toString()).value_or(models::UserRole::User), models::UserRole::Admin);
    }

    // Lot 1 securite : une date future ne gagne pas toutes les reconciliations a venir.
    void applyUserEntryFutureTimestampIsClampedToNow()
    {
        freshDatabase();
        QCOMPARE(m_repository->applyBatch({makeUserEntry(QStringLiteral("e-f1"), QStringLiteral("rec-future"),
            models::SyncOperation::Insert, QStringLiteral("fanny"), QStringLiteral("2026-01-01T00:00:00Z"))}), 1);
        QCOMPARE(m_repository->applyBatch({makeUserEntry(QStringLiteral("e-f2"), QStringLiteral("rec-future"),
            models::SyncOperation::Update, QStringLiteral("fanny"), QStringLiteral("2099-12-31T00:00:00Z"))}), 1);

        database::UserRepository users(m_dbManager->database());
        const auto stored = users.findByUuid(QStringLiteral("rec-future"));
        QVERIFY(stored.has_value());
        QVERIFY2(stored->updatedAt() <= QDateTime::currentDateTimeUtc().addSecs(300),
                 qPrintable(stored->updatedAt().toString(Qt::ISODate)));
    }

    // Lot 1 securite : le reseau ne peut pas laisser le poste sans administrateur.
    void applyUserEntryLastAdminIsNeitherDeletedNorDemoted()
    {
        freshDatabase();
        QCOMPARE(m_repository->applyBatch({makeUserEntry(QStringLiteral("e-l1"), QStringLiteral("rec-last-admin"),
            models::SyncOperation::Insert, QStringLiteral("gael"), QStringLiteral("2026-01-01T00:00:00Z"), QStringLiteral("Admin"))}), 1);

        m_repository->applyBatch({makeUserEntry(QStringLiteral("e-l2"), QStringLiteral("rec-last-admin"),
            models::SyncOperation::Update, QStringLiteral("gael"), QStringLiteral("2026-01-02T00:00:00Z"), QStringLiteral("User"))});
        m_repository->applyBatch({makeUserEntry(QStringLiteral("e-l3"), QStringLiteral("rec-last-admin"),
            models::SyncOperation::Delete, QStringLiteral("gael"), QStringLiteral("2026-01-03T00:00:00Z"))});

        database::UserRepository users(m_dbManager->database());
        const auto stored = users.findByUuid(QStringLiteral("rec-last-admin"));
        QVERIFY2(stored.has_value(), "le dernier administrateur ne doit pas etre supprime");
        QVERIFY2(stored->isAdmin(), "le dernier administrateur ne doit pas etre retrograde");
    }

    void applyUserEntryUpdateLosesWhenOlder()
    {
        freshDatabase();

        const auto insertEntry = makeUserEntry(QStringLiteral("uuid-user-u3"),
                                                QStringLiteral("record-uuid-5"),
                                                models::SyncOperation::Insert,
                                                QStringLiteral("dave"),
                                                QStringLiteral("2026-01-05T00:00:00Z"),
                                                QStringLiteral("User"));
        QCOMPARE(m_repository->applyBatch({insertEntry}), 1);

        // updated_at plus ancien que l'existant (modif locale posterieure a la
        // panne, deja plus recente) : LWW garde la version locale.
        const auto staleUpdate = makeUserEntry(QStringLiteral("uuid-user-u4"),
                                                QStringLiteral("record-uuid-5"),
                                                models::SyncOperation::Update,
                                                QStringLiteral("dave"),
                                                QStringLiteral("2026-01-01T00:00:00Z"),
                                                QStringLiteral("Admin"));
        QCOMPARE(m_repository->applyBatch({staleUpdate}), 1);

        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral("SELECT role FROM Users WHERE uuid = 'record-uuid-5'")));
        QVERIFY(query.next());
        const auto storedRole = models::stringToUserRole(query.value(0).toString());
        QVERIFY(storedRole.has_value());
        QCOMPARE(*storedRole, models::UserRole::User);
    }

    void applyUserEntryUpdateBeforeInsertFallsBackToInsert()
    {
        freshDatabase();

        // Batch partiel : l'UPDATE arrive sans INSERT prealable connu localement.
        const auto updateOnly = makeUserEntry(QStringLiteral("uuid-user-u5"),
                                               QStringLiteral("record-uuid-6"),
                                               models::SyncOperation::Update,
                                               QStringLiteral("erin"),
                                               QStringLiteral("2026-01-01T00:00:00Z"));
        QCOMPARE(m_repository->applyBatch({updateOnly}), 1);

        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral("SELECT name FROM Users WHERE uuid = 'record-uuid-6'")));
        QVERIFY(query.next());
        QCOMPARE(query.value(0).toString(), QStringLiteral("erin"));
    }

    void applyUserEntryDeleteRemovesAccount()
    {
        freshDatabase();

        const auto insertEntry = makeUserEntry(QStringLiteral("uuid-user-d1"),
                                                QStringLiteral("record-uuid-7"),
                                                models::SyncOperation::Insert,
                                                QStringLiteral("frank"),
                                                QStringLiteral("2026-01-01T00:00:00Z"));
        QCOMPARE(m_repository->applyBatch({insertEntry}), 1);

        models::SyncLogEntry deleteEntry;
        deleteEntry.setEntryUuid(QStringLiteral("uuid-user-d2"));
        deleteEntry.setTableName(QStringLiteral("Users"));
        deleteEntry.setRecordUuid(QStringLiteral("record-uuid-7"));
        deleteEntry.setOperation(models::SyncOperation::Delete);
        deleteEntry.setLamportClock(2);
        deleteEntry.setEpoch(1);
        deleteEntry.setOriginMachineId(QStringLiteral("temp-server"));
        deleteEntry.setUpdatedAt(QDateTime::currentDateTimeUtc());
        QCOMPARE(m_repository->applyBatch({deleteEntry}), 1);

        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral("SELECT COUNT(*) FROM Users WHERE uuid = 'record-uuid-7'")));
        QVERIFY(query.next());
        QCOMPARE(query.value(0).toInt(), 0);
    }
};

QTEST_GUILESS_MAIN(TestSyncLogRepository)
#include "test_synclogrepository.moc"