#ifndef CORE_USERMANAGER_H
#define CORE_USERMANAGER_H

#include <QSqlDatabase>
#include <QString>
#include <optional>
#include <vector>

#include "database/Repositories/UserRepository.h"
#include "models/User.h"

namespace core {

/**
 * @brief Resultat d'une operation de creation/authentification.
 */
enum class UserManagerError {
    None,
    InvalidName,
    InvalidPassword,
    UserAlreadyExists,
    UserNotFound,
    WrongPassword,
    DatabaseError
};

/**
 * @brief Gestion des utilisateurs (creation, authentification, statut).
 *
 * Logique metier pure : aucune dependance graphique. S'appuie sur
 * database::UserRepository pour la persistance.
 */
class UserManager {
public:
    explicit UserManager(QSqlDatabase database);
    ~UserManager();

    /**
     * @brief Cree un nouvel utilisateur local avec un mot de passe.
     *
     * Le mot de passe n'est jamais stocke en clair : il est sale puis
     * hache (SHA-256) avant persistance.
     */
    std::optional<models::User> createUser(const QString &name,
                                            const QString &password,
                                            bool isAdmin = false);

    /**
     * @brief Verifie les identifiants d'un utilisateur.
     * @return l'utilisateur authentifie si les identifiants sont valides.
     */
    std::optional<models::User> authenticate(const QString &name, const QString &password);

    /**
     * @brief Utilisateur actuellement connecte sur ce poste (le cas echeant).
     */
    std::optional<models::User> currentUser() const;

    /**
     * @brief Deconnecte l'utilisateur courant (passe son statut a hors ligne).
     */
    void logout();

    /**
     * @brief Change le statut (en ligne / hors ligne / absent) d'un utilisateur.
     */
    bool setStatus(int userId, models::UserStatus status);

    /**
     * @brief Statut courant d'un utilisateur.
     */
    std::optional<models::UserStatus> status(int userId) const;

    std::vector<models::User> allUsers() const;

    /**
     * @brief Dernier message d'erreur SQL brut (debogage).
     */
    QString lastDatabaseErrorText() const;

    UserManagerError lastError() const;

private:
    static QString generateSalt();
    static QString hashPassword(const QString &password, const QString &salt);
    static bool verifyPassword(const QString &password, const QString &salt, const QString &expectedHash);

    database::UserRepository m_repository;
    std::optional<int> m_currentUserId;
    UserManagerError m_lastError = UserManagerError::None;
};

} // namespace core

#endif // CORE_USERMANAGER_H
