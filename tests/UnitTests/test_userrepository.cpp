#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "database/DatabaseManager.h"
#include "database/Repositories/UserRepository.h"

class TestUserRepository : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_tempDir;
    database::DatabaseManager *m_dbManager = nullptr;

    models::User makeUser(const QString &name) const
    {
        models::User user;
        user.setName(name);
        user.setIpAddress(QStringLiteral("192.168.1.42"));
        user.setStatus(models::UserStatus::Offline);
        user.setIsAdmin(false);
        user.setPasswordHash(QStringLiteral("hash"));
        user.setPasswordSalt(QStringLiteral("salt"));
        return user;
    }

private slots:
    void init()
    {
        QVERIFY(m_tempDir.isValid());
        const QString dbPath = m_tempDir.filePath(
            QStringLiteral("test_%1.sqlite").arg(QRandomGenerator::global()->generate()));
        m_dbManager = new database::DatabaseManager(
            QStringLiteral("test_userrepo_connection_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(m_dbManager->open(dbPath));
    }

    void cleanup()
    {
        delete m_dbManager;
        m_dbManager = nullptr;
    }

    // ---- Create ----

    void testCreateReturnsGeneratedId()
    {
        database::UserRepository repo(m_dbManager->database());

        const int id = repo.create(makeUser(QStringLiteral("alice")));
        QVERIFY(id >= 0);
    }

    void testCreateDuplicateNameFails()
    {
        database::UserRepository repo(m_dbManager->database());

        QVERIFY(repo.create(makeUser(QStringLiteral("bob"))) >= 0);
        const int duplicateId = repo.create(makeUser(QStringLiteral("bob")));

        QCOMPARE(duplicateId, -1);
        QVERIFY(!repo.lastError().isEmpty());
    }

    // ---- Read ----

    void testReadReturnsPersistedFields()
    {
        database::UserRepository repo(m_dbManager->database());
        const int id = repo.create(makeUser(QStringLiteral("carol")));
        QVERIFY(id >= 0);

        const auto found = repo.read(id);
        QVERIFY(found.has_value());
        QCOMPARE(found->id(), id);
        QCOMPARE(found->name(), QStringLiteral("carol"));
        QCOMPARE(found->ipAddress(), QStringLiteral("192.168.1.42"));
        QCOMPARE(found->status(), models::UserStatus::Offline);
        QVERIFY(!found->isAdmin());
        QCOMPARE(found->passwordHash(), QStringLiteral("hash"));
        QCOMPARE(found->passwordSalt(), QStringLiteral("salt"));
    }

    void testReadUnknownIdReturnsNullopt()
    {
        database::UserRepository repo(m_dbManager->database());
        QVERIFY(!repo.read(999999).has_value());
    }

    void testFindByName()
    {
        database::UserRepository repo(m_dbManager->database());
        const int id = repo.create(makeUser(QStringLiteral("dave")));
        QVERIFY(id >= 0);

        const auto found = repo.findByName(QStringLiteral("dave"));
        QVERIFY(found.has_value());
        QCOMPARE(found->id(), id);

        QVERIFY(repo.existsByName(QStringLiteral("dave")));
        QVERIFY(!repo.existsByName(QStringLiteral("nobody")));
    }

    void testFindAllReturnsEveryUser()
    {
        database::UserRepository repo(m_dbManager->database());
        QVERIFY(repo.create(makeUser(QStringLiteral("erin"))) >= 0);
        QVERIFY(repo.create(makeUser(QStringLiteral("frank"))) >= 0);

        const auto all = repo.findAll();
        QCOMPARE(all.size(), static_cast<size_t>(2));
    }

    // ---- Update ----

    void testUpdateModifiesFields()
    {
        database::UserRepository repo(m_dbManager->database());
        const int id = repo.create(makeUser(QStringLiteral("gina")));
        QVERIFY(id >= 0);

        auto user = repo.read(id);
        QVERIFY(user.has_value());
        user->setIpAddress(QStringLiteral("10.0.0.5"));
        user->setIsAdmin(true);
        user->setStatus(models::UserStatus::Online);

        QVERIFY(repo.update(*user));

        const auto reloaded = repo.read(id);
        QVERIFY(reloaded.has_value());
        QCOMPARE(reloaded->ipAddress(), QStringLiteral("10.0.0.5"));
        QVERIFY(reloaded->isAdmin());
        QCOMPARE(reloaded->status(), models::UserStatus::Online);
    }

    void testUpdateUnknownIdReturnsFalse()
    {
        database::UserRepository repo(m_dbManager->database());
        models::User ghost = makeUser(QStringLiteral("ghost"));
        ghost.setId(123456);

        QVERIFY(!repo.update(ghost));
    }

    void testUpdateStatusOnly()
    {
        database::UserRepository repo(m_dbManager->database());
        const int id = repo.create(makeUser(QStringLiteral("henry")));
        QVERIFY(id >= 0);

        QVERIFY(repo.updateStatus(id, models::UserStatus::Away));

        const auto reloaded = repo.read(id);
        QVERIFY(reloaded.has_value());
        QCOMPARE(reloaded->status(), models::UserStatus::Away);
    }

    // ---- Delete ----

    void testRemoveDeletesUser()
    {
        database::UserRepository repo(m_dbManager->database());
        const int id = repo.create(makeUser(QStringLiteral("ivan")));
        QVERIFY(id >= 0);

        QVERIFY(repo.remove(id));
        QVERIFY(!repo.read(id).has_value());
    }

    void testRemoveUnknownIdReturnsFalse()
    {
        database::UserRepository repo(m_dbManager->database());
        QVERIFY(!repo.remove(999999));
    }
};

QTEST_MAIN(TestUserRepository)
#include "test_userrepository.moc"
