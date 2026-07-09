#ifndef DATABASE_USERREPOSITORY_H
#define DATABASE_USERREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <optional>
#include <vector>

#include "models/User.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees de la table Users (CRUD complet).
 *
 * Toutes les requetes sont preparees (QSqlQuery::prepare) afin d'eviter
 * toute injection SQL.
 */
class UserRepository {
public:
    explicit UserRepository(QSqlDatabase database);
    ~UserRepository();

    /**
     * @brief Insere un nouvel utilisateur en base.
     * @return l'id genere, ou -1 en cas d'echec (voir lastError()).
     */
    int create(const models::User &user);

    /**
     * @brief Recharge un utilisateur par son id.
     */
    std::optional<models::User> read(int id) const;

    /**
     * @brief Met a jour l'ensemble des champs d'un utilisateur existant.
     */
    bool update(const models::User &user);

    /**
     * @brief Supprime un utilisateur par son id.
     */
    bool remove(int id);

    // Alias explicites pour lisibilite (Create/Read/Update/Delete).
    std::optional<models::User> findById(int id) const;
    std::optional<models::User> findByName(const QString &name) const;
    bool existsByName(const QString &name) const;
    std::vector<models::User> findAll() const;

    /**
     * @brief Met a jour uniquement le statut (en ligne/hors ligne/absent).
     */
    bool updateStatus(int id, models::UserStatus status);

    QString lastError() const;

private:
    models::User userFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_USERREPOSITORY_H
