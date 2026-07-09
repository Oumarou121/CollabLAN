#include "UserManager.h"

#include "DatabaseManager.h"
#include "PasswordHasher.h"
#include "UserRepository.h"

namespace core {

UserManager::UserManager(database::DatabaseManager *databaseManager, QObject *parent)
    : QObject(parent)
    , m_databaseManager(databaseManager)
    , m_userRepository(std::make_unique<database::UserRepository>(
          databaseManager ? databaseManager->database() : QSqlDatabase()))
{
}

UserManager::~UserManager() = default;

bool UserManager::login(const QString &username, const QString &password)
{
    const QString trimmedUsername = username.trimmed();

    if (trimmedUsername.isEmpty() || password.isEmpty()) {
        emit loginFailed(tr("Merci de renseigner un nom d'utilisateur et un mot de passe."));
        return false;
    }

    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        emit loginFailed(tr("La base de donnees est indisponible. Veuillez reessayer plus tard."));
        return false;
    }

    setBusy(true);

    const std::optional<models::User> user = m_userRepository->findByName(trimmedUsername);

    if (!user.has_value() || !PasswordHasher::verify(password, user->passwordHash())) {
        setBusy(false);
        emit loginFailed(tr("Nom d'utilisateur ou mot de passe incorrect."));
        return false;
    }

    m_currentUsername = user->name();
    m_currentUserIsAdmin = user->isAdmin();
    m_authenticated = true;

    setBusy(false);
    emit authenticationChanged();
    emit loginSucceeded(m_currentUsername);
    return true;
}

void UserManager::logout()
{
    if (!m_authenticated) {
        return;
    }

    m_authenticated = false;
    m_currentUsername.clear();
    m_currentUserIsAdmin = false;

    emit authenticationChanged();
}

bool UserManager::isAuthenticated() const
{
    return m_authenticated;
}

QString UserManager::currentUsername() const
{
    return m_currentUsername;
}

bool UserManager::isCurrentUserAdmin() const
{
    return m_currentUserIsAdmin;
}

bool UserManager::isBusy() const
{
    return m_busy;
}

void UserManager::setBusy(bool busy)
{
    if (m_busy == busy) {
        return;
    }
    m_busy = busy;
    emit busyChanged();
}

} // namespace core
