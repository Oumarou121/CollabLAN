#ifndef DATABASE_USERREPOSITORY_H
#define DATABASE_USERREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <QVariant>
#include <optional>

#include "User.h"

namespace database {

/**
 * @brief Acces aux donnees de la table Users.
 *
 * Reste une couche fine au-dessus de QSqlDatabase : aucune logique
 * metier (verification de mot de passe, regles d'autorisation...) n'y
 * est presente, celle-ci vit dans core::UserManager.
 */
class UserRepository {
public:
    explicit UserRepository(QSqlDatabase database);
    ~UserRepository();

    // Recherche par nom d'utilisateur (identifiant de connexion), qui
    // est contraint unique par la migration 002_add_user_password.sql.
    std::optional<models::User> findByName(const QString &name) const;
    std::optional<models::User> findById(int id) const;

    // Insere un nouvel utilisateur ; renseigne user.id() sur succes.
    bool create(models::User &user);

    bool updateStatus(int userId, const QString &status);

    QString lastError() const;

private:
    std::optional<models::User> findOneWhere(const QString &whereClause, const QVariant &boundValue) const;

    QSqlDatabase m_database;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_USERREPOSITORY_H
