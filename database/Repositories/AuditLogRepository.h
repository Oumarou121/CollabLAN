#ifndef DATABASE_AUDITLOGREPOSITORY_H
#define DATABASE_AUDITLOGREPOSITORY_H

#include <QVector>
#include <QString>
#include <QDateTime>
#include <optional>

#include "models/AuditLog.h"

class QSqlQuery;

namespace database {

class DatabaseManager;

/// Criteres de filtrage pour la consultation du journal d'audit
/// (issue #63). Tous les champs sont optionnels ; un champ absent
/// n'ajoute aucune restriction sur la requete.
struct AuditLogFilter {
    std::optional<QString> eventType;
    std::optional<qint64> userId;
    std::optional<QDateTime> from; ///< Entrees a partir de cet horodatage (inclus).
    std::optional<QDateTime> to;   ///< Entrees jusqu'a cet horodatage (inclus).
    int limit = 200;
    int offset = 0;
};

/**
 * @brief Acces aux donnees de la table AuditLogs (issue #63).
 *
 * Persiste les entrees d'audit enregistrees par core::AuditManager et
 * permet leur consultation filtree (par type d'evenement, par date, par
 * utilisateur), y compris apres redemarrage de l'application puisque la
 * table AuditLogs est stockee dans la base SQLite persistante geree par
 * DatabaseManager.
 */
class AuditLogRepository
{
public:
    explicit AuditLogRepository(DatabaseManager *dbManager);
    ~AuditLogRepository();

    /// Insere une nouvelle entree d'audit. Retourne l'entree avec son id
    /// assigne par la base, ou std::nullopt en cas d'echec.
    std::optional<models::AuditLog> insert(const models::AuditLog &entry);

    /// Recupere les entrees d'audit correspondant au filtre, les plus
    /// recentes en premier.
    QVector<models::AuditLog> find(const AuditLogFilter &filter = {});

    /// Recupere une entree par son identifiant.
    std::optional<models::AuditLog> getById(qint64 id);

    /// Nombre total d'entrees correspondant au filtre (ignore limit/offset),
    /// utile pour la pagination cote UI.
    int count(const AuditLogFilter &filter = {});

private:
    static models::AuditLog fromRecord(const QSqlQuery &query);

    DatabaseManager *m_dbManager = nullptr;
};

} // namespace database

#endif // DATABASE_AUDITLOGREPOSITORY_H
