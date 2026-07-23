#ifndef MODELS_SERVERELECTION_H
#define MODELS_SERVERELECTION_H

#include <QString>
#include <QDateTime>

namespace models {

/**
 * @brief Rôle courant d'un poste dans l'architecture hybride
 *        (HYBRID_SERVER_FAILOVER.md, section 2).
 */
enum class ServerRole {
    Client,     ///< Se connecte au poste en rôle Server actif.
    Server,     ///< Fait autorité. Les clients s'y connectent, écrivent et lisent via lui.
    TempServer  ///< Client promu temporairement, sert de serveur en attendant le retour du Server officiel.
};

QString serverRoleToString(ServerRole role);
ServerRole serverRoleFromString(const QString &value);

/**
 * @brief État singleton (une seule ligne en base) de l'élection de serveur pour ce poste.
 *
 * Reflète la table ServerElection : rôle courant, epoch de coordination (anti split-brain),
 * et informations sur le serveur actif connu.
 */
class ServerElection
{
public:
    ServerElection();

    ServerRole currentRole() const { return m_currentRole; }
    void setCurrentRole(ServerRole role) { m_currentRole = role; }

    int epoch() const { return m_epoch; }
    void setEpoch(int epoch) { m_epoch = epoch; }

    QString activeServerIp() const { return m_activeServerIp; }
    void setActiveServerIp(const QString &ip) { m_activeServerIp = ip; }

    QString activeServerUuid() const { return m_activeServerUuid; }
    void setActiveServerUuid(const QString &uuid) { m_activeServerUuid = uuid; }

    int priorityWeight() const { return m_priorityWeight; }
    void setPriorityWeight(int weight) { m_priorityWeight = weight; }

    QDateTime lastHeartbeatSeen() const { return m_lastHeartbeatSeen; }
    void setLastHeartbeatSeen(const QDateTime &dt) { m_lastHeartbeatSeen = dt; }

private:
    ServerRole m_currentRole = ServerRole::Client;
    int m_epoch = 0;
    QString m_activeServerIp;
    QString m_activeServerUuid;
    int m_priorityWeight = 100;
    QDateTime m_lastHeartbeatSeen;
};

/**
 * @brief Entrée d'historique des bascules (table ServerElectionLog), pour audit/debug.
 */
class ServerElectionLogEntry
{
public:
    ServerElectionLogEntry();
    ServerElectionLogEntry(int id,
                            const QString &event,
                            int epoch,
                            const QString &machineUuid,
                            const QDateTime &createdAt = QDateTime::currentDateTimeUtc());

    int id() const { return m_id; }
    void setId(int id) { m_id = id; }

    QString event() const { return m_event; }
    void setEvent(const QString &event) { m_event = event; }

    int epoch() const { return m_epoch; }
    void setEpoch(int epoch) { m_epoch = epoch; }

    QString machineUuid() const { return m_machineUuid; }
    void setMachineUuid(const QString &uuid) { m_machineUuid = uuid; }

    QDateTime createdAt() const { return m_createdAt; }
    void setCreatedAt(const QDateTime &dt) { m_createdAt = dt; }

    /// Identifiant global (migration 032), utilise pour diffuser cette
    /// entree entre postes (server_election_event) et l'appliquer de facon
    /// idempotente cote reception (cf. ServerElectionRepository::applyRemoteLogEntry).
    QString logUuid() const { return m_logUuid; }
    void setLogUuid(const QString &uuid) { m_logUuid = uuid; }

private:
    int m_id = -1;
    QString m_event;
    int m_epoch = 0;
    QString m_machineUuid;
    QDateTime m_createdAt;
    QString m_logUuid;
};

// Constantes des événements d'historique (ServerElectionLog.event)
namespace ServerElectionEvent {
inline const QString HeartbeatLost   = QStringLiteral("HEARTBEAT_LOST");
inline const QString TempPromoted    = QStringLiteral("TEMP_PROMOTED");
inline const QString ServerReconciled = QStringLiteral("SERVER_RECONCILED");
inline const QString ServerRestored  = QStringLiteral("SERVER_RESTORED");
}

} // namespace models

#endif // MODELS_SERVERELECTION_H