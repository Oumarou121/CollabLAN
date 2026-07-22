#ifndef NETWORK_VOICESERVICE_H
#define NETWORK_VOICESERVICE_H

#include <QObject>
#include <QHostAddress>
#include <QString>
#include <atomic>
#include <memory>

#include "VoiceSignalingChannel.h"

namespace rtc {
class PeerConnection;
class Track;
} // namespace rtc

namespace network {

class SecurityService;
class VoiceAudioIO;

/// Etat d'un appel vocal, expose a l'UI (QML) pour piloter l'affichage.
enum class CallState {
    Idle,          ///< Aucun appel en cours.
    Calling,       ///< Offre envoyee, en attente de reponse (sortant).
    Ringing,       ///< Offre recue, en attente de decision utilisateur (entrant).
    Connecting,    ///< Reponse echangee, negociation ICE/DTLS en cours.
    Connected,     ///< Flux audio etabli dans les deux sens.
    Ending
};

/**
 * @brief Appels vocaux peer-to-peer via WebRTC (issues #60 et #61).
 *
 * VoiceService orchestre :
 *  - la signalisation (VoiceSignalingChannel) : echange d'offre/reponse SDP
 *    et de candidats ICE entre les deux postes (#60) ;
 *  - la session media (rtc::PeerConnection de libdatachannel) : negociation
 *    DTLS-SRTP et transport RTP de l'audio (#61) ;
 *  - la capture/lecture audio locale (VoiceAudioIO), branchee sur la piste
 *    audio de la PeerConnection une fois la session etablie.
 *
 * Aucun serveur STUN/TURN externe n'est configure : CollabLAN fonctionne
 * en LAN, les candidats ICE "host" (adresses locales) suffisent a etablir
 * la connexion directement entre les deux postes.
 */
class VoiceService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(network::CallState state READ state NOTIFY stateChanged)

public:
    explicit VoiceService(SecurityService *securityService, QObject *parent = nullptr);
    ~VoiceService() override;

    /// Demarre l'ecoute des appels entrants (a appeler une fois au demarrage
    /// de l'application, comme MessagingServer::start()).
    bool startListening(quint16 signalingPort = 12347);
    void setPermissionManager(QObject *manager);
    void stopListening();

    /// Initie un appel sortant vers le poste distant.
    bool call(const QHostAddress &peerAddress, quint16 signalingPort = 12347);

    /// Port de signalisation par défaut utilisé par startListening() et call().
    static quint16 defaultSignalingPort();

    /// Accepte l'appel entrant actuellement en sonnerie (etat Ringing).
    void acceptCall();

    /// Refuse l'appel entrant actuellement en sonnerie, ou raccroche un
    /// appel en cours quel que soit son etat.
    void hangUp();

    /// Coupe/reactive le microphone local sans interrompre l'appel.
    void setMuted(bool muted);
    bool isMuted() const;

    CallState state() const { return m_state; }

signals:
    void stateChanged(network::CallState state);

    /// Emis a la reception d'une offre entrante, avant que l'appel ne passe
    /// a l'etat Ringing, pour que l'UI puisse afficher l'identite de
    /// l'appelant.
    void incomingCall(const QHostAddress &callerAddress);

    /// Emis juste apres qu'un appel sortant ait reellement demarre (offre
    /// de signalisation envoyee avec succes, etat passe a Calling),
    /// symetrique de incomingCall() ci-dessus. N'est PAS emis si call()
    /// echoue avant ce point (appel deja en cours, connexion de
    /// signalisation impossible) : dans ce cas aucune tentative n'a
    /// vraiment eu lieu, rien a journaliser (voir core::CallHistoryManager).
    void outgoingCallStarted(const QHostAddress &peerAddress);

    /// Emis lorsque la session audio est pleinement etablie dans les deux
    /// sens (critere d'acceptation de l'issue #61).
    void callConnected();

    void callEnded(const QString &reason);
    void errorOccurred(const QString &message);

private slots:
    void onSignalingMessage(const network::SignalingMessage &message, const QHostAddress &peerAddress);
    void onSignalingPeerDisconnected();
    void onSignalingPeerConnected();
    void onCapturedAudioFrame(const QByteArray &pcm16);

private:
    void setState(CallState newState);
    void createPeerConnection();
    void teardownSession(const QString &reason);
    void wireTrackCallbacks();

    SecurityService *m_securityService = nullptr;
    std::unique_ptr<VoiceSignalingChannel> m_signaling;
    std::unique_ptr<VoiceAudioIO> m_audioIo;

    std::shared_ptr<rtc::PeerConnection> m_peerConnection;
    std::shared_ptr<rtc::Track> m_audioTrack;

    CallState m_state = CallState::Idle;
    QString m_currentCallId;
    QHostAddress m_peerAddress;
    quint16 m_peerSignalingPort = 0;
    bool m_isCaller = false;

    // Compteurs RTP pour le flux sortant. Mis a jour uniquement depuis le
    // thread de VoiceService (slot connecte a VoiceAudioIO::capturedFrame,
    // connexion Qt::AutoConnection -> execution sur ce thread) ; std::atomic
    // conserve par prudence en cas d'evolution future vers un traitement
    // audio sur thread dedie.
    std::atomic<std::uint16_t> m_rtpSequence { 0 };
    std::atomic<std::uint32_t> m_rtpTimestamp { 0 };
    std::uint32_t m_rtpSsrc = 0;
};

} // namespace network

#endif // NETWORK_VOICESERVICE_H
