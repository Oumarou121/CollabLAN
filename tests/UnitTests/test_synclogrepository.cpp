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

    // Synchronisation incrementale : suite du journal par id local, curseur
    // par (serveur, utilisateur), detection d'un enregistrement deja journalise.
    void entriesAfterIdAndCursor()
    {
        freshDatabase();
        QCOMPARE(m_repository->maxEntryId(), 0);
        // Lamport volontairement decroissant : l'ordre suit l'ecriture locale.
        QVERIFY(m_repository->append(makeEntry(QStringLiteral("e1"), 1, 30)));
        QVERIFY(m_repository->append(makeEntry(QStringLiteral("e2"), 1, 20)));
        QVERIFY(m_repository->append(makeEntry(QStringLiteral("e3"), 1, 10)));
        const qint64 last = m_repository->maxEntryId();
        QVERIFY(last >= 3);

        const auto after = m_repository->entriesAfterId(last - 2);
        QCOMPARE(after.size(), static_cast<size_t>(2));
        QCOMPARE(after[0].entryUuid(), QStringLiteral("e2"));
        QCOMPARE(after[1].entryUuid(), QStringLiteral("e3"));
        QVERIFY(m_repository->entriesAfterId(last).empty());

        QVERIFY(m_repository->hasRecord(QStringLiteral("Messages"), QStringLiteral("1020")));
        QVERIFY(!m_repository->hasRecord(QStringLiteral("Messages"), QStringLiteral("9999")));
        QVERIFY(!m_repository->hasRecord(QStringLiteral("Groups"), QStringLiteral("1020")));

        QCOMPARE(m_repository->syncCursor(QStringLiteral("srv"), QStringLiteral("bob")), 0);
        QVERIFY(m_repository->setSyncCursor(QStringLiteral("srv"), QStringLiteral("bob"), 42));
        QVERIFY(m_repository->setSyncCursor(QStringLiteral("srv"), QStringLiteral("bob"), 43));
        QCOMPARE(m_repository->syncCursor(QStringLiteral("srv"), QStringLiteral("bob")), 43);
        QCOMPARE(m_repository->syncCursor(QStringLiteral("srv"), QStringLiteral("alice")), 0);
        QCOMPARE(m_repository->syncCursor(QStringLiteral("autre"), QStringLiteral("bob")), 0);
    }

    // Une entree differee (dependance absente) est signalee : le client ne fait
    // alors pas avancer son curseur.
    void applyBatchReportsPendingEntries()
    {
        freshDatabase();
        models::SyncLogEntry orphan = makeEntry(QStringLiteral("orphan"), 1, 5);
        orphan.setPayloadJson(QStringLiteral(
            R"json({"senderUuid":"inconnu","conversationUuid":"c","content":"x","timestamp":"2026-01-01T00:00:00Z"})json"));
        QCOMPARE(m_repository->applyBatch({orphan, makeEntry(QStringLiteral("ok"), 1, 6)}), 1);
        QCOMPARE(m_repository->lastBatchPendingCount(), 1);
        QCOMPARE(m_repository->applyBatch({makeEntry(QStringLiteral("ok2"), 1, 7)}), 1);
        QCOMPARE(m_repository->lastBatchPendingCount(), 0);
    }

    // Message de groupe applique avant son groupe : la conversation est creee
    // en groupe, et un ancien typage "individuel" est corrige a l'arrivee du groupe.
    void groupMessageBeforeGroupKeepsGroupType()
    {
        freshDatabase();
        models::SyncLogEntry message = makeEntry(QStringLiteral("gm"), 1, 1);
        message.setPayloadJson(QStringLiteral(
            R"json({"senderUuid":"user-uuid-1","conversationUuid":"conv-groupe","conversationType":"group","conversationName":"Equipe","content":"salut","timestamp":"2026-01-01T00:00:00Z"})json"));
        QCOMPARE(m_repository->applyBatch({message}), 1);
        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral("SELECT type, name FROM Conversations WHERE uuid = 'conv-groupe'")) && query.next());
        QCOMPARE(query.value(0).toString(), QStringLiteral("group"));
        QCOMPARE(query.value(1).toString(), QStringLiteral("Equipe"));

        QVERIFY(query.exec(QStringLiteral(
            "INSERT INTO Conversations (type, name, uuid) VALUES ('individual', 'Conversation', 'conv-ancienne')")));
        QVERIFY(m_repository->ensureConversationByUuid(QStringLiteral("conv-ancienne"), QStringLiteral("group"),
                                                       QStringLiteral("Projet")) > 0);
        QVERIFY(query.exec(QStringLiteral("SELECT type, name FROM Conversations WHERE uuid = 'conv-ancienne'")) && query.next());
        QCOMPARE(query.value(0).toString(), QStringLiteral("group"));
        QCOMPARE(query.value(1).toString(), QStringLiteral("Projet"));
    }

    // Source autre que le serveur officiel : creation acceptee mais jamais en
    // administrateur, ni role ni mot de passe modifies, pas de suppression.
    void restrictUserEntriesFromUntrustedSource()
    {
        freshDatabase();
        const auto insertEntry = makeUserEntry(QStringLiteral("r1"), QStringLiteral("record-r"),
                                                models::SyncOperation::Insert, QStringLiteral("mallory"),
                                                QStringLiteral("2026-01-01T00:00:00Z"), QStringLiteral("Admin"));
        QCOMPARE(m_repository->applyBatch(SyncLogRepository::restrictUserEntries({insertEntry})), 1);
        database::UserRepository users(m_dbManager->database());
        auto created = users.findByUuid(QStringLiteral("record-r"));
        QVERIFY(created.has_value());
        QCOMPARE(created->role(), models::UserRole::User);
        const QString originalHash = created->passwordHash();

        auto update = makeUserEntry(QStringLiteral("r2"), QStringLiteral("record-r"),
                                    models::SyncOperation::Update, QStringLiteral("mallory2"),
                                    QStringLiteral("2026-01-02T00:00:00Z"), QStringLiteral("Admin"));
        update.setPayloadJson(update.payloadJson().replace(QStringLiteral("\"passwordHash\":\"h\""),
                                                           QStringLiteral("\"passwordHash\":\"pirate\"")));
        models::SyncLogEntry deletion = update;
        deletion.setEntryUuid(QStringLiteral("r3"));
        deletion.setOperation(models::SyncOperation::Delete);
        const auto restricted = SyncLogRepository::restrictUserEntries({update, deletion});
        QCOMPARE(restricted.size(), static_cast<size_t>(1)); // suppression retiree
        QCOMPARE(m_repository->applyBatch(restricted), 1);

        const auto after = users.findByUuid(QStringLiteral("record-r"));
        QVERIFY(after.has_value());
        QCOMPARE(after->name(), QStringLiteral("mallory2")); // champ ordinaire : applique
        QCOMPARE(after->role(), models::UserRole::User);
        QCOMPARE(after->passwordHash(), originalHash);

        // Les autres tables passent telles quelles.
        const auto message = makeEntry(QStringLiteral("m"), 1, 1);
        QCOMPARE(SyncLogRepository::restrictUserEntry(message)->payloadJson(), message.payloadJson());
    }

    // Modification puis suppression d'un message par son auteur, appliquees par
    // le journal ; une modification d'un autre que l'auteur est ignoree.
    void applyMessageChangeFromAuthorOnly()
    {
        freshDatabase();
        QCOMPARE(m_repository->applyBatch({makeEntry(QStringLiteral("ins"), 1, 1)}), 1); // message 1001
        models::SyncLogEntry edit = makeEntry(QStringLiteral("upd-pirate"), 1, 2);
        edit.setOperation(models::SyncOperation::Update);
        edit.setPayloadJson(QStringLiteral(
            R"json({"senderUuid":"autre","content":"pirate","editedAt":"2026-01-02T00:00:00Z"})json"));
        edit.setRecordUuid(QStringLiteral("1001"));
        QCOMPARE(m_repository->applyBatch({edit}), 1);
        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral("SELECT content FROM Messages WHERE uuid = '1001'")) && query.next());
        QCOMPARE(query.value(0).toString(), QStringLiteral("hello"));

        edit.setEntryUuid(QStringLiteral("upd"));
        edit.setPayloadJson(QStringLiteral(
            R"json({"senderUuid":"user-uuid-1","content":"corrige","editedAt":"2026-01-02T00:00:00Z"})json"));
        QCOMPARE(m_repository->applyBatch({edit}), 1);
        QVERIFY(query.exec(QStringLiteral("SELECT content, edited_at FROM Messages WHERE uuid = '1001'")) && query.next());
        QCOMPARE(query.value(0).toString(), QStringLiteral("corrige"));
        QVERIFY(!query.value(1).toString().isEmpty());

        models::SyncLogEntry del = edit;
        del.setEntryUuid(QStringLiteral("del"));
        del.setOperation(models::SyncOperation::Delete);
        del.setPayloadJson(QStringLiteral(R"json({"senderUuid":"user-uuid-1","deletedAt":"2026-01-03T00:00:00Z"})json"));
        QCOMPARE(m_repository->applyBatch({del}), 1);
        QVERIFY(query.exec(QStringLiteral("SELECT content, deleted_at FROM Messages WHERE uuid = '1001'")) && query.next());
        QVERIFY(query.value(0).toString().isEmpty());
        QVERIFY(!query.value(1).toString().isEmpty());
    }

    // Accuse applique : enregistre, heures deja connues gardees, signale pour
    // recalcul de l'etat d'envoi.
    void applyReceiptEntryMergesAndReports()
    {
        freshDatabase();
        models::SyncLogEntry receipt;
        receipt.setEntryUuid(QStringLiteral("r1"));
        receipt.setTableName(QStringLiteral("MessageReceipts"));
        receipt.setRecordUuid(QStringLiteral("m1|bob"));
        receipt.setOperation(models::SyncOperation::Update);
        receipt.setPayloadJson(QStringLiteral(
            R"json({"messageUuid":"m1","userUuid":"bob","senderUuid":"alice","deliveredAt":"2026-01-01T10:00:00Z","readAt":""})json"));
        receipt.setEpoch(1);
        receipt.setOriginMachineId(QStringLiteral("srv"));
        QCOMPARE(m_repository->applyBatch({receipt}), 1);
        models::SyncLogEntry read = receipt;
        read.setEntryUuid(QStringLiteral("r2"));
        read.setPayloadJson(QStringLiteral(
            R"json({"messageUuid":"m1","userUuid":"bob","senderUuid":"alice","deliveredAt":"2026-01-01T11:00:00Z","readAt":"2026-01-01T12:00:00Z"})json"));
        QCOMPARE(m_repository->applyBatch({read}), 1);
        QCOMPARE(m_repository->takeTouchedReceiptMessages(), QStringList({QStringLiteral("m1")}));
        QVERIFY(m_repository->takeTouchedReceiptMessages().isEmpty());

        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral(
            "SELECT delivered_at, read_at FROM MessageReceipts WHERE message_uuid = 'm1' AND user_uuid = 'bob'")) && query.next());
        QCOMPARE(query.value(0).toString(), QStringLiteral("2026-01-01T10:00:00Z")); // la premiere heure reste
        QCOMPARE(query.value(1).toString(), QStringLiteral("2026-01-01T12:00:00Z"));
    }

    // Renommage puis suppression d'un groupe appliques par le journal.
    void applyGroupRenameAndDelete()
    {
        freshDatabase();
        models::SyncLogEntry group = makeEntry(QStringLiteral("g-ins"), 1, 1);
        group.setTableName(QStringLiteral("Groups"));
        group.setRecordUuid(QStringLiteral("grp-1"));
        group.setPayloadJson(QStringLiteral(
            R"json({"name":"Equipe","ownerUuid":"user-uuid-1","conversationUuid":"conv-grp","memberUuids":["user-uuid-1"]})json"));
        models::SyncLogEntry message = makeEntry(QStringLiteral("g-msg"), 1, 2);
        message.setPayloadJson(QStringLiteral(
            R"json({"senderUuid":"user-uuid-1","conversationUuid":"conv-grp","conversationType":"group","content":"hello","timestamp":"2026-01-01T00:00:00Z"})json"));
        QCOMPARE(m_repository->applyBatch({group, message}), 2);

        models::SyncLogEntry rename = group;
        rename.setEntryUuid(QStringLiteral("g-upd"));
        rename.setOperation(models::SyncOperation::Update);
        rename.setPayloadJson(QStringLiteral(R"json({"name":"Equipe projet"})json"));
        QCOMPARE(m_repository->applyBatch({rename}), 1);
        QSqlQuery query(m_dbManager->database());
        QVERIFY(query.exec(QStringLiteral("SELECT g.name, c.name FROM Groups g JOIN Conversations c ON c.id = g.conversation_id WHERE g.uuid = 'grp-1'")) && query.next());
        QCOMPARE(query.value(0).toString(), QStringLiteral("Equipe projet"));
        QCOMPARE(query.value(1).toString(), QStringLiteral("Equipe projet"));

        models::SyncLogEntry del = group;
        del.setEntryUuid(QStringLiteral("g-del"));
        del.setOperation(models::SyncOperation::Delete);
        del.setPayloadJson(QStringLiteral("{}"));
        QCOMPARE(m_repository->applyBatch({del}), 1);
        QVERIFY(query.exec(QStringLiteral("SELECT COUNT(*) FROM Groups WHERE uuid = 'grp-1'")) && query.next());
        QCOMPARE(query.value(0).toInt(), 0);
        QVERIFY(query.exec(QStringLiteral("SELECT COUNT(*) FROM Conversations WHERE uuid = 'conv-grp'")) && query.next());
        QCOMPARE(query.value(0).toInt(), 0);
        QVERIFY(query.exec(QStringLiteral("SELECT COUNT(*) FROM Messages WHERE uuid = '1002'")) && query.next());
        QCOMPARE(query.value(0).toInt(), 0);
    }

    // Purge : seul l'etat le plus recent par enregistrement reste ; le texte
    // d'un message supprime disparait du journal ; les messages restent.
    void compactKeepsOnlyLatestState()
    {
        freshDatabase();
        const auto entryFor = [this](const QString &uuid, const QString &table, const QString &record,
                                     const QString &op, const QString &payload) {
            models::SyncLogEntry e = makeEntry(uuid, 1, 1);
            e.setTableName(table);
            e.setRecordUuid(record);
            e.setOperation(op);
            e.setPayloadJson(payload);
            return e;
        };
        const QString r1 = QStringLiteral(R"json({"messageUuid":"m","userUuid":"bob","deliveredAt":"2026-01-01T10:00:00Z"})json");
        const QString r2 = QStringLiteral(R"json({"messageUuid":"m","userUuid":"bob","deliveredAt":"2026-01-01T10:00:00Z","readAt":"2026-01-01T11:00:00Z"})json");
        QVERIFY(m_repository->append(entryFor(QStringLiteral("rc1"), QStringLiteral("MessageReceipts"), QStringLiteral("m|bob"), models::SyncOperation::Update, r1)));
        QVERIFY(m_repository->append(entryFor(QStringLiteral("rc2"), QStringLiteral("MessageReceipts"), QStringLiteral("m|bob"), models::SyncOperation::Update, r2)));
        QVERIFY(m_repository->append(makeUserEntry(QStringLiteral("u-new"), QStringLiteral("acct"), models::SyncOperation::Update,
                                                   QStringLiteral("neuf"), QStringLiteral("2026-03-01T00:00:00Z"))));
        // Ecrite apres mais plus ancienne (fusionnee d'un serveur de secours).
        QVERIFY(m_repository->append(makeUserEntry(QStringLiteral("u-old"), QStringLiteral("acct"), models::SyncOperation::Update,
                                                   QStringLiteral("ancien"), QStringLiteral("2026-02-01T00:00:00Z"))));
        QVERIFY(m_repository->append(entryFor(QStringLiteral("msg"), QStringLiteral("Messages"), QStringLiteral("mx"), models::SyncOperation::Insert,
                                              QStringLiteral(R"json({"senderUuid":"user-uuid-1","content":"secret"})json"))));
        QVERIFY(m_repository->append(entryFor(QStringLiteral("msg-u1"), QStringLiteral("Messages"), QStringLiteral("mx"), models::SyncOperation::Update,
                                              QStringLiteral(R"json({"content":"v2"})json"))));
        QVERIFY(m_repository->append(entryFor(QStringLiteral("msg-d"), QStringLiteral("Messages"), QStringLiteral("mx"), models::SyncOperation::Delete,
                                              QStringLiteral(R"json({"senderUuid":"user-uuid-1"})json"))));
        QVERIFY(m_repository->append(entryFor(QStringLiteral("keep"), QStringLiteral("Messages"), QStringLiteral("my"), models::SyncOperation::Insert,
                                              QStringLiteral(R"json({"content":"garde"})json"))));

        QCOMPARE(m_repository->compact(), 3); // rc1, u-old, msg-u1
        QStringList left;
        for (const auto &e : m_repository->entriesAfterId(0))
            left << e.entryUuid();
        QCOMPARE(left, QStringList({QStringLiteral("rc2"), QStringLiteral("u-new"), QStringLiteral("msg"),
                                    QStringLiteral("msg-d"), QStringLiteral("keep")}));
        const auto insert = m_repository->messageInsertPayload(QStringLiteral("mx"));
        QVERIFY(insert.has_value());
        QVERIFY(insert->value(QStringLiteral("content")).toString().isEmpty());
        QCOMPARE(m_repository->messageInsertPayload(QStringLiteral("my"))->value(QStringLiteral("content")).toString(),
                 QStringLiteral("garde"));
        QCOMPARE(m_repository->compact(), 0); // rien de plus a retirer
    }
};

QTEST_GUILESS_MAIN(TestSyncLogRepository)
#include "test_synclogrepository.moc"