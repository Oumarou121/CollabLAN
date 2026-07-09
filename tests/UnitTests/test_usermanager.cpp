#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include "DatabaseManager.h"
#include "PasswordHasher.h"
#include "User.h"
#include "UserManager.h"
#include "UserRepository.h"

class TestUserManager : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    std::unique_ptr<database::DatabaseManager> m_dbManager;

    // Chaque test ouvre sa propre base SQLite temporaire (migrations
    // rejouees, y compris le seed du compte "admin" / "admin123" -
    // voir database/Migrations/002_add_user_password.sql).
    database::DatabaseManager *freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        Q_ASSERT(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-usermanager-%1").arg(reinterpret_cast<quintptr>(QTest::currentTestFunction())));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        Q_ASSERT(opened);
        return m_dbManager.get();
    }

private slots:
    void cleanup()
    {
        if (m_dbManager) {
            m_dbManager->close();
        }
        m_dbManager.reset();
        m_dir.reset();
    }

    void loginWithSeededAdminSucceeds()
    {
        core::UserManager manager(freshDatabase());
        QSignalSpy successSpy(&manager, &core::UserManager::loginSucceeded);
        QSignalSpy failureSpy(&manager, &core::UserManager::loginFailed);

        QVERIFY(manager.login(QStringLiteral("admin"), QStringLiteral("admin123")));

        QCOMPARE(successSpy.count(), 1);
        QCOMPARE(failureSpy.count(), 0);
        QVERIFY(manager.isAuthenticated());
        QCOMPARE(manager.currentUsername(), QStringLiteral("admin"));
        QVERIFY(manager.isCurrentUserAdmin());
        QVERIFY(!manager.isBusy());
    }

    void loginWithWrongPasswordFails()
    {
        core::UserManager manager(freshDatabase());
        QSignalSpy failureSpy(&manager, &core::UserManager::loginFailed);

        QVERIFY(!manager.login(QStringLiteral("admin"), QStringLiteral("not-the-password")));

        QCOMPARE(failureSpy.count(), 1);
        QVERIFY(!manager.isAuthenticated());
        QVERIFY(manager.currentUsername().isEmpty());
    }

    void loginWithUnknownUserFails()
    {
        core::UserManager manager(freshDatabase());
        QSignalSpy failureSpy(&manager, &core::UserManager::loginFailed);

        QVERIFY(!manager.login(QStringLiteral("inconnu"), QStringLiteral("peu-importe")));

        QCOMPARE(failureSpy.count(), 1);
        QVERIFY(!manager.isAuthenticated());
    }

    void loginWithEmptyFieldsFailsWithoutTouchingDatabase()
    {
        core::UserManager manager(freshDatabase());
        QSignalSpy failureSpy(&manager, &core::UserManager::loginFailed);

        QVERIFY(!manager.login(QString(), QString()));
        QVERIFY(!manager.login(QStringLiteral("admin"), QString()));

        QCOMPARE(failureSpy.count(), 2);
        QVERIFY(!manager.isAuthenticated());
    }

    void newlyCreatedUserCanLogIn()
    {
        database::DatabaseManager *db = freshDatabase();

        database::UserRepository repository(db->database());
        models::User newUser(-1, QStringLiteral("bilal"), QStringLiteral("192.168.1.11"),
                              QStringLiteral("offline"), false, core::PasswordHasher::hash(QStringLiteral("s3cret!")));
        QVERIFY(repository.create(newUser));
        QVERIFY(newUser.id() > 0);

        core::UserManager manager(db);
        QVERIFY(manager.login(QStringLiteral("bilal"), QStringLiteral("s3cret!")));
        QVERIFY(manager.isAuthenticated());
        QVERIFY(!manager.isCurrentUserAdmin());
    }

    void logoutClearsAuthenticationState()
    {
        core::UserManager manager(freshDatabase());
        QVERIFY(manager.login(QStringLiteral("admin"), QStringLiteral("admin123")));
        QVERIFY(manager.isAuthenticated());

        QSignalSpy authChangedSpy(&manager, &core::UserManager::authenticationChanged);
        manager.logout();

        QVERIFY(!manager.isAuthenticated());
        QVERIFY(manager.currentUsername().isEmpty());
        QCOMPARE(authChangedSpy.count(), 1);
    }
};

QTEST_MAIN(TestUserManager)
#include "test_usermanager.moc"
