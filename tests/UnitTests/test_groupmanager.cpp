#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include "GroupManager.h"
#include "DatabaseManager.h"
#include "UserManager.h"

using core::GroupManager;
using core::GroupManagerError;

class TestGroupManager : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<database::DatabaseManager> m_dbManager;
    std::unique_ptr<core::UserManager> m_userManager;
    std::unique_ptr<GroupManager> m_groupManager;

    void freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        Q_ASSERT(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-groupmanager-%1").arg(QRandomGenerator::global()->generate()));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        Q_ASSERT(opened);

        // Creer les tables de base pour les tests
        QSqlDatabase db = m_dbManager->database();
        QSqlQuery query(db);
        QVERIFY(query.exec(QStringLiteral("DROP TABLE IF EXISTS Groups")));
        // Schema aligne sur celui produit par les migrations reelles
        // (004_link_groups_to_conversations + 011_add_sync_uuid_columns) :
        // la colonne uuid est requise par GroupRepository::insert(), sans
        // elle query.prepare() echoue silencieusement ("Parameter count
        // mismatch") faute de colonne correspondante.
        QVERIFY(query.exec(QStringLiteral(
            "CREATE TABLE Groups ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "name TEXT NOT NULL, "
            "owner_id INTEGER NOT NULL, "
            "conversation_id INTEGER, "
            "uuid TEXT)"
        )));
        QVERIFY(query.exec(QStringLiteral("DROP TABLE IF EXISTS GroupMembers")));
        QVERIFY(query.exec(QStringLiteral(
            "CREATE TABLE GroupMembers ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "group_id INTEGER NOT NULL, "
            "user_id INTEGER NOT NULL)"
        )));
        // GroupManager::createGroup() cree desormais une Conversation liee
        // (type='group') pour chaque groupe : la table doit exister ici
        // aussi (elle vient normalement de la migration 002).
        QVERIFY(query.exec(QStringLiteral("DROP TABLE IF EXISTS Conversations")));
        // Schema aligne sur celui produit par les migrations reelles
        // (002_add_conversations_table + 011_add_sync_uuid_columns) : la
        // colonne uuid est requise par GroupManager::createGroup() (INSERT
        // INTO Conversations (type, name, uuid) ...), sans elle
        // query.prepare() echoue silencieusement ("Parameter count
        // mismatch") faute de colonne correspondante.
        QVERIFY(query.exec(QStringLiteral(
            "CREATE TABLE Conversations ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "type TEXT NOT NULL DEFAULT 'individual', "
            "name TEXT NOT NULL, "
            "participant1_id INTEGER, "
            "participant2_id INTEGER, "
            "uuid TEXT)"
        )));

        // Creer trois utilisateurs de test
        m_userManager = std::make_unique<core::UserManager>(m_dbManager.get());
        const auto user1 = m_userManager->createUser(QStringLiteral("alice"), QStringLiteral("password1"));
        const auto user2 = m_userManager->createUser(QStringLiteral("bob"), QStringLiteral("password2"));
        const auto user3 = m_userManager->createUser(QStringLiteral("charlie"), QStringLiteral("password3"));
        Q_ASSERT(user1.has_value());
        Q_ASSERT(user2.has_value());
        Q_ASSERT(user3.has_value());

        m_groupManager = std::make_unique<GroupManager>(m_dbManager.get());
    }

private slots:
    void cleanup()
    {
        if (m_dbManager) {
            m_dbManager->close();
        }
        m_groupManager.reset();
        m_userManager.reset();
        m_dbManager.reset();
        m_dir.reset();
    }

    void initTestCase()
    {
        // Initialisation Qt
    }

    void createGroup_succeeds()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 ownerId = users[0].id();
        QVector<qint64> initialMembers = {users[1].id(), users[2].id()};

        QSignalSpy groupCreatedSpy(m_groupManager.get(), &GroupManager::groupCreated);

        const auto group = m_groupManager->createGroup(QStringLiteral("Test Group"), ownerId, initialMembers);
        QVERIFY(group.has_value());
        QVERIFY(group->id() > 0);
        QCOMPARE(group->name(), QStringLiteral("Test Group"));
        QCOMPARE(group->ownerId(), ownerId);
        QCOMPARE(group->memberIds().size(), 3);  // Owner + 2 initial members
        QVERIFY(group->memberIds().contains(ownerId));

        QCOMPARE(groupCreatedSpy.count(), 1);
    }

    void createGroup_rejectsEmptyName()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 ownerId = users[0].id();

        const auto group = m_groupManager->createGroup(QStringLiteral(""), ownerId, {});
        QVERIFY(!group.has_value());
        QCOMPARE(m_groupManager->lastError(), GroupManagerError::InvalidName);
    }

    void addMember_succeeds()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 ownerId = users[0].id();
        const qint64 newMemberId = users[2].id();

        const auto group = m_groupManager->createGroup(QStringLiteral("Test Group"), ownerId, {users[1].id()});
        QVERIFY(group.has_value());

        QSignalSpy memberAddedSpy(m_groupManager.get(), &GroupManager::memberAdded);

        const bool added = m_groupManager->addMember(group->id(), newMemberId, ownerId);
        QVERIFY(added);

        const auto updatedGroup = m_groupManager->getGroup(group->id());
        QVERIFY(updatedGroup.has_value());
        QVERIFY(updatedGroup->memberIds().contains(newMemberId));

        QCOMPARE(memberAddedSpy.count(), 1);
    }

    void addMember_failsWhenNotOwner()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 ownerId = users[0].id();
        const qint64 nonOwnerId = users[1].id();
        const qint64 newMemberId = users[2].id();

        const auto group = m_groupManager->createGroup(QStringLiteral("Test Group"), ownerId, {});
        QVERIFY(group.has_value());

        const bool added = m_groupManager->addMember(group->id(), newMemberId, nonOwnerId);
        QVERIFY(!added);
        QCOMPARE(m_groupManager->lastError(), GroupManagerError::NotOwner);
    }

    void removeMember_succeeds()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 ownerId = users[0].id();
        const qint64 memberId = users[1].id();

        const auto group = m_groupManager->createGroup(QStringLiteral("Test Group"), ownerId, {memberId});
        QVERIFY(group.has_value());

        QSignalSpy memberRemovedSpy(m_groupManager.get(), &GroupManager::memberRemoved);

        const bool removed = m_groupManager->removeMember(group->id(), memberId, ownerId);
        QVERIFY(removed);

        const auto updatedGroup = m_groupManager->getGroup(group->id());
        QVERIFY(updatedGroup.has_value());
        QVERIFY(!updatedGroup->memberIds().contains(memberId));

        QCOMPARE(memberRemovedSpy.count(), 1);
    }

    void removeMember_failsWhenNotOwner()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 ownerId = users[0].id();
        const qint64 nonOwnerId = users[1].id();
        const qint64 memberId = users[2].id();

        const auto group = m_groupManager->createGroup(QStringLiteral("Test Group"), ownerId, {memberId});
        QVERIFY(group.has_value());

        const bool removed = m_groupManager->removeMember(group->id(), memberId, nonOwnerId);
        QVERIFY(!removed);
        QCOMPARE(m_groupManager->lastError(), GroupManagerError::NotOwner);
    }

    void removeMember_failsForOwner()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 ownerId = users[0].id();

        const auto group = m_groupManager->createGroup(QStringLiteral("Test Group"), ownerId, {});
        QVERIFY(group.has_value());

        const bool removed = m_groupManager->removeMember(group->id(), ownerId, ownerId);
        QVERIFY(!removed);
        QCOMPARE(m_groupManager->lastError(), GroupManagerError::InvalidUser);
    }

    void getUserGroups_returnsUserGroups()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        m_groupManager->createGroup(QStringLiteral("Group1"), user1Id, {user2Id});
        m_groupManager->createGroup(QStringLiteral("Group2"), user1Id, {});

        const auto user1Groups = m_groupManager->getUserGroups(user1Id);
        QCOMPARE(user1Groups.size(), 2);

        const auto user2Groups = m_groupManager->getUserGroups(user2Id);
        QCOMPARE(user2Groups.size(), 1);
    }

    void createGroup_createsLinkedConversation()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 ownerId = users[0].id();

        const auto group = m_groupManager->createGroup(QStringLiteral("Test Group"), ownerId, {users[1].id()});
        QVERIFY(group.has_value());
        QVERIFY(group->conversationId() > 0);

        // La conversation existe bien en base, avec le bon type.
        QSqlQuery query(m_dbManager->database());
        query.prepare(QStringLiteral("SELECT type FROM Conversations WHERE id = ?"));
        query.addBindValue(group->conversationId());
        QVERIFY(query.exec());
        QVERIFY(query.next());
        QCOMPARE(query.value(0).toString(), QStringLiteral("group"));

        // getGroup() doit retrouver le meme conversationId.
        const auto reloaded = m_groupManager->getGroup(group->id());
        QVERIFY(reloaded.has_value());
        QCOMPARE(reloaded->conversationId(), group->conversationId());
    }

    void getGroup_returnsGroup()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 ownerId = users[0].id();

        const auto createdGroup = m_groupManager->createGroup(QStringLiteral("Test Group"), ownerId, {users[1].id()});
        QVERIFY(createdGroup.has_value());

        const auto retrievedGroup = m_groupManager->getGroup(createdGroup->id());
        QVERIFY(retrievedGroup.has_value());
        QCOMPARE(retrievedGroup->id(), createdGroup->id());
        QCOMPARE(retrievedGroup->name(), createdGroup->name());
        QCOMPARE(retrievedGroup->ownerId(), createdGroup->ownerId());
    }
};

QTEST_MAIN(TestGroupManager)
#include "test_groupmanager.moc"
