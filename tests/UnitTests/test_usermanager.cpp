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

    // --- Lot 2 securite : empreintes PBKDF2 --------------------------------

    void passwordHashUsesPbkdf2AndVerifies()
    {
        const QString salt = core::PasswordHasher::generateSalt();
        const QString stored = core::PasswordHasher::hashPassword(QStringLiteral("S3cret-motdepasse"), salt);
        QVERIFY2(stored.startsWith(QStringLiteral("pbkdf2$sha256$100000$")), qPrintable(stored));
        QVERIFY(!core::PasswordHasher::needsRehash(stored));
        QVERIFY(core::PasswordHasher::verify(QStringLiteral("S3cret-motdepasse"), salt, stored));
        QVERIFY(!core::PasswordHasher::verify(QStringLiteral("mauvais"), salt, stored));
        // Nombre d'iterations aberrant (empreinte recue du reseau) : refuse sans calcul interminable.
        QVERIFY(!core::PasswordHasher::verify(QStringLiteral("x"), salt, QStringLiteral("pbkdf2$sha256$999999999$00")));
    }

    void legacyHashIsAcceptedThenUpgradedAtLogin()
    {
        database::DatabaseManager *db = freshDatabase();
        database::UserRepository repository(db->database());
        auto legacy = repository.findByName(QStringLiteral("admin"));
        QVERIFY(legacy.has_value());
        legacy->setPasswordSalt(QStringLiteral("ancien-sel"));
        legacy->setPasswordHash(core::PasswordHasher::hash(QStringLiteral("admin123"), QStringLiteral("ancien-sel")));
        QVERIFY(repository.update(*legacy));
        QVERIFY(core::PasswordHasher::needsRehash(repository.findByName(QStringLiteral("admin"))->passwordHash()));

        core::UserManager manager(db);
        QVERIFY(manager.authenticate(QStringLiteral("admin"), QStringLiteral("admin123")).has_value());

        const auto upgraded = repository.findByName(QStringLiteral("admin"));
        QVERIFY(!core::PasswordHasher::needsRehash(upgraded->passwordHash()));
        QVERIFY(manager.authenticate(QStringLiteral("admin"), QStringLiteral("admin123")).has_value());
        QVERIFY(!manager.authenticate(QStringLiteral("admin"), QStringLiteral("faux")).has_value());
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

    // --- "Se souvenir de moi" (migration #026, SessionRepository) --------

    void rememberThisDeviceThenAutoLoginSucceeds()
    {
        database::DatabaseManager *db = freshDatabase();
        core::UserManager manager(db);

        QVERIFY(manager.login(QStringLiteral("admin"), QStringLiteral("admin123")));
        const QString token = manager.rememberThisDevice();
        QVERIFY(!token.isEmpty());

        // Simule un redemarrage de l'application : nouvelle instance de
        // UserManager (donc etat en memoire perdu), meme base SQLite.
        core::UserManager restarted(db);
        QSignalSpy successSpy(&restarted, &core::UserManager::loginSucceeded);
        QSignalSpy failureSpy(&restarted, &core::UserManager::loginFailed);

        QVERIFY(restarted.loginWithRememberedToken(QStringLiteral("admin"), token));

        QCOMPARE(successSpy.count(), 1);
        QCOMPARE(failureSpy.count(), 0);
        QVERIFY(restarted.isAuthenticated());
        QCOMPARE(restarted.currentUsername(), QStringLiteral("admin"));
        QVERIFY(restarted.isCurrentUserAdmin());
    }

    void autoLoginWithWrongTokenFailsSilently()
    {
        database::DatabaseManager *db = freshDatabase();
        core::UserManager manager(db);
        QVERIFY(manager.login(QStringLiteral("admin"), QStringLiteral("admin123")));
        QVERIFY(!manager.rememberThisDevice().isEmpty());

        core::UserManager restarted(db);
        QSignalSpy failureSpy(&restarted, &core::UserManager::loginFailed);

        QVERIFY(!restarted.loginWithRememberedToken(QStringLiteral("admin"), QStringLiteral("bogus-token")));

        // Un jeton invalide ne doit jamais emettre loginFailed (auto-login
        // silencieux : l'echec doit se traduire par un simple retour a
        // l'ecran Login, pas par un message d'erreur).
        QCOMPARE(failureSpy.count(), 0);
        QVERIFY(!restarted.isAuthenticated());
    }

    void autoLoginWithMismatchedUsernameFails()
    {
        database::DatabaseManager *db = freshDatabase();
        core::UserManager manager(db);
        QVERIFY(manager.createUser(QStringLiteral("gina"), QStringLiteral("password1")).has_value());

        QVERIFY(manager.login(QStringLiteral("admin"), QStringLiteral("admin123")));
        const QString token = manager.rememberThisDevice();
        QVERIFY(!token.isEmpty());

        core::UserManager restarted(db);
        // Le jeton appartient a "admin", pas a "gina" : doit etre refuse.
        QVERIFY(!restarted.loginWithRememberedToken(QStringLiteral("gina"), token));
        QVERIFY(!restarted.isAuthenticated());
    }

    void logoutInvalidatesRememberedToken()
    {
        database::DatabaseManager *db = freshDatabase();
        core::UserManager manager(db);

        QVERIFY(manager.login(QStringLiteral("admin"), QStringLiteral("admin123")));
        const QString token = manager.rememberThisDevice();
        QVERIFY(!token.isEmpty());

        manager.logout();

        core::UserManager restarted(db);
        QVERIFY(!restarted.loginWithRememberedToken(QStringLiteral("admin"), token));
    }

    void forgetRememberedTokenPreventsFutureAutoLogin()
    {
        database::DatabaseManager *db = freshDatabase();
        core::UserManager manager(db);

        QVERIFY(manager.login(QStringLiteral("admin"), QStringLiteral("admin123")));
        const QString token = manager.rememberThisDevice();
        QVERIFY(!token.isEmpty());

        manager.forgetRememberedToken(token);

        core::UserManager restarted(db);
        QVERIFY(!restarted.loginWithRememberedToken(QStringLiteral("admin"), token));
    }

    // ------------------------------------------------------------------
    // Changement de mot de passe par l'utilisateur lui-meme.
    // Avant changeOwnPassword(), la seule voie etait resetPassword(), reservee
    // a un administrateur : celui-ci choisissait donc le mot de passe et le
    // connaissait. Ces tests verifient que l'ancien mot de passe est bien exige
    // et que le nouveau prend effet reellement (connexion apres coup).
    // ------------------------------------------------------------------
    void changeOwnPasswordRequiresAnAuthenticatedUser()
    {
        database::DatabaseManager *db = freshDatabase();
        core::UserManager manager(db);

        // Personne n'est connecte : aucun changement ne doit etre possible.
        QVERIFY(!manager.changeOwnPassword(QStringLiteral("admin123"),
                                           QStringLiteral("nouveau-mdp"),
                                           QStringLiteral("nouveau-mdp")).isEmpty());

        core::UserManager other(db);
        QVERIFY(other.login(QStringLiteral("admin"), QStringLiteral("admin123")));
    }

    void changeOwnPasswordRejectsWrongCurrentPassword()
    {
        database::DatabaseManager *db = freshDatabase();
        core::UserManager manager(db);
        QVERIFY(manager.login(QStringLiteral("admin"), QStringLiteral("admin123")));

        QVERIFY(!manager.changeOwnPassword(QStringLiteral("pas-le-bon"),
                                           QStringLiteral("nouveau-mdp"),
                                           QStringLiteral("nouveau-mdp")).isEmpty());

        // L'ancien mot de passe doit rester valable, le nouveau refuse.
        core::UserManager fresh(db);
        QVERIFY(fresh.login(QStringLiteral("admin"), QStringLiteral("admin123")));
        core::UserManager fresh2(db);
        QVERIFY(!fresh2.login(QStringLiteral("admin"), QStringLiteral("nouveau-mdp")));
    }

    void changeOwnPasswordRejectsMismatchedConfirmationOrTooShortPassword()
    {
        database::DatabaseManager *db = freshDatabase();
        core::UserManager manager(db);
        QVERIFY(manager.login(QStringLiteral("admin"), QStringLiteral("admin123")));

        // Confirmation differente.
        QVERIFY(!manager.changeOwnPassword(QStringLiteral("admin123"),
                                           QStringLiteral("nouveau-mdp"),
                                           QStringLiteral("nouveau-mdq")).isEmpty());
        // Trop court (meme regle que createUser).
        QVERIFY(!manager.changeOwnPassword(QStringLiteral("admin123"),
                                           QStringLiteral("ab"),
                                           QStringLiteral("ab")).isEmpty());
        // Identique a l'ancien : sans interet et masque une erreur de saisie.
        QVERIFY(!manager.changeOwnPassword(QStringLiteral("admin123"),
                                           QStringLiteral("admin123"),
                                           QStringLiteral("admin123")).isEmpty());

        core::UserManager fresh(db);
        QVERIFY(fresh.login(QStringLiteral("admin"), QStringLiteral("admin123")));
    }

    void changeOwnPasswordSucceedsAndNewPasswordIsRequiredAfterwards()
    {
        database::DatabaseManager *db = freshDatabase();
        core::UserManager manager(db);
        QVERIFY(manager.login(QStringLiteral("admin"), QStringLiteral("admin123")));

        QCOMPARE(manager.changeOwnPassword(QStringLiteral("admin123"),
                                           QStringLiteral("nouveau-mdp"),
                                           QStringLiteral("nouveau-mdp")),
                 QString());

        // L'ancien mot de passe ne doit plus ouvrir la session...
        core::UserManager fresh(db);
        QVERIFY(!fresh.login(QStringLiteral("admin"), QStringLiteral("admin123")));
        // ...et le nouveau doit fonctionner.
        core::UserManager fresh2(db);
        QVERIFY(fresh2.login(QStringLiteral("admin"), QStringLiteral("nouveau-mdp")));
    }
};

QTEST_MAIN(TestUserManager)
#include "test_usermanager.moc"