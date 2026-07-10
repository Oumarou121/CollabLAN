#include "UserManager.h"

#include "DatabaseManager.h"
#include "PasswordHasher.h"

namespace core {

namespace {
constexpr int kMinPasswordLength = 4;
} // namespace

UserManager::UserManager(database::DatabaseManager *databaseManager, QObject *parent)
    : QObject(parent)
    , m_databaseManager(databaseManager)
    , m_userRepository(databaseManager ? databaseManager->database() : QSqlDatabase())
{
}

UserManager::~UserManager() = default;

// --- API QML ----------------------------------------------------------

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
    const auto user = authenticate(trimmedUsername, password);
    if (!user.has_value()) {
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
    if (m_currentUserId.has_value()) {
        m_userRepository.updateStatus(*m_currentUserId, models::UserStatus::Offline);
        m_currentUserId.reset();
    }

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

std::optional<int> UserManager::currentUserId() const
{
    return m_currentUserId;
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

// --- API C++ (administration) ------------------------------------------

std::optional<models::User> UserManager::createUser(const QString &name,
                                                      const QString &password,
                                                      bool isAdmin)
{
    const QString trimmedName = name.trimmed();
    if (trimmedName.isEmpty()) {
        m_lastError = UserManagerError::InvalidName;
        return std::nullopt;
    }
    if (password.size() < kMinPasswordLength) {
        m_lastError = UserManagerError::InvalidPassword;
        return std::nullopt;
    }
    if (m_userRepository.existsByName(trimmedName)) {
        m_lastError = UserManagerError::UserAlreadyExists;
        return std::nullopt;
    }

    const QString salt = PasswordHasher::generateSalt();
    const QString hash = PasswordHasher::hash(password, salt);

    models::User user;
    user.setName(trimmedName);
    user.setStatus(models::UserStatus::Offline);
    user.setIsAdmin(isAdmin);
    user.setPasswordHash(hash);
    user.setPasswordSalt(salt);

    const int id = m_userRepository.create(user);
    if (id < 0) {
        m_lastError = UserManagerError::DatabaseError;
        return std::nullopt;
    }
    user.setId(id);
    m_lastError = UserManagerError::None;
    return user;
}

std::optional<models::User> UserManager::authenticate(const QString &name, const QString &password)
{
    const auto existing = m_userRepository.findByName(name.trimmed());
    if (!existing.has_value()) {
        m_lastError = UserManagerError::UserNotFound;
        return std::nullopt;
    }
    if (!PasswordHasher::verify(password, existing->passwordSalt(), existing->passwordHash())) {
        m_lastError = UserManagerError::WrongPassword;
        return std::nullopt;
    }

    m_userRepository.updateStatus(existing->id(), models::UserStatus::Online);
    m_currentUserId = existing->id();
    m_lastError = UserManagerError::None;

    models::User authenticated = *existing;
    authenticated.setStatus(models::UserStatus::Online);
    return authenticated;
}

bool UserManager::setStatus(int userId, models::UserStatus status)
{
    const bool ok = m_userRepository.updateStatus(userId, status);
    m_lastError = ok ? UserManagerError::None : UserManagerError::DatabaseError;
    return ok;
}

std::optional<models::UserStatus> UserManager::status(int userId) const
{
    const auto user = m_userRepository.findById(userId);
    if (!user.has_value()) {
        return std::nullopt;
    }
    return user->status();
}

std::vector<models::User> UserManager::allUsers() const
{
    return m_userRepository.findAll();
}

QString UserManager::lastDatabaseErrorText() const
{
    return m_userRepository.lastError();
}

UserManagerError UserManager::lastError() const
{
    return m_lastError;
}

} // namespace core