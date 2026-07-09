#include "UserManager.h"

#include <QCryptographicHash>
#include <QRandomGenerator>

namespace core {

namespace {
constexpr int kSaltByteLength = 16;
constexpr int kMinPasswordLength = 4;
} // namespace

UserManager::UserManager(QSqlDatabase database)
    : m_repository(std::move(database))
{
}

UserManager::~UserManager() = default;

QString UserManager::generateSalt()
{
    QByteArray salt(kSaltByteLength, Qt::Uninitialized);
    for (int i = 0; i < kSaltByteLength; ++i) {
        salt[i] = static_cast<char>(QRandomGenerator::global()->bounded(256));
    }
    return QString::fromLatin1(salt.toHex());
}

QString UserManager::hashPassword(const QString &password, const QString &salt)
{
    const QByteArray data = (salt + password).toUtf8();
    return QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex());
}

bool UserManager::verifyPassword(const QString &password, const QString &salt, const QString &expectedHash)
{
    return hashPassword(password, salt) == expectedHash;
}

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

    if (m_repository.existsByName(trimmedName)) {
        m_lastError = UserManagerError::UserAlreadyExists;
        return std::nullopt;
    }

    const QString salt = generateSalt();
    const QString hash = hashPassword(password, salt);

    models::User user;
    user.setName(trimmedName);
    user.setStatus(models::UserStatus::Offline);
    user.setIsAdmin(isAdmin);
    user.setPasswordHash(hash);
    user.setPasswordSalt(salt);

    const int id = m_repository.create(user);
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
    const auto existing = m_repository.findByName(name.trimmed());
    if (!existing.has_value()) {
        m_lastError = UserManagerError::UserNotFound;
        return std::nullopt;
    }

    if (!verifyPassword(password, existing->passwordSalt(), existing->passwordHash())) {
        m_lastError = UserManagerError::WrongPassword;
        return std::nullopt;
    }

    m_repository.updateStatus(existing->id(), models::UserStatus::Online);
    m_currentUserId = existing->id();
    m_lastError = UserManagerError::None;

    models::User authenticated = *existing;
    authenticated.setStatus(models::UserStatus::Online);
    return authenticated;
}

std::optional<models::User> UserManager::currentUser() const
{
    if (!m_currentUserId.has_value()) {
        return std::nullopt;
    }
    return m_repository.findById(*m_currentUserId);
}

void UserManager::logout()
{
    if (m_currentUserId.has_value()) {
        m_repository.updateStatus(*m_currentUserId, models::UserStatus::Offline);
        m_currentUserId.reset();
    }
}

bool UserManager::setStatus(int userId, models::UserStatus status)
{
    const bool ok = m_repository.updateStatus(userId, status);
    m_lastError = ok ? UserManagerError::None : UserManagerError::DatabaseError;
    return ok;
}

std::optional<models::UserStatus> UserManager::status(int userId) const
{
    const auto user = m_repository.findById(userId);
    if (!user.has_value()) {
        return std::nullopt;
    }
    return user->status();
}

std::vector<models::User> UserManager::allUsers() const
{
    return m_repository.findAll();
}

QString UserManager::lastDatabaseErrorText() const
{
    return m_repository.lastError();
}

UserManagerError UserManager::lastError() const
{
    return m_lastError;
}

} // namespace core
