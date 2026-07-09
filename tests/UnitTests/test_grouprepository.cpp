#include <QtTest>
#include <QTemporaryDir>
#include "GroupRepository.h"
#include "DatabaseManager.h"

using database::GroupRepository;

class TestGroupRepository : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<database::DatabaseManager> m_dbManager;
    std::unique_ptr<GroupRepository> m_repository;

    void freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        Q_ASSERT(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-grouprepository-%1").arg(QRandomGenerator::global()->generate()));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        Q_ASSERT(opened);

        // Creer les tables Groups et GroupMembers
        QSqlDatabase db = m_dbManager->database();
        QSqlQuery query(db);
        QVERIFY(query.exec(QStringLiteral("DROP TABLE IF EXISTS Groups")));
        QVERIFY(query.exec(QStringLiteral(
            "CREATE TABLE Groups ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "name TEXT NOT NULL, "
            "owner_id INTEGER NOT NULL)"
        )));
        QVERIFY(query.exec(QStringLiteral("DROP TABLE IF EXISTS GroupMembers")));
        QVERIFY(query.exec(QStringLiteral(
            "CREATE TABLE GroupMembers ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "group_id INTEGER NOT NULL, "
            "user_id INTEGER NOT NULL)"
        )));

        m_repository = std::make_unique<GroupRepository>(m_dbManager.get());
    }

private slots:
    void cleanup()
    {
        if (m_dbManager) {
            m_dbManager->close();
        }
        m_repository.reset();
        m_dbManager.reset();
        m_dir.reset();
    }

    void initTestCase()
    {
        // Initialisation Qt
    }

    void insert_succeeds()
    {
        freshDatabase();

        models::Group group(0, QStringLiteral("Test Group"));
        group.setOwnerId(100);
        group.addMember(100);
        group.addMember(101);
        group.addMember(102);

        const auto inserted = m_repository->insert(group);
        QVERIFY(inserted.has_value());
        QVERIFY(inserted->id() > 0);
        QCOMPARE(inserted->name(), QStringLiteral("Test Group"));
        QCOMPARE(inserted->ownerId(), 100);
        QCOMPARE(inserted->memberIds().size(), 3);
    }

    void getById_returnsGroup()
    {
        freshDatabase();

        models::Group group(0, QStringLiteral("Test Group"));
        group.setOwnerId(100);
        group.addMember(100);
        group.addMember(101);

        const auto inserted = m_repository->insert(group);
        QVERIFY(inserted.has_value());

        const auto retrieved = m_repository->getById(inserted->id());
        QVERIFY(retrieved.has_value());
        QCOMPARE(retrieved->id(), inserted->id());
        QCOMPARE(retrieved->name(), inserted->name());
        QCOMPARE(retrieved->ownerId(), inserted->ownerId());
        QCOMPARE(retrieved->memberIds().size(), 2);
    }

    void update_succeeds()
    {
        freshDatabase();

        models::Group group(0, QStringLiteral("Old Name"));
        group.setOwnerId(100);
        group.addMember(100);

        const auto inserted = m_repository->insert(group);
        QVERIFY(inserted.has_value());

        models::Group updatedGroup(*inserted);
        updatedGroup.setName(QStringLiteral("New Name"));
        updatedGroup.addMember(101);

        const bool updated = m_repository->update(updatedGroup);
        QVERIFY(updated);

        const auto retrieved = m_repository->getById(inserted->id());
        QVERIFY(retrieved.has_value());
        QCOMPARE(retrieved->name(), QStringLiteral("New Name"));
        QCOMPARE(retrieved->memberIds().size(), 2);
    }

    void remove_succeeds()
    {
        freshDatabase();

        models::Group group(0, QStringLiteral("Test Group"));
        group.setOwnerId(100);
        group.addMember(100);

        const auto inserted = m_repository->insert(group);
        QVERIFY(inserted.has_value());

        const bool removed = m_repository->remove(inserted->id());
        QVERIFY(removed);

        const auto retrieved = m_repository->getById(inserted->id());
        QVERIFY(!retrieved.has_value());
    }

    void getByUserId_returnsUserGroups()
    {
        freshDatabase();

        models::Group group1(0, QStringLiteral("Group 1"));
        group1.setOwnerId(100);
        group1.addMember(100);
        group1.addMember(101);

        models::Group group2(0, QStringLiteral("Group 2"));
        group2.setOwnerId(100);
        group2.addMember(100);
        group2.addMember(102);

        m_repository->insert(group1);
        m_repository->insert(group2);

        const auto userGroups = m_repository->getByUserId(100);
        QCOMPARE(userGroups.size(), 2);

        const auto user101Groups = m_repository->getByUserId(101);
        QCOMPARE(user101Groups.size(), 1);
        QCOMPARE(user101Groups[0].name(), QStringLiteral("Group 1"));
    }

    void addMember_succeeds()
    {
        freshDatabase();

        models::Group group(0, QStringLiteral("Test Group"));
        group.setOwnerId(100);
        group.addMember(100);

        const auto inserted = m_repository->insert(group);
        QVERIFY(inserted.has_value());

        const bool added = m_repository->addMember(inserted->id(), 101);
        QVERIFY(added);

        const auto retrieved = m_repository->getById(inserted->id());
        QVERIFY(retrieved.has_value());
        QCOMPARE(retrieved->memberIds().size(), 2);
        QVERIFY(retrieved->memberIds().contains(101));
    }

    void addMember_handlesDuplicate()
    {
        freshDatabase();

        models::Group group(0, QStringLiteral("Test Group"));
        group.setOwnerId(100);
        group.addMember(100);

        const auto inserted = m_repository->insert(group);
        QVERIFY(inserted.has_value());

        // Add same member twice
        const bool added1 = m_repository->addMember(inserted->id(), 101);
        QVERIFY(added1);

        const bool added2 = m_repository->addMember(inserted->id(), 101);
        QVERIFY(added2);  // Should succeed (idempotent)

        const auto retrieved = m_repository->getById(inserted->id());
        QVERIFY(retrieved.has_value());
        QCOMPARE(retrieved->memberIds().size(), 2);  // Still 2 members
    }

    void removeMember_succeeds()
    {
        freshDatabase();

        models::Group group(0, QStringLiteral("Test Group"));
        group.setOwnerId(100);
        group.addMember(100);
        group.addMember(101);

        const auto inserted = m_repository->insert(group);
        QVERIFY(inserted.has_value());

        const bool removed = m_repository->removeMember(inserted->id(), 101);
        QVERIFY(removed);

        const auto retrieved = m_repository->getById(inserted->id());
        QVERIFY(retrieved.has_value());
        QCOMPARE(retrieved->memberIds().size(), 1);
        QVERIFY(!retrieved->memberIds().contains(101));
    }

    void getGroupMembers_returnsMembers()
    {
        freshDatabase();

        models::Group group(0, QStringLiteral("Test Group"));
        group.setOwnerId(100);
        group.addMember(100);
        group.addMember(101);
        group.addMember(102);

        const auto inserted = m_repository->insert(group);
        QVERIFY(inserted.has_value());

        const auto members = m_repository->getGroupMembers(inserted->id());
        QCOMPARE(members.size(), 3);
        QVERIFY(members.contains(100));
        QVERIFY(members.contains(101));
        QVERIFY(members.contains(102));
    }

    void isMember_returnsCorrectValue()
    {
        freshDatabase();

        models::Group group(0, QStringLiteral("Test Group"));
        group.setOwnerId(100);
        group.addMember(100);
        group.addMember(101);

        const auto inserted = m_repository->insert(group);
        QVERIFY(inserted.has_value());

        QVERIFY(m_repository->isMember(inserted->id(), 100));
        QVERIFY(m_repository->isMember(inserted->id(), 101));
        QVERIFY(!m_repository->isMember(inserted->id(), 999));
    }
};

QTEST_MAIN(TestGroupRepository)
#include "test_grouprepository.moc"
