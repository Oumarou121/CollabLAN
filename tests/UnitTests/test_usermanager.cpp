#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>
#include <QRandomGenerator>

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

// Chaque test ouvre sa propre base SQLite temporaire, puis seede
    // manuellement le compte "admin"/"admin123" : ce seed est fait par
    // Application::initialize() en production (via UserManager::createUser,
    // hash+salt corrects), plus par une migration SQL.
    database::DatabaseManager *freshDatabase()
    {
        m_dir = std::make_unique<QTemporaryDir>();
        Q_ASSERT(m_dir->isValid());

        m_dbManager = std::make_unique<database::DatabaseManager>(
            QStringLiteral("test-usermanager-%1").arg(QRandomGenerator::global()->generate()));
        const bool opened = m_dbManager->open(m_dir->filePath(QStringLiteral("test.db")));
        Q_ASSERT(opened);

        core::UserManager seeder(m_dbManager.get());
        const auto admin = seeder.createUser(QStringLiteral("admin"), QStringLiteral("admin123"), /*isAdmin=*/true);
        Q_ASSERT(admin.has_value());

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

    // --- Parcours QML (login/logout) ------------------------------------

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

    // --- API C++ (creation, authenticate direct, statut) -----------------

    void createUserThenLoginSucceeds()
    {
        database::DatabaseManager *db = freshDatabase();
        core::UserManager manager(db);

        const auto created = manager.createUser(QStringLiteral("bilal"), QStringLiteral("s3cret!"));
        QVERIFY(created.has_value());
        QVERIFY(created->id() > 0);
        QVERIFY(created->passwordHash() != QStringLiteral("s3cret!"));
        QVERIFY(!created->passwordSalt().isEmpty());

        QVERIFY(manager.login(QStringLiteral("bilal"), QStringLiteral("s3cret!")));
        QVERIFY(manager.isAuthenticated());
        QVERIFY(!manager.isCurrentUserAdmin());
    }

    void createUserRejectsDuplicateName()
    {
        core::UserManager manager(freshDatabase());

        QVERIFY(manager.createUser(QStringLiteral("bob"), QStringLiteral("password1")).has_value());
        const auto duplicate = manager.createUser(QStringLiteral("bob"), QStringLiteral("otherpass"));

        QVERIFY(!duplicate.has_value());
        QCOMPARE(manager.lastError(), core::UserManagerError::UserAlreadyExists);
    }

    void createUserRejectsEmptyNameOrShortPassword()
    {
        core::UserManager manager(freshDatabase());

        QVERIFY(!manager.createUser(QStringLiteral("   "), QStringLiteral("password1")).has_value());
        QCOMPARE(manager.lastError(), core::UserManagerError::InvalidName);

        QVERIFY(!manager.createUser(QStringLiteral("carol"), QStringLiteral("ab")).has_value());
        QCOMPARE(manager.lastError(), core::UserManagerError::InvalidPassword);
    }

    void authenticateFailsWithWrongPassword()
    {
        core::UserManager manager(freshDatabase());
        QVERIFY(manager.createUser(QStringLiteral("erin"), QStringLiteral("rightpassword")).has_value());

        const auto authenticated = manager.authenticate(QStringLiteral("erin"), QStringLiteral("wrongpassword"));
        QVERIFY(!authenticated.has_value());
        QCOMPARE(manager.lastError(), core::UserManagerError::WrongPassword);
    }

    void statusManagementRoundTrips()
    {
        core::UserManager manager(freshDatabase());
        const auto user = manager.createUser(QStringLiteral("frank"), QStringLiteral("password1"));
        QVERIFY(user.has_value());

        auto initialStatus = manager.status(user->id());
        QVERIFY(initialStatus.has_value());
        QCOMPARE(*initialStatus, models::UserStatus::Offline);

        QVERIFY(manager.setStatus(user->id(), models::UserStatus::Online));
        auto onlineStatus = manager.status(user->id());
        QVERIFY(onlineStatus.has_value());
        QCOMPARE(*onlineStatus, models::UserStatus::Online);
    }
};

QTEST_MAIN(TestUserManager)
#include "test_usermanager.moc"