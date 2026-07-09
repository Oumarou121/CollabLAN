#ifndef MODELS_USER_H
#define MODELS_USER_H

#include <QString>
#include <QDateTime>

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
 * @brief Represente un utilisateur/poste sur le reseau.
 */
class User {
public:
    User();
    User(int id,
         QString name,
         QString ipAddress,
         UserStatus status,
         bool isAdmin,
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

    bool isAdmin() const;
    void setIsAdmin(bool isAdmin);

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
    bool m_isAdmin = false;
    QString m_passwordHash;
    QString m_passwordSalt;
    QDateTime m_createdAt;
};

} // namespace models

#endif // MODELS_USER_H
