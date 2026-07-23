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
     *
     * Genere un log_uuid pour cette entree (migration 032) et le renvoie via
     * outLogUuid si non nul, afin que l'appelant (Application::) puisse
     * diffuser exactement la meme entree aux autres postes
     * (server_election_event) -- sans quoi chaque machine ne voit que sa
     * propre vue locale de l'historique des bascules.
     */
    bool appendLogEntry(const QString &event, int epoch, const QString &machineUuid,
                        QString *outLogUuid = nullptr);

    /**
     * @brief Applique une entree d'historique recue d'un autre poste
     *        (Application::handleIncomingPayload, type "server_election_event").
     *
     * Idempotent : une entree deja connue (meme log_uuid) est ignoree
     * silencieusement (comptee comme un succes), pour supporter les rejeux
     * (reconnexion, relais en etoile).
     */
    bool applyRemoteLogEntry(const models::ServerElectionLogEntry &entry);

    /**
     * @brief Aligne l'epoch local sur celui d'un pair si celui-ci est plus
     *        recent (jamais de retour en arriere), sans toucher a
     *        current_role : le role de CE poste reste determine
     *        localement par son propre ElectionService (heartbeats /
     *        election), jamais copie depuis un pair.
     */
    bool bumpEpochIfNewer(int remoteEpoch);

    /**
     * @brief Historique des bascules, du plus récent au plus ancien (pour AdminView.qml).
     */
    std::vector<models::ServerElectionLogEntry> logHistory(int limit = 100) const;

    /**
     * @brief Entrées ServerElectionLog dont l'epoch est >= fromEpoch, triées
     *        du plus ancien au plus récent (ordre chronologique, contrairement
     *        à logHistory()).
     *
     * Utilisé par SyncService lors de la réconciliation post-panne pour
     * rattraper les entrées qui n'ont jamais pu être diffusées en temps réel
     * (ex : HEARTBEAT_LOST/TEMP_PROMOTED émis alors que le pair n'était pas
     * encore reconnecté, cf. HYBRID_SERVER_FAILOVER.md section 7.2) — le même
     * principe que SyncLogRepository::entriesSinceEpoch pour les autres
     * tables, ServerElectionLog n'étant jusqu'ici couvert par aucun mécanisme
     * de rattrapage.
     */
    std::vector<models::ServerElectionLogEntry> entriesSinceEpoch(int fromEpoch) const;

    QString lastError() const;

private:
    void ensureSingletonRow() const;
    models::ServerElectionLogEntry logEntryFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SERVERELECTIONREPOSITORY_H