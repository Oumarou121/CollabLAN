#ifndef NETWORK_SYNCSERVICE_H
#define NETWORK_SYNCSERVICE_H

#include <QObject>
#include <QString>
#include <QHostAddress>
#include <functional>
#include <vector>

#include "models/SyncLogEntry.h"

namespace database {
class SyncLogRepository;
class ServerElectionRepository;
}

namespace network {

class MessagingServer;
class MessagingService;

/// Entrees du journal de synchronisation qu'un CLIENT identifie comme `userUuid` a le droit de
/// recevoir : les comptes (necessaires a la connexion locale), les groupes dont il est ou a ete
/// membre et leurs mouvements de membres, les messages de ses conversations directes et de ses
/// groupes. Tout le reste est retire, y compris les types d'entree inconnus. Sans utilisateur
/// identifie (poste neuf, personne de connecte) : uniquement les comptes.
std::vector<models::SyncLogEntry> syncEntriesVisibleTo(const std::vector<models::SyncLogEntry> &entries,
                                                       const QString &userUuid);

/// Suite incrementale : parmi toutes les entrees (allEntries), celles visibles par
/// `userUuid` qu'il n'a pas encore recues, sachant que recentEntries sont les
/// entrees ecrites apres son curseur. Comprend l'historique d'un groupe rejoint
/// apres le curseur (ses anciennes entrees n'etaient pas visibles a l'epoque).
std::vector<models::SyncLogEntry> syncEntriesNewlyVisibleTo(const std::vector<models::SyncLogEntry> &allEntries,
                                                            const std::vector<models::SyncLogEntry> &recentEntries,
                                                            const QString &userUuid);

/**
 * @brief Reconciliation post-panne pour l'architecture hybride
 *        (HYBRID_SERVER_FAILOVER.md, section 7).
 *
 * Reutilise le canal WebSocket deja etabli par MessagingServer/MessagingService
 * (les messages "sync_request" / "sync_batch" / "sync_ack" sont distingues des
 * messages de chat par leur champ JSON "type" ; MessagingManager ignore deja
 * tout message dont le type n'est pas "message", cf. core/MessagingManager.cpp).
 *
 * Deux roles possibles pour une meme instance de SyncService selon le role
 * ElectionService du poste au moment de l'appel :
 *  - Cote TEMP_SERVER (repond aux demandes) : ecoute MessagingServer pour un
 *    "sync_request", renvoie via MessagingServer::broadcastMessage() un
 *    "sync_batch" contenant les entrees SyncLog depuis l'epoch de la panne
 *    (section 7.2). Cote le plus simple car MessagingServer ne propose pas
 *    d'envoi cible a un client precis ; en pratique un seul client (le SERVER
 *    officiel qui se reconnecte) est concerne durant la reconciliation.
 *  - Cote SERVER officiel (demande) : apres connexion au TEMP_SERVER via
 *    MessagingService::connectToHost() (a la charge de l'appelant), envoie un
 *    "sync_request" (requestReconciliation()), recoit le "sync_batch", fusionne
 *    via SyncLogRepository::applyBatch() (section 7.2), renvoie un "sync_ack"
 *    (section 7.3) puis emet reconciliationCompleted() : l'appelant peut alors
 *    appeler ElectionService::reclaimAsOfficialServer() (section 7.3-7.4).
 */
class SyncService : public QObject
{
    Q_OBJECT

public:
    explicit SyncService(database::SyncLogRepository *repository, QObject *parent = nullptr);
    ~SyncService() override;

    /// Branche le MessagingServer local (cote TEMP_SERVER, pour repondre aux sync_request).
    void setMessagingServer(MessagingServer *server);

    /// Branche le MessagingService local (cote SERVER officiel, pour demander/recevoir la reconciliation).
    void setMessagingService(MessagingService *service);

    /// Branche le ServerElectionRepository local (optionnel) afin que le
    /// sync_batch echange aussi les entrees ServerElectionLog manquees
    /// (HEARTBEAT_LOST/TEMP_PROMOTED/SERVER_RESTORED/SERVER_RECONCILED dont
    /// le broadcast temps reel n'a pas pu atteindre le pair, cf. Application::
    /// broadcastServerElectionEvent). Sans repository branche, le sync_batch
    /// se comporte comme avant (SyncLogRepository seul).
    void setServerElectionRepository(database::ServerElectionRepository *repository);

    /// Gestionnaire d'autorisations (PermissionManager) : le journal COMPLET n'est envoye qu'a un
    /// pair reconnu comme serveur (reconciliation SERVER <-> TEMP_SERVER) ; un client recoit
    /// seulement ce qui le concerne (syncEntriesVisibleTo).
    void setPermissionManager(QObject *manager);

    /**
     * @brief A appeler par le SERVER officiel une fois connecte au TEMP_SERVER
     *        (MessagingService::connectToHost() deja effectue par l'appelant).
     *        Envoie {"type":"sync_request","from_epoch":fromEpoch,"requester_uuid":localMachineUuid}.
     */
    bool requestReconciliation(int fromEpoch, const QString &localMachineUuid);

    /**
     * @brief Synchronisation incrementale d'un CLIENT avec le serveur connecte :
     *        demande seulement la suite du journal depuis le dernier id recu de ce
     *        serveur (serverKey, typiquement l'empreinte de son certificat) pour
     *        cet utilisateur (le serveur filtre selon l'utilisateur identifie).
     *        Le serveur renvoie "last_id" ; le curseur n'avance que si tout le lot
     *        a pu etre applique (sinon la meme portion sera redemandee).
     */
    bool requestIncrementalSync(const QString &serverKey, const QString &userUuid,
                                const QString &localMachineUuid);

    /// Condition evaluee a chaque lot recu : vraie quand la source n'est pas le
    /// serveur officiel (ce poste est le serveur officiel et reconcilie un
    /// serveur de secours, ou il est client d'un serveur de secours). Les
    /// changements de comptes sensibles sont alors retires du lot
    /// (SyncLogRepository::restrictUserEntries).
    void setUntrustedSourceCheck(std::function<bool()> check);

signals:
    /// Emis cote TEMP_SERVER apres avoir repondu a un sync_request (audit/tests).
    void batchSentToPeer(int entryCount);

    /// Emis cote SERVER officiel une fois le sync_batch recu et fusionne localement.
    /// mergedEntryCount = nombre d'entrees effectivement nouvelles (les doublons ne comptent pas).
    void reconciliationCompleted(int mergedEntryCount);

    /// Emis cote SERVER officiel si le sync_batch recu est illisible (JSON invalide).
    void reconciliationFailed(const QString &reason);

    /// Emis cote TEMP_SERVER a la reception du sync_ack final (informatif : le SERVER
    /// officiel va reprendre la main via ElectionService::reclaimAsOfficialServer()).
    void peerAcknowledgedReconciliation(int mergedEntryCount);

private slots:
    void onServerMessageReceived(const QString &message, const QHostAddress &senderAddress);
    void onClientMessageReceived(const QString &message);

private:
    database::SyncLogRepository *m_repository = nullptr;
    database::ServerElectionRepository *m_electionRepository = nullptr;
    MessagingServer *m_messagingServer = nullptr;
    MessagingService *m_messagingService = nullptr;
    QObject *m_permissionManager = nullptr;
    std::function<bool()> m_untrustedSource;
};

} // namespace network

#endif // NETWORK_SYNCSERVICE_H