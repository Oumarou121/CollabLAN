#ifndef DATABASE_SERVERELECTIONREPOSITORY_H
#define DATABASE_SERVERELECTIONREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <optional>
#include <vector>

#include "models/ServerElection.h"

class QSqlQuery;

namespace database {

/**
 * @brief Accès aux données des tables ServerElection / ServerElectionLog
 *        (HYBRID_SERVER_FAILOVER.md).
 *
 * ServerElection est un singleton (une seule ligne, id = 1) qui reflète le rôle
 * courant du poste local et l'epoch de coordination anti split-brain.
 */
class ServerElectionRepository
{
public:
    explicit ServerElectionRepository(QSqlDatabase database);
    ~ServerElectionRepository();

    /**
     * @brief Récupère l'état courant (crée la ligne singleton par défaut si absente).
     */
    models::ServerElection current() const;

    /**
     * @brief Met à jour l'état complet (upsert sur la ligne singleton id = 1).
     */
    bool save(const models::ServerElection &state);

    /**
     * @brief Met à jour uniquement le rôle et l'epoch (chemin le plus utilisé par ElectionService).
     */
    bool updateRoleAndEpoch(models::ServerRole role, int epoch);

    /**
     * @brief Met à jour les informations du serveur actif connu (IP/UUID) + heartbeat.
     */
    bool updateActiveServer(const QString &ip, const QString &uuid, const QDateTime &heartbeatSeenAt);

    /**
     * @brief Met à jour uniquement le poids de priorité (réglable par l'admin dans SettingsView.qml).
     */
    bool updatePriorityWeight(int weight);

    /**
     * @brief Ajoute une entrée à l'historique des bascules (ServerElectionLog).
     */
    bool appendLogEntry(const QString &event, int epoch, const QString &machineUuid);

    /**
     * @brief Historique des bascules, du plus récent au plus ancien (pour AdminView.qml).
     */
    std::vector<models::ServerElectionLogEntry> logHistory(int limit = 100) const;

    QString lastError() const;

private:
    void ensureSingletonRow() const;
    models::ServerElectionLogEntry logEntryFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SERVERELECTIONREPOSITORY_H
