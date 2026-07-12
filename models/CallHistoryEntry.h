#ifndef MODELS_CALLHISTORYENTRY_H
#define MODELS_CALLHISTORYENTRY_H

#include <QString>
#include <QDateTime>

namespace models {

/// Sens de l'appel du point de vue de CE poste (chaque poste a sa propre
/// base locale : un appel sortant ici est enregistre comme entrant chez
/// le correspondant, dans SA propre base).
enum class CallDirection {
    Outgoing,
    Incoming
};

QString callDirectionToString(CallDirection direction);
CallDirection callDirectionFromString(const QString &value);

/// Statut final d'un appel termine (ou "InProgress" tant qu'il est en
/// cours). Deduit par core::CallHistoryManager a partir des transitions
/// d'etat de network::VoiceService et de la raison de fin d'appel, faute
/// de signal explicite "refuse"/"manque" dans le protocole de
/// signalisation actuel (voir core::CallHistoryManager pour le detail de
/// cette deduction).
enum class CallStatus {
    InProgress,
    Completed,  ///< La session audio a ete etablie au moins une fois.
    Missed,     ///< Appel entrant jamais decroche (l'appelant a raccroche ou timeout).
    Rejected,   ///< Appel refuse explicitement par un des deux postes avant connexion.
    Cancelled,  ///< Appel sortant annule par l'appelant avant reponse.
    Failed      ///< Echec technique (signalisation perdue, erreur ICE/DTLS...).
};

QString callStatusToString(CallStatus status);
CallStatus callStatusFromString(const QString &value);

/**
 * @brief Represente une ligne de l'historique des appels vocaux (table
 * CallHistory), du point de vue de ce poste.
 *
 * Comme pour models::Transfer (voir migration 012), localUserId est un
 * simple int avec -1 comme sentinelle "inconnu" plutot qu'un
 * std::optional : aucun utilisateur local ne peut etre authentifie au
 * moment de l'appel (ex. appel recu avant login) sans que cela empeche
 * l'enregistrement de l'historique.
 */
class CallHistoryEntry {
public:
    CallHistoryEntry();

    int id() const { return m_id; }
    void setId(int id) { m_id = id; }

    /// Identifiant technique correlant demarrage/fin d'un meme appel cote
    /// network::VoiceService (VoiceService::m_currentCallId). Non utilise
    /// pour retrouver l'enregistrement actif (VoiceService l'efface avant
    /// meme d'emettre callEnded() - voir CallHistoryManager), conserve
    /// uniquement a titre de correlation/diagnostic.
    QString callUuid() const { return m_callUuid; }
    void setCallUuid(const QString &callUuid) { m_callUuid = callUuid; }

    /// Utilisateur local connecte pendant l'appel, -1 si inconnu/absent.
    int localUserId() const { return m_localUserId; }
    void setLocalUserId(int localUserId) { m_localUserId = localUserId; }

    CallDirection direction() const { return m_direction; }
    void setDirection(CallDirection direction) { m_direction = direction; }

    QString peerAddress() const { return m_peerAddress; }
    void setPeerAddress(const QString &peerAddress) { m_peerAddress = peerAddress; }

    /// Nom affichable du correspondant au moment de l'appel (resolu via
    /// network::DiscoveryService si le poste etait alors decouvert),
    /// fige a cet instant : un renommage/deconnexion ulterieur du
    /// correspondant ne modifie pas les entrees d'historique deja
    /// enregistrees. Vide si non resolu (adresse seule affichee dans l'UI).
    QString peerName() const { return m_peerName; }
    void setPeerName(const QString &peerName) { m_peerName = peerName; }

    CallStatus status() const { return m_status; }
    void setStatus(CallStatus status) { m_status = status; }

    QDateTime startedAt() const { return m_startedAt; }
    void setStartedAt(const QDateTime &startedAt) { m_startedAt = startedAt; }

    /// Invalide (QDateTime()) si la session audio n'a jamais ete etablie.
    QDateTime connectedAt() const { return m_connectedAt; }
    void setConnectedAt(const QDateTime &connectedAt) { m_connectedAt = connectedAt; }

    /// Invalide tant que l'appel est en cours (status == InProgress).
    QDateTime endedAt() const { return m_endedAt; }
    void setEndedAt(const QDateTime &endedAt) { m_endedAt = endedAt; }

    /// Duree en secondes entre connectedAt et endedAt, -1 si non applicable
    /// (appel jamais connecte ou toujours en cours).
    int durationSeconds() const { return m_durationSeconds; }
    void setDurationSeconds(int durationSeconds) { m_durationSeconds = durationSeconds; }

private:
    int m_id = -1;
    QString m_callUuid;
    int m_localUserId = -1;
    CallDirection m_direction = CallDirection::Outgoing;
    QString m_peerAddress;
    QString m_peerName;
    CallStatus m_status = CallStatus::InProgress;
    QDateTime m_startedAt;
    QDateTime m_connectedAt;
    QDateTime m_endedAt;
    int m_durationSeconds = -1;
};

} // namespace models

#endif // MODELS_CALLHISTORYENTRY_H
