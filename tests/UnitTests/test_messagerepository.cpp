#include <QtTest>
#include <QTemporaryDir>
#include "MessageRepository.h"
#include "DatabaseManager.h"

using database::MessageRepository;

class TestMessageRepository : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<database::DatabaseManager> m_dbManager;
    std::unique_ptr<MessageRepository> m_repository;

    void freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        Q_ASSERT(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-messagetrepository-%1").arg(QRandomGenerator::global()->generate()));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        Q_ASSERT(opened);

        // Creer la table Messages
        QSqlDatabase db = m_dbManager->database();
        QSqlQuery query(db);
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

        m_repository = std::make_unique<MessageRepository>(m_dbManager.get());
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

        models::Message message(0, 1, 100, QStringLiteral("Hello World"));
        message.setTimestamp(QDateTime::currentDateTime());

        const auto inserted = m_repository->insert(message);
        QVERIFY(inserted.has_value());
        QVERIFY(inserted->id() > 0);
        QCOMPARE(inserted->conversationId(), 1);
        QCOMPARE(inserted->senderId(), 100);
        QCOMPARE(inserted->content(), QStringLiteral("Hello World"));
    }

    void insert_survivesApostropheInContent()
    {
        // Regression : l'ancienne implementation construisait le SQL par
        // concatenation de chaines ('%3'), ce qui cassait des qu'une
        // apostrophe apparaissait dans le contenu.
        freshDatabase();

        models::Message message(0, 1, 100, QStringLiteral("C'est l'ami d'Alice"));
        message.setTimestamp(QDateTime::currentDateTime());

        const auto inserted = m_repository->insert(message);
        QVERIFY(inserted.has_value());
        QCOMPARE(inserted->content(), QStringLiteral("C'est l'ami d'Alice"));

        const auto messages = m_repository->getMessages(1);
        QCOMPARE(messages.size(), 1);
        QCOMPARE(messages[0].content(), QStringLiteral("C'est l'ami d'Alice"));
    }

    void getMessages_returnsMessages()
    {
        freshDatabase();

        const qint64 conversationId = 1;
        const qint64 senderId = 100;

        // Inserer plusieurs messages
        for (int i = 0; i < 5; ++i) {
            models::Message msg(0, conversationId, senderId, QStringLiteral("Message %1").arg(i));
            msg.setTimestamp(QDateTime::currentDateTime());
            m_repository->insert(msg);
        }

        const auto messages = m_repository->getMessages(conversationId);
        QCOMPARE(messages.size(), 5);
        QCOMPARE(messages[0].content(), QStringLiteral("Message 0"));
        QCOMPARE(messages[4].content(), QStringLiteral("Message 4"));
    }

    void getMessages_withPagination()
    {
        freshDatabase();

        const qint64 conversationId = 1;
        const qint64 senderId = 100;

        // Inserer 10 messages
        for (int i = 0; i < 10; ++i) {
            models::Message msg(0, conversationId, senderId, QStringLiteral("Message %1").arg(i));
            msg.setTimestamp(QDateTime::currentDateTime());
            m_repository->insert(msg);
        }

        // Recuperer les 5 premiers
        const auto firstPage = m_repository->getMessages(conversationId, 5, 0);
        QCOMPARE(firstPage.size(), 5);
        QCOMPARE(firstPage[0].content(), QStringLiteral("Message 0"));

        // Recuperer les 5 suivants
        const auto secondPage = m_repository->getMessages(conversationId, 5, 5);
        QCOMPARE(secondPage.size(), 5);
        QCOMPARE(secondPage[0].content(), QStringLiteral("Message 5"));
    }

    void getMessages_withLimit()
    {
        freshDatabase();

        const qint64 conversationId = 1;
        const qint64 senderId = 100;

        // Inserer 10 messages
        for (int i = 0; i < 10; ++i) {
            models::Message msg(0, conversationId, senderId, QStringLiteral("Message %1").arg(i));
            msg.setTimestamp(QDateTime::currentDateTime());
            m_repository->insert(msg);
        }

        // Recuperer seulement 3 messages
        const auto messages = m_repository->getMessages(conversationId, 3);
        QCOMPARE(messages.size(), 3);
    }

    void getMessageCount_returnsCorrectCount()
    {
        freshDatabase();

        const qint64 conversationId = 1;
        const qint64 senderId = 100;

        QCOMPARE(m_repository->getMessageCount(conversationId), 0);

        // Inserer 7 messages
        for (int i = 0; i < 7; ++i) {
            models::Message msg(0, conversationId, senderId, QStringLiteral("Message %1").arg(i));
            msg.setTimestamp(QDateTime::currentDateTime());
            m_repository->insert(msg);
        }

        QCOMPARE(m_repository->getMessageCount(conversationId), 7);
    }

    void markAsRead_succeeds()
    {
        freshDatabase();

        models::Message message(0, 1, 100, QStringLiteral("Hello"));
        message.setTimestamp(QDateTime::currentDateTime());
        message.setRead(false);

        const auto inserted = m_repository->insert(message);
        QVERIFY(inserted.has_value());
        QVERIFY(!inserted->isRead());

        const bool marked = m_repository->markAsRead(inserted->id());
        QVERIFY(marked);

        const auto messages = m_repository->getMessages(1);
        QCOMPARE(messages.size(), 1);
        QVERIFY(messages[0].isRead());
    }

    void markConversationAsRead_succeeds()
    {
        freshDatabase();

        const qint64 conversationId = 1;
        const qint64 senderId = 100;
        const qint64 otherSenderId = 200;

        // Inserer des messages de l'utilisateur
        for (int i = 0; i < 3; ++i) {
            models::Message msg(0, conversationId, senderId, QStringLiteral("My message %1").arg(i));
            msg.setTimestamp(QDateTime::currentDateTime());
            msg.setRead(false);
            m_repository->insert(msg);
        }

        // Inserer des messages d'autres utilisateurs
        for (int i = 0; i < 2; ++i) {
            models::Message msg(0, conversationId, otherSenderId, QStringLiteral("Other message %1").arg(i));
            msg.setTimestamp(QDateTime::currentDateTime());
            msg.setRead(false);
            m_repository->insert(msg);
        }

        const bool marked = m_repository->markConversationAsRead(conversationId, senderId);
        QVERIFY(marked);

        const auto messages = m_repository->getMessages(conversationId);
        QCOMPARE(messages.size(), 5);

        // Les messages de l'utilisateur ne sont pas marques comme lus
        int myMessagesRead = 0;
        for (const auto &msg : messages) {
            if (msg.senderId() == senderId && msg.isRead()) {
                myMessagesRead++;
            }
        }
        QCOMPARE(myMessagesRead, 0);

        // Les messages des autres sont marques comme lus
        int otherMessagesRead = 0;
        for (const auto &msg : messages) {
            if (msg.senderId() == otherSenderId && msg.isRead()) {
                otherMessagesRead++;
            }
        }
        QCOMPARE(otherMessagesRead, 2);
    }
};

QTEST_MAIN(TestMessageRepository)
#include "test_messagerepository.moc"
