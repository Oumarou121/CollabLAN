#ifndef MODELS_USER_H
#define MODELS_USER_H

#include <QDateTime>
#include <QString>

namespace models {

/**
 * @brief Represente un utilisateur/poste sur le reseau.
 *
 * Correspond a une ligne de la table `Users` (voir
 * database/Migrations). Le hash de mot de passe est transporte par ce
 * modele pour permettre a UserRepository de le lire/ecrire, mais ne
 * doit jamais etre expose tel quel a l'interface (cf. core::UserManager,
 * qui ne remonte a la QML que le nom d'utilisateur et le role admin).
 */
class User {
public:
    User();
    User(int id,
         QString name,
         QString ipAddress,
         QString status,
         bool isAdmin,
         QString passwordHash,
         QDateTime createdAt = QDateTime());
    ~User();

    int id() const;
    void setId(int id);

    QString name() const;
    void setName(const QString &name);

    QString ipAddress() const;
    void setIpAddress(const QString &ipAddress);

    QString status() const;
    void setStatus(const QString &status);

    bool isAdmin() const;
    void setIsAdmin(bool isAdmin);

    QString passwordHash() const;
    void setPasswordHash(const QString &passwordHash);

    QDateTime createdAt() const;
    void setCreatedAt(const QDateTime &createdAt);

private:
    int m_id = -1;
    QString m_name;
    QString m_ipAddress;
    QString m_status = QStringLiteral("offline");
    bool m_isAdmin = false;
    QString m_passwordHash;
    QDateTime m_createdAt;
};

} // namespace models

#endif // MODELS_USER_H
