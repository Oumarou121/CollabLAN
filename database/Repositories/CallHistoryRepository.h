#ifndef DATABASE_CALLHISTORYREPOSITORY_H
#define DATABASE_CALLHISTORYREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <QDateTime>
#include <optional>
#include <vector>

#include "models/CallHistoryEntry.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees de la table CallHistory.
 *
 * Couche fine au-dessus de QSqlDatabase (requetes preparees, aucune
 * logique reseau/etat d'appel), suivant exactement le meme patron que
 * database::TransferRepository : core::CallHistoryManager s'en sert pour
 * enregistrer le demarrage d'un appel puis mettre a jour sa connexion/fin.
 */
class CallHistoryRepository {
public:
    explicit CallHistoryRepository(QSqlDatabase database);
    ~CallHistoryRepository();

    /// Insere une nouvelle entree (statut initial : in_progress).
    /// @return l'id genere, ou -1 en cas d'echec (voir lastError()).
    int create(const models::CallHistoryEntry &entry);

    std::optional<models::CallHistoryEntry> findById(int id) const;

    /// Historique complet (tous utilisateurs locaux confondus), le plus
    /// recent en premier.
    std::vector<models::CallHistoryEntry> findAll(int limit = 200, int offset = 0) const;

    /// Historique des appels (emis ou recus) d'un utilisateur local donne.
    std::vector<models::CallHistoryEntry> findByUser(int userId, int limit = 200, int offset = 0) const;

    /// Renseigne l'horodatage de connexion (session audio etablie), sans
    /// toucher au statut (qui reste in_progress jusqu'a la fin de l'appel).
    bool markConnected(int id, const QDateTime &connectedAt);

    /// Cloture l'entree : statut final + horodatage de fin + duree
    /// (calculee par l'appelant, cf. core::CallHistoryManager).
    bool markEnded(int id, models::CallStatus status, const QDateTime &endedAt,
                   std::optional<int> durationSeconds);

    bool remove(int id);

    QString lastError() const;

private:
    models::CallHistoryEntry entryFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_CALLHISTORYREPOSITORY_H
