#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QJsonDocument>
#include <QJsonObject>
#include "MessagingManager.h"
#include "DatabaseManager.h"
#include "UserManager.h"

using core::MessagingManager;
using core::MessagingManagerError;

class TestMessagingManager : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<database::DatabaseManager> m_dbManager;
    std::unique_ptr<core::UserManager> m_userManager;
    std::unique_ptr<MessagingManager> m_messagingManager;

    void freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        Q_ASSERT(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-messagingmanager-%1").arg(QRandomGenerator::global()->generate()));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        Q_ASSERT(opened);

        // Creer les tables de base pour les tests
        QSqlDatabase db = m_dbManager->database();
        QSqlQuery query(db);
        QVERIFY(query.exec(QStringLiteral(
            "CREATE TABLE IF NOT EXISTS Conversations ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "type TEXT NOT NULL, "
            "name TEXT, "
            "participant1_id INTEGER, "
            "participant2_id INTEGER)"
        )));
        QVERIFY(query.exec(QStringLiteral("DROP TABLE IF EXISTS Messages")));
        QVERIFY(query.exec(QStringLiteral(
            "CREATE TABLE Messages ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "conversationId INTEGER NOT NULL, "
            "senderId INTEGER NOT NULL, "
            "content TEXT NOT NULL, "
            "timestamp TEXT, "
            "is_read INTEGER DEFAULT 0)"
        )));

        // Creer deux utilisateurs de test
        m_userManager = std::make_unique<core::UserManager>(m_dbManager.get());
        const auto user1 = m_userManager->createUser(QStringLiteral("alice"), QStringLiteral("password1"));
        const auto user2 = m_userManager->createUser(QStringLiteral("bob"), QStringLiteral("password2"));
        Q_ASSERT(user1.has_value());
        Q_ASSERT(user2.has_value());

        m_messagingManager = std::make_unique<MessagingManager>(m_dbManager.get());
    }

private slots:
    void cleanup()
    {
        if (m_dbManager) {
            m_dbManager->close();
        }
        m_messagingManager.reset();
        m_userManager.reset();
        m_dbManager.reset();
        m_dir.reset();
    }

    void initTestCase()
    {
        // Initialisation Qt
    }

    void getOrCreateConversation_createsNewConversation()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());
        QVERIFY(conv->id() > 0);
        QCOMPARE(conv->type(), models::ConversationType::Individual);
        QCOMPARE(conv->participant1Id(), user1Id);
        QCOMPARE(conv->participant2Id(), user2Id);
    }

    void getOrCreateConversation_reusesExistingConversation()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv1 = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv1.has_value());

        const auto conv2 = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv2.has_value());

        QCOMPARE(conv1->id(), conv2->id());
    }

    void getOrCreateConversation_rejectsSameUser()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user1Id);
        QVERIFY(!conv.has_value());
        QCOMPARE(m_messagingManager->lastError(), MessagingManagerError::InvalidUser);
    }

    void sendMessage_succeeds()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        QSignalSpy messageSentSpy(m_messagingManager.get(), &MessagingManager::messageSent);

        const auto msg = m_messagingManager->sendMessage(conv->id(), user1Id, QStringLiteral("Hello Bob"));
        QVERIFY(msg.has_value());
        QVERIFY(msg->id() > 0);
        QCOMPARE(msg->conversationId(), conv->id());
        QCOMPARE(msg->senderId(), user1Id);
        QCOMPARE(msg->content(), QStringLiteral("Hello Bob"));

        QCOMPARE(messageSentSpy.count(), 1);
    }

    void sendMessage_rejectsEmptyContent()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        const auto msg = m_messagingManager->sendMessage(conv->id(), user1Id, QStringLiteral(""));
        QVERIFY(!msg.has_value());
        QCOMPARE(m_messagingManager->lastError(), MessagingManagerError::InvalidContent);
    }

    void sendMessage_toGroupConversation_succeeds()
    {
        // sendMessage()/getMessages() ne discriminent que par conversationId :
        // une conversation de type 'group' doit donc fonctionner exactement
        // comme une conversation individuelle, sans aucun changement de code.
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        QSqlQuery query(m_dbManager->database());
        query.prepare(QStringLiteral(
            "INSERT INTO Conversations (type, name) VALUES ('group', 'Groupe Test')"));
        QVERIFY(query.exec());
        const qint64 groupConversationId = query.lastInsertId().toLongLong();

        const auto msg = m_messagingManager->sendMessage(groupConversationId, user1Id, QStringLiteral("Salut a tous"));
        QVERIFY(msg.has_value());
        QCOMPARE(msg->conversationId(), groupConversationId);

        m_messagingManager->sendMessage(groupConversationId, user2Id, QStringLiteral("Salut !"));

        const auto messages = m_messagingManager->getMessages(groupConversationId);
        QCOMPARE(messages.size(), 2);
    }

    void getMessages_returnsMessages()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        m_messagingManager->sendMessage(conv->id(), user1Id, QStringLiteral("Message 1"));
        m_messagingManager->sendMessage(conv->id(), user2Id, QStringLiteral("Message 2"));
        m_messagingManager->sendMessage(conv->id(), user1Id, QStringLiteral("Message 3"));

        const auto messages = m_messagingManager->getMessages(conv->id());
        QCOMPARE(messages.size(), 3);
        QCOMPARE(messages[0].content(), QStringLiteral("Message 1"));
        QCOMPARE(messages[1].content(), QStringLiteral("Message 2"));
        QCOMPARE(messages[2].content(), QStringLiteral("Message 3"));
    }

    void getUserConversations_returnsUserConversations()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        const auto user1Convs = m_messagingManager->getUserConversations(user1Id);
        QCOMPARE(user1Convs.size(), 1);
        QCOMPARE(user1Convs[0].id(), conv->id());

        const auto user2Convs = m_messagingManager->getUserConversations(user2Id);
        QCOMPARE(user2Convs.size(), 1);
        QCOMPARE(user2Convs[0].id(), conv->id());
    }

    void receiveMessage_persistsAndEmitsSignal()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        QSignalSpy messageReceivedSpy(m_messagingManager.get(), &MessagingManager::messageReceived);

        const QString payload = QStringLiteral(
            "{\"type\":\"message\",\"conversationId\":%1,\"senderId\":%2,\"content\":\"Salut Alice\"}")
            .arg(conv->id()).arg(user2Id);

        const auto msg = m_messagingManager->receiveMessage(payload);
        QVERIFY(msg.has_value());
        QCOMPARE(msg->conversationId(), conv->id());
        QCOMPARE(msg->senderId(), user2Id);
        QCOMPARE(msg->content(), QStringLiteral("Salut Alice"));
        QCOMPARE(messageReceivedSpy.count(), 1);

        const auto messages = m_messagingManager->getMessages(conv->id());
        QCOMPARE(messages.size(), 1);
    }

    void receiveMessage_survivesApostropheInContent()
    {
        // Regression : l'ancienne implementation construisait le SQL par
        // concatenation de chaines ('%3'), ce qui cassait (ou permettait une
        // injection SQL) des qu'une apostrophe apparaissait dans le contenu.
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user1Id = users[0].id();
        const qint64 user2Id = users[1].id();

        const auto conv = m_messagingManager->getOrCreateConversation(user1Id, user2Id);
        QVERIFY(conv.has_value());

        QJsonObject payloadObj;
        payloadObj.insert(QStringLiteral("type"), QStringLiteral("message"));
        payloadObj.insert(QStringLiteral("conversationId"), conv->id());
        payloadObj.insert(QStringLiteral("senderId"), user2Id);
        payloadObj.insert(QStringLiteral("content"), QStringLiteral("C'est l'ami d'Alice"));
        const QString payload = QString::fromUtf8(QJsonDocument(payloadObj).toJson(QJsonDocument::Compact));

        const auto msg = m_messagingManager->receiveMessage(payload);
        QVERIFY(msg.has_value());
        QCOMPARE(msg->content(), QStringLiteral("C'est l'ami d'Alice"));

        const auto messages = m_messagingManager->getMessages(conv->id());
        QCOMPARE(messages.size(), 1);
        QCOMPARE(messages[0].content(), QStringLiteral("C'est l'ami d'Alice"));
    }

    void receiveMessage_forGroupConversation_persists()
    {
        freshDatabase();

        const auto users = m_userManager->allUsers();
        const qint64 user2Id = users[1].id();

        QSqlQuery query(m_dbManager->database());
        query.prepare(QStringLiteral(
            "INSERT INTO Conversations (type, name) VALUES ('group', 'Groupe Test')"));
        QVERIFY(query.exec());
        const qint64 groupConversationId = query.lastInsertId().toLongLong();

        QSignalSpy messageReceivedSpy(m_messagingManager.get(), &MessagingManager::messageReceived);

        const QString payload = QStringLiteral(
            "{\"type\":\"message\",\"conversationId\":%1,\"senderId\":%2,\"content\":\"Salut le groupe\"}")
            .arg(groupConversationId).arg(user2Id);

        const auto msg = m_messagingManager->receiveMessage(payload);
        QVERIFY(msg.has_value());
        QCOMPARE(msg->conversationId(), groupConversationId);
        QCOMPARE(messageReceivedSpy.count(), 1);

        const auto messages = m_messagingManager->getMessages(groupConversationId);
        QCOMPARE(messages.size(), 1);
    }

    void receiveMessage_rejectsInvalidJson()
    {
        freshDatabase();

        const auto msg = m_messagingManager->receiveMessage(QStringLiteral("not json"));
        QVERIFY(!msg.has_value());
    }

    void receiveMessage_rejectsUnknownType()
    {
        freshDatabase();

        const auto msg = m_messagingManager->receiveMessage(
            QStringLiteral("{\"type\":\"ping\"}"));
        QVERIFY(!msg.has_value());
    }
};

QTEST_MAIN(TestMessagingManager)
#include "test_messagingmanager.moc"
