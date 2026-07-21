#include "UserManager.h"

#include <QDateTime>
#include <QDebug>

#include "DatabaseManager.h"
#include "PasswordHasher.h"

namespace core {

namespace {
constexpr int kMinPasswordLength = 4;
// Duree de vie d'un jeton "Se souvenir de moi" avant expiration forcee.
constexpr int kRememberMeSessionDays = 30;
} // namespace

UserManager::UserManager(database::DatabaseManager *databaseManager, QObject *parent)
    : QObject(parent)
    , m_databaseManager(databaseManager)
    , m_userRepository(databaseManager ? databaseManager->database() : QSqlDatabase())
    , m_sessionRepository(databaseManager ? databaseManager->database() : QSqlDatabase())
{
    // Nettoyage ponctuel des jetons "Se souvenir de moi" perimes : evite
    // une accumulation indefinie de lignes mortes dans UserSessions au fil
    // des mois (pas besoin d'un cycle recurrent, un coup par demarrage suffit).
    if (m_databaseManager && m_databaseManager->isOpen()) {
        m_sessionRepository.removeExpired();
    }
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

    m_userRepository.updateStatus(user->id(), models::UserStatus::Online);

    m_currentUsername = user->name();
    m_currentUserIsAdmin = user->isAdmin();
    m_currentUserId = user->id();
    m_currentUserUuid = user->uuid();
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
        // Une deconnexion explicite invalide aussi tout jeton "Se souvenir
        // de moi" persiste pour cet utilisateur sur ce poste : sans cela,
        // le prochain demarrage de l'application reconnecterait silencieusement
        // l'utilisateur malgre le logout, ce qui surprendrait plus qu'autre
        // chose. La table etant locale (non synchronisee), ceci n'affecte
        // que ce poste.
        m_sessionRepository.removeAllForUser(*m_currentUserId);
        m_currentUserId.reset();
        m_currentUserUuid.clear();
    }

    if (!m_authenticated) {
        return;
    }
    m_authenticated = false;
    m_currentUsername.clear();
    m_currentUserIsAdmin = false;
    emit authenticationChanged();
}

QString UserManager::rememberThisDevice()
{
    if (!m_authenticated || !m_currentUserId.has_value()) {
        qDebug() << "[UserManager::rememberThisDevice] non authentifie, abandon";
        return QString();
    }
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        qDebug() << "[UserManager::rememberThisDevice] base de donnees indisponible";
        return QString();
    }

    // Le jeton brut est une valeur aleatoire haute-entropie (128 bits,
    // meme generateur que les sels de mot de passe) : inutile de la saler
    // a nouveau avant de la hacher, contrairement a un mot de passe humain
    // a faible entropie (cf. core::PasswordHasher, doc de classe).
    const QString rawToken = PasswordHasher::generateSalt();
    const QString tokenHash = PasswordHasher::hash(rawToken, QString());
    const QDateTime expiresAt = QDateTime::currentDateTimeUtc().addDays(kRememberMeSessionDays);

    const int sessionId = m_sessionRepository.create(*m_currentUserId, tokenHash, expiresAt);
    if (sessionId < 0) {
        qDebug() << "[UserManager::rememberThisDevice] echec ecriture UserSessions :"
                  << m_sessionRepository.lastError();
        return QString();
    }
    qDebug() << "[UserManager::rememberThisDevice] session" << sessionId << "creee pour utilisateur"
              << *m_currentUserId << "expire le" << expiresAt;
    return rawToken;
}

bool UserManager::loginWithRememberedToken(const QString &username, const QString &token)
{
    const QString trimmedUsername = username.trimmed();
    if (trimmedUsername.isEmpty() || token.isEmpty()) {
        qDebug() << "[UserManager::loginWithRememberedToken] username ou token vide, abandon";
        return false;
    }
    if (!m_databaseManager || !m_databaseManager->isOpen()) {
        qDebug() << "[UserManager::loginWithRememberedToken] base de donnees indisponible";
        return false;
    }

    const QString tokenHash = PasswordHasher::hash(token, QString());
    const auto session = m_sessionRepository.findByTokenHash(tokenHash);
    if (!session.has_value()) {
        qDebug() << "[UserManager::loginWithRememberedToken] aucune session trouvee pour ce hash de jeton"
                  << "(lastError=" << m_sessionRepository.lastError() << ")";
        return false;
    }
    if (session->isExpired()) {
        // Nettoyage immediat : pas la peine d'attendre un cycle de
        // removeExpired() pour un jeton qu'on sait deja perime.
        qDebug() << "[UserManager::loginWithRememberedToken] session expiree (expiresAt="
                 << session->expiresAt() << ")";
        m_sessionRepository.remove(session->id());
        return false;
    }

    const auto user = m_userRepository.findById(session->userId());
    if (!user.has_value() || user->name() != trimmedUsername) {
        // Le jeton ne correspond pas au nom d'utilisateur attendu (compte
        // supprime/renomme depuis, ou jeton corrompu) : on refuse plutot
        // que de connecter la mauvaise identite.
        qDebug() << "[UserManager::loginWithRememberedToken] utilisateur introuvable ou nom different"
                  << "(attendu=" << trimmedUsername
                  << ", trouve=" << (user.has_value() ? user->name() : QStringLiteral("<aucun>")) << ")";
        return false;
    }

    m_userRepository.updateStatus(user->id(), models::UserStatus::Online);

    m_currentUsername = user->name();
    m_currentUserIsAdmin = user->isAdmin();
    m_currentUserId = user->id();
    m_currentUserUuid = user->uuid();
    m_authenticated = true;
    qDebug() << "[UserManager::loginWithRememberedToken] auto-login reussi pour" << m_currentUsername;
    emit authenticationChanged();
    emit loginSucceeded(m_currentUsername);
    return true;
}

void UserManager::forgetRememberedToken(const QString &token)
{
    if (token.isEmpty()) {
        return;
    }
    const QString tokenHash = PasswordHasher::hash(token, QString());
    m_sessionRepository.removeByTokenHash(tokenHash);
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

QString UserManager::currentUserUuid() const
{
    return m_currentUserUuid;
}

QString UserManager::userNameForUuid(const QString &uuid) const
{
    if (uuid.isEmpty()) {
        return QString();
    }

    const auto user = m_userRepository.findByUuid(uuid);
    return user.has_value() ? user->name() : QString();
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
    user.setRole(isAdmin ? models::UserRole::Admin : models::UserRole::User);
    user.setPasswordHash(hash);
    user.setPasswordSalt(salt);

    const int id = m_userRepository.create(user);
    if (id < 0) {
        m_lastError = UserManagerError::DatabaseError;
        return std::nullopt;
    }
    m_lastError = UserManagerError::None;

    // Recharger depuis la base : create() genere le uuid/updated_at
    // (migration 010) que le modele passe en parametre ne connait pas encore.
    const auto persisted = m_userRepository.findById(id);
    if (persisted.has_value()) {
        emit userCreated(*persisted);
        return persisted;
    }
    user.setId(id);
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
    if (ok) {
        const auto updated = m_userRepository.findById(userId);
        if (updated.has_value()) {
            emit userUpdated(*updated);
        }
    }
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

bool UserManager::changeRole(int userId, bool isAdmin)
{
    auto existing = m_userRepository.findById(userId);
    if (!existing.has_value()) {
        m_lastError = UserManagerError::UserNotFound;
        return false;
    }

    existing->setRole(isAdmin ? models::UserRole::Admin : models::UserRole::User);
    existing->setUpdatedAt(QDateTime::currentDateTimeUtc());

    const bool ok = m_userRepository.update(*existing);
    m_lastError = ok ? UserManagerError::None : UserManagerError::DatabaseError;
    if (ok) {
        emit userUpdated(*existing);
    }
    return ok;
}

bool UserManager::deleteUser(int userId)
{
    const auto existing = m_userRepository.findById(userId);
    if (!existing.has_value()) {
        m_lastError = UserManagerError::UserNotFound;
        return false;
    }

    const bool ok = m_userRepository.remove(userId);
    m_lastError = ok ? UserManagerError::None : UserManagerError::DatabaseError;
    if (ok) {
        emit userDeleted(existing->uuid(), userId);
    }
    return ok;
}

std::vector<models::User> UserManager::allUsers() const
{
    return m_userRepository.findAll();
}

void UserManager::emitUsersChanged()
{
    // Émettre le signal dans le thread principal pour éviter les crashs Qt
    QMetaObject::invokeMethod(this, [this]() {
        emit usersChanged();
    }, Qt::QueuedConnection);
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
