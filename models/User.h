#ifndef MODELS_USER_H
#define MODELS_USER_H

#include <QString>
#include <QDateTime>
#include <optional>

namespace models {

/**
 * @brief Statut de connexion d'un utilisateur/poste.
 */
enum class UserStatus {
    Offline,
    Online,
    Away
};

QString userStatusToString(UserStatus status);
UserStatus userStatusFromString(const QString &value);

/**
 * @brief Rôles utilisateurs dans l'application (issue #67).
 */
enum class UserRole {
    User,   ///< Utilisateur standard (accès limité)
    Admin   ///< Administrateur (accès complet, y compris administration)
};

QString userRoleToString(UserRole role);
std::optional<UserRole> stringToUserRole(const QString &str);

/**
 * @brief Represente un utilisateur/poste sur le reseau.
 *
 * Correspond a une ligne de la table `Users`. Le hash + le sel de mot
 * de passe sont transportes par ce modele pour permettre a
 * UserRepository de les lire/ecrire, mais ne doivent jamais etre
 * exposes tels quels a l'interface (cf. core::UserManager, qui ne
 * remonte a la QML que le nom d'utilisateur et le role admin).
 */
class User {
public:
    User();
    User(int id,
         QString name,
         QString ipAddress,
         UserStatus status,
         UserRole role,
         QString passwordHash,
         QString passwordSalt,
         QDateTime createdAt = QDateTime::currentDateTimeUtc());
    ~User();

    int id() const;
    void setId(int id);

    QString name() const;
    void setName(const QString &name);

    QString ipAddress() const;
    void setIpAddress(const QString &ipAddress);

    UserStatus status() const;
    void setStatus(UserStatus status);

    UserRole role() const;
    void setRole(UserRole role);

    bool isAdmin() const; ///< Convenience method for backward compatibility
    void setIsAdmin(bool isAdmin); ///< Convenience method for backward compatibility

    QString passwordHash() const;
    void setPasswordHash(const QString &hash);

    QString passwordSalt() const;
    void setPasswordSalt(const QString &salt);

    QDateTime createdAt() const;
    void setCreatedAt(const QDateTime &createdAt);

    bool isValid() const;

private:
    int m_id = -1;
    QString m_name;
    QString m_ipAddress = QStringLiteral("");
    UserStatus m_status = UserStatus::Offline;
    UserRole m_role = UserRole::User;
    QString m_passwordHash = QStringLiteral("");
    QString m_passwordSalt = QStringLiteral("");
    QDateTime m_createdAt;
};

} // namespace models

#endif // MODELS_USER_H
