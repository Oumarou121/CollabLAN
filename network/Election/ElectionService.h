#ifndef NETWORK_ELECTIONSERVICE_H
#define NETWORK_ELECTIONSERVICE_H

#include <QObject>
#include <QString>
#include <QDateTime>
#include <QHostAddress>

#include "models/ServerElection.h"

class QUdpSocket;
class QTimer;

namespace network {

/**
 * @brief Election de serveur temporaire et detection de panne pour l'architecture
 *        hybride a bascule automatique (HYBRID_SERVER_FAILOVER.md, sections 4 a 8).
 *
 * Principe (paquets UDP JSON, marques "collablan.election" pour ignorer tout
 * trafic non lie a CollabLAN sur ce port) :
 *  - Le poste en role Server ou TempServer diffuse un heartbeat toutes les
 *    heartbeatIntervalMs() (3000 ms par defaut, cf. doc section 4).
 *  - Chaque poste surveille le dernier heartbeat recu ; au-dela de
 *    heartbeatTimeoutMs() (15000 ms par defaut) sans nouvelle, une election
 *    est declenchee (section 5).
 *  - L'election est deterministe : priority_weight le plus bas gagne, puis
 *    machine_uuid comme tie-breaker par ordre lexical croissant.
 *  - Le gagnant s'auto-promeut TempServer, incremente l'epoch et diffuse
 *    server_promoted(epoch, uuid, temporary=true).
 *  - Regle anti split-brain (section 7) : tout server_promoted avec un epoch
 *    inferieur ou egal a l'epoch local est ignore.
 *
 * Ce service ne touche pas la base de donnees : il expose son etat courant
 * (role(), epoch()...) et des signaux (roleChanged, serverPromoted...) que
 * l'appelant (Application/ServerElectionRepository) peut utiliser pour
 * persister l'etat et pour piloter MessagingServer::start()/stop().
 */
class ElectionService : public QObject
{
    Q_OBJECT
    // Proprietes exposees a l'UI (SettingsView.qml section 9 etape 5) :
    // roleLabel/epoch/activeServerUuid en lecture seule (pilotees par le
    // protocole reseau), priorityWeight/heartbeatTimeoutMs en lecture-
    // ecriture (reglables par l'admin).
    Q_PROPERTY(QString roleLabel READ roleLabel NOTIFY roleLabelChanged)
    Q_PROPERTY(int epoch READ epoch NOTIFY epochChanged)
    Q_PROPERTY(QString activeServerUuid READ activeServerUuid NOTIFY activeServerUuidChanged)
    Q_PROPERTY(int priorityWeight READ priorityWeight WRITE setPriorityWeight NOTIFY priorityWeightChanged)
    Q_PROPERTY(int heartbeatTimeoutMs READ heartbeatTimeoutMs WRITE setHeartbeatTimeoutMs NOTIFY heartbeatTimeoutMsChanged)

public:
    explicit ElectionService(QObject *parent = nullptr);
    ~ElectionService() override;

    /// Demarre l'ecoute + le heartbeat/l'election. Ne fait rien si deja demarre.
    bool start();

    /// Arrete l'ecoute et toute activite periodique.
    void stop();

    bool isRunning() const;

    /// Identifiant unique de ce poste (genere aleatoirement si non fourni).
    QString localMachineUuid() const;
    void setLocalMachineUuid(const QString &uuid);

    /// Poids de priorite pour devenir TempServer : plus petit = plus prioritaire
    /// (reglable par l'admin, section 5). 100 par defaut.
    int priorityWeight() const;
    void setPriorityWeight(int weight);

    /// Port UDP pour heartbeat/election (45455 par defaut, distinct du port
    /// 45454 utilise par DiscoveryService).
    quint16 port() const;
    void setPort(quint16 port);

    /// Port TCP sur lequel MessagingServer de CE poste écoute réellement
    /// quand il est Server/TempServer (typiquement --port en CLI, cf.
    /// app/main.cpp). Diffusé dans heartbeat/server_promoted afin que les
    /// autres postes sachent sur quel port se connecter : sans cela,
    /// Application supposait à tort que le pair actif écoutait sur son
    /// PROPRE messagingServerPort, ce qui casse silencieusement dès que
    /// --port diffère d'un poste à l'autre.
    quint16 messagingPort() const;
    void setMessagingPort(quint16 port);

    /// Intervalle entre deux heartbeats emis quand ce poste est Server/TempServer.
    int heartbeatIntervalMs() const;
    void setHeartbeatIntervalMs(int ms);

    /// Delai sans heartbeat recu au-dela duquel une election est declenchee.
    int heartbeatTimeoutMs() const;
    void setHeartbeatTimeoutMs(int ms);

    /// Fenetre d'attente des candidatures avant de determiner le gagnant de l'election.
    int electionWindowMs() const;
    void setElectionWindowMs(int ms);

    /// Definit le role initial de ce poste (typiquement lu depuis
    /// ServerElectionRepository::current() par l'appelant avant start()).
    void setInitialState(models::ServerRole role, int epoch);

    models::ServerRole role() const;
    /// Libelle textuel de role() (serverRoleToString), pour affichage direct
    /// en QML sans avoir a exposer l'enum ServerRole lui-meme.
    QString roleLabel() const;
    int epoch() const;
    QString activeServerUuid() const;
    QHostAddress activeServerAddress() const;

    /// Port TCP de messagerie du serveur actif courant (Server ou TempServer),
    /// tel qu'annoncé par son propre setMessagingPort() dans heartbeat/
    /// server_promoted. À utiliser à la place de son propre messagingServerPort
    /// pour se connecter à lui (voir messagingPort()).
    quint16 activeServerPort() const;

    /**
     * @brief A appeler par le poste officiel Server une fois la reconciliation
     *        terminee (sync_ack recu, cf. section 7.3) pour reprendre la main
     *        aupres du TempServer courant. Incremente l'epoch et diffuse
     *        server_promoted(epoch, localMachineUuid(), temporary=false).
     */
    void reclaimAsOfficialServer();

signals:
    void started();
    void stopped();

    /// Emis a chaque changement de role de ce poste.
    void roleChanged(models::ServerRole newRole, models::ServerRole previousRole);

    /// Emis quand plus aucun heartbeat n'est recu depuis heartbeatTimeoutMs().
    void heartbeatLost();

    /// Emis quand une election demarre localement (candidature envoyee).
    void electionStarted();

    /// Emis pour tout message server_promoted valide (epoch > epoch local),
    /// que ce poste en soit l'emetteur ou non.
    void serverPromoted(int epoch, const QString &machineUuid, bool temporary);

    /// Emis quand un server_promoted perime (epoch <= epoch local) est recu et ignore
    /// (utile pour les tests/l'audit de la regle anti split-brain, section 7).
    void splitBrainAttemptIgnored(int epoch, const QString &machineUuid);

    /// Emis lorsque ce poste (role Server) detecte pour la premiere fois qu'un
    /// TempServer a pris le relais pendant son absence : le point d'accroche
    /// pour declencher la reconciliation via le futur SyncService (section 7.1).
    void reconciliationRequired(const QString &tempServerUuid);

    // Signaux NOTIFY des Q_PROPERTY ci-dessus, pour le binding QML reactif
    // (SettingsView.qml / indicateur Main.qml, section 9 etape 5).
    void roleLabelChanged();
    void epochChanged();
    void activeServerUuidChanged();
    void priorityWeightChanged();
    void heartbeatTimeoutMsChanged();

private slots:
    void readPendingDatagrams();
    void sendHeartbeat();
    void checkHeartbeatTimeout();
    void concludeElection();

private:
    struct Candidate {
        QString machineUuid;
        int priorityWeight = 100;
    };

    void handlePacket(const QByteArray &data, const QHostAddress &senderAddress);
    void broadcastPacket(const QByteArray &data);
    void startElection();
    void applyRole(models::ServerRole newRole);
    void enterServerRole(int newEpoch, bool temporary);
    bool isBetterCandidate(const Candidate &a, const Candidate &b) const;

    QUdpSocket *m_socket = nullptr;
    QTimer *m_heartbeatTimer = nullptr;
    QTimer *m_timeoutTimer = nullptr;
    QTimer *m_electionWindowTimer = nullptr;

    QString m_localMachineUuid;
    int m_priorityWeight = 100;

    quint16 m_port = 45455;
    quint16 m_messagingPort = 0;
    int m_heartbeatIntervalMs = 3000;
    int m_heartbeatTimeoutMs = 15000;
    int m_electionWindowMs = 2000;

    bool m_running = false;
    bool m_electionInProgress = false;

    models::ServerRole m_role = models::ServerRole::Client;
    int m_epoch = 0;
    QString m_activeServerUuid;
    QHostAddress m_activeServerAddress;
    quint16 m_activeServerPort = 0;
    qint64 m_lastHeartbeatSeenMs = 0;
    bool m_heartbeatEverSeen = false;

    QList<Candidate> m_candidates;
};

} // namespace network

#endif // NETWORK_ELECTIONSERVICE_H
