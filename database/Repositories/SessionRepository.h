#ifndef DATABASE_SESSIONREPOSITORY_H
#define DATABASE_SESSIONREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <optional>

#include "models/UserSession.h"

class QSqlQuery;

namespace database {

/**
 * @brief Accès aux données de la table UserSessions (migration #026).
 *
 * Gère la persistance des jetons de session utilisés par
 * core::UserManager pour la fonctionnalité "Se souvenir de moi"
 * (auto-login silencieux au démarrage). Seul le hash SHA-256 du jeton
 * transite ici : cette classe ne connaît jamais le jeton en clair.
 *
 * Table volontairement locale (non synchronisée entre postes, cf.
 * commentaire de la migration 026).
 */
class SessionRepository
{
public:
    explicit SessionRepository(QSqlDatabase database);
    ~SessionRepository();

    /**
     * @brief Insère une nouvelle session pour userId.
     * @return l'id généré, ou -1 en cas d'échec.
     */
    int create(int userId,
               const QString &tokenHash,
               const QDateTime &expiresAt,
               const QString &deviceLabel = QString());

    /**
     * @brief Recherche une session par le hash du jeton fourni.
     *        Ne filtre pas sur l'expiration : c'est à l'appelant
     *        (core::UserManager) de vérifier models::UserSession::isExpired().
     */
    std::optional<models::UserSession> findByTokenHash(const QString &tokenHash) const;

    /**
     * @brief Supprime une session par son id (ex: fin de vie normale).
     */
    bool remove(int id);

    /**
     * @brief Supprime une session par le hash de son jeton.
     */
    bool removeByTokenHash(const QString &tokenHash);

    /**
     * @brief Supprime toutes les sessions d'un utilisateur (ex: logout,
     *        suppression de compte, changement de mot de passe).
     */
    bool removeAllForUser(int userId);

    /**
     * @brief Supprime toutes les sessions expirées (nettoyage périodique,
     *        appelé par ex. à l'ouverture de la base).
     */
    bool removeExpired();

    QString lastError() const;

private:
    models::UserSession sessionFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SESSIONREPOSITORY_H
