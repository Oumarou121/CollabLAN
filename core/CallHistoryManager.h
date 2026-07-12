#ifndef CORE_CALLHISTORYMANAGER_H
#define CORE_CALLHISTORYMANAGER_H

#include <QObject>
#include <QHostAddress>
#include <QString>
#include <vector>

#include "models/CallHistoryEntry.h"
#include "database/Repositories/CallHistoryRepository.h"
#include "Voice/VoiceService.h"

namespace database {
class DatabaseManager;
}

namespace network {
class DiscoveryService;
}

namespace core {

class UserManager;

/**
 * @brief Relie network::VoiceService a database::CallHistoryRepository :
 * persiste chaque appel (emis ou recu) et son issue finale, suivant le
 * meme patron que TransferManager pour les transferts de fichiers
 * (demarrage -> enregistrement immediat en base, puis mise a jour du
 * statut a la fin).
 *
 * VoiceService ne gere qu'un seul appel a la fois (call() refuse tout
 * nouvel appel tant que l'etat n'est pas Idle) : contrairement a
 * TransferManager, aucune cle de correlation n'est donc necessaire entre
 * plusieurs appels concurrents - un unique "appel actif" suffit.
 *
 * Deduction du statut final : le protocole de signalisation actuel ne
 * distingue pas explicitement un appel "refuse" d'un appel "manque" ou
 * "annule" (VoiceService::hangUp() couvre les trois : raccrocher un appel
 * en cours, refuser un appel entrant en sonnerie, ou annuler un appel
 * sortant pas encore repondu - toujours avec la meme raison
 * "local-hangup"). CallHistoryManager infere donc le statut a partir de
 * trois informations disponibles : le sens de l'appel, si la session
 * audio a deja ete etablie au moins une fois, et le dernier etat actif
 * observe juste avant la bascule a Idle (Ringing/Calling/Connecting) :
 *
 *  - session etablie au moins une fois -> Completed (avec duree)
 *  - sortant, jamais connecte, raccroche localement      -> Cancelled
 *  - sortant, jamais connecte, raccroche par le distant   -> Rejected
 *  - sortant, jamais connecte, autre raison (reseau...)   -> Failed
 *  - entrant, encore en sonnerie, refuse localement        -> Rejected
 *  - entrant, encore en sonnerie, raccroche par l'appelant -> Missed
 *  - entrant, deja en Connecting (accepte) mais jamais connecte -> Failed
 */
class CallHistoryManager : public QObject
{
    Q_OBJECT

public:
    explicit CallHistoryManager(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~CallHistoryManager() override;

    /// Configure le service vocal a observer. Doit etre appele une fois
    /// VoiceService instancie (voir Application::initialize()).
    void setVoiceService(network::VoiceService *voiceService);

    /// Permet de resoudre local_user_id (utilisateur local connecte au
    /// moment de l'appel). Optionnel : reste -1 (inconnu) si non fourni.
    void setUserManager(UserManager *userManager);

    /// Permet de resoudre peer_name a partir de l'adresse du correspondant
    /// (nom annonce par network::DiscoveryService, s'il est alors visible
    /// sur le reseau). Optionnel : peer_name reste vide sinon.
    void setDiscoveryService(network::DiscoveryService *discoveryService);

    /// Historique complet (tous utilisateurs locaux), le plus recent en premier.
    std::vector<models::CallHistoryEntry> allCalls(int limit = 200, int offset = 0) const;

    /// Historique des appels de l'utilisateur local donne.
    std::vector<models::CallHistoryEntry> userCalls(int userId, int limit = 200, int offset = 0) const;

signals:
    /// Emis des qu'un appel (entrant ou sortant) est enregistre en base,
    /// au tout debut de la tentative.
    void callRecorded(int callHistoryId, const models::CallHistoryEntry &entry);

    /// Emis quand une entree deja enregistree est finalisee (fin d'appel).
    void callFinalized(int callHistoryId, models::CallStatus status);

private slots:
    void onOutgoingCallStarted(const QHostAddress &peerAddress);
    void onIncomingCall(const QHostAddress &peerAddress);
    void onStateChanged(network::CallState state);
    void onCallEnded(const QString &reason);

private:
    QString resolvePeerName(const QHostAddress &peerAddress) const;
    void beginEntry(network::CallState triggerState, models::CallDirection direction,
                     const QHostAddress &peerAddress);
    void resetActiveState();

    database::CallHistoryRepository m_repository;
    network::VoiceService *m_voiceService = nullptr;
    UserManager *m_userManager = nullptr;
    network::DiscoveryService *m_discoveryService = nullptr;

    // Etat de l'appel actif en cours d'enregistrement (un seul a la fois,
    // voir la note de classe ci-dessus). m_activeId <= 0 signifie aucun
    // appel actif suivi.
    int m_activeId = -1;
    models::CallDirection m_activeDirection = models::CallDirection::Outgoing;
    bool m_activeReachedConnected = false;
    QDateTime m_activeConnectedAt;
    network::CallState m_activeLastState = network::CallState::Idle;
};

} // namespace core

#endif // CORE_CALLHISTORYMANAGER_H
