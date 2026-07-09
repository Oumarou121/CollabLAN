#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "core/UserManager.h"
#include "database/DatabaseManager.h"

class TestUserManager : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_tempDir;
    database::DatabaseManager *m_dbManager = nullptr;

private slots:
    void init()
    {
        QVERIFY(m_tempDir.isValid());
        const QString dbPath = m_tempDir.filePath(
            QStringLiteral("test_%1.sqlite").arg(QRandomGenerator::global()->generate()));
        m_dbManager = new database::DatabaseManager(
            QStringLiteral("test_connection_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(m_dbManager->open(dbPath));
    }

    void cleanup()
    {
        delete m_dbManager;
        m_dbManager = nullptr;
    }

    void testCreateUser()
    {
        core::UserManager manager(m_dbManager->database());

        const auto user = manager.createUser(QStringLiteral("alice"), QStringLiteral("hunter2"));
        QVERIFY(user.has_value());
        QCOMPARE(user->name(), QStringLiteral("alice"));
        QVERIFY(user->id() >= 0);
        // Le mot de passe ne doit jamais etre stocke en clair.
        QVERIFY(user->passwordHash() != QStringLiteral("hunter2"));
        QVERIFY(!user->passwordSalt().isEmpty());
    }

    void testCreateUserRejectsDuplicateName()
    {
        core::UserManager manager(m_dbManager->database());

        QVERIFY(manager.createUser(QStringLiteral("bob"), QStringLiteral("password1")).has_value());
        const auto duplicate = manager.createUser(QStringLiteral("bob"), QStringLiteral("otherpass"));

        QVERIFY(!duplicate.has_value());
        QCOMPARE(manager.lastError(), core::UserManagerError::UserAlreadyExists);
    }

    void testCreateUserRejectsEmptyNameOrShortPassword()
    {
        core::UserManager manager(m_dbManager->database());

        QVERIFY(!manager.createUser(QStringLiteral("   "), QStringLiteral("password1")).has_value());
        QCOMPARE(manager.lastError(), core::UserManagerError::InvalidName);

        QVERIFY(!manager.createUser(QStringLiteral("carol"), QStringLiteral("ab")).has_value());
        QCOMPARE(manager.lastError(), core::UserManagerError::InvalidPassword);
    }

    void testAuthenticateSucceedsWithCorrectCredentials()
    {
        core::UserManager manager(m_dbManager->database());
        QVERIFY(manager.createUser(QStringLiteral("dave"), QStringLiteral("correcthorse")).has_value());

        const auto authenticated = manager.authenticate(QStringLiteral("dave"), QStringLiteral("correcthorse"));
        QVERIFY(authenticated.has_value());
        QCOMPARE(authenticated->status(), models::UserStatus::Online);

        const auto current = manager.currentUser();
        QVERIFY(current.has_value());
        QCOMPARE(current->name(), QStringLiteral("dave"));
    }

    void testAuthenticateFailsWithWrongPassword()
    {
        core::UserManager manager(m_dbManager->database());
        QVERIFY(manager.createUser(QStringLiteral("erin"), QStringLiteral("rightpassword")).has_value());

        const auto authenticated = manager.authenticate(QStringLiteral("erin"), QStringLiteral("wrongpassword"));
        QVERIFY(!authenticated.has_value());
        QCOMPARE(manager.lastError(), core::UserManagerError::WrongPassword);
    }

    void testAuthenticateFailsForUnknownUser()
    {
        core::UserManager manager(m_dbManager->database());

        const auto authenticated = manager.authenticate(QStringLiteral("ghost"), QStringLiteral("whatever"));
        QVERIFY(!authenticated.has_value());
        QCOMPARE(manager.lastError(), core::UserManagerError::UserNotFound);
    }

    void testStatusManagement()
    {
        core::UserManager manager(m_dbManager->database());
        const auto user = manager.createUser(QStringLiteral("frank"), QStringLiteral("password1"));
        QVERIFY(user.has_value());

        auto initialStatus = manager.status(user->id());
        QVERIFY(initialStatus.has_value());
        QCOMPARE(*initialStatus, models::UserStatus::Offline);

        QVERIFY(manager.setStatus(user->id(), models::UserStatus::Online));
        auto onlineStatus = manager.status(user->id());
        QVERIFY(onlineStatus.has_value());
        QCOMPARE(*onlineStatus, models::UserStatus::Online);

        manager.authenticate(QStringLiteral("frank"), QStringLiteral("password1"));
        manager.logout();
        auto offlineStatus = manager.status(user->id());
        QVERIFY(offlineStatus.has_value());
        QCOMPARE(*offlineStatus, models::UserStatus::Offline);
        QVERIFY(!manager.currentUser().has_value());
    }
};

QTEST_MAIN(TestUserManager)
#include "test_usermanager.moc"
