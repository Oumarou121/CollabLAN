#ifndef NETWORK_VOICESERVICE_H
#define NETWORK_VOICESERVICE_H

#include <QObject>
#include <QHostAddress>
#include <QImage>
#include <QList>
#include <QPair>
#include <QTimer>
#include <QString>
#include <map>
#include <memory>

#include "VoiceSignalingChannel.h"

namespace rtc {
class DataChannel;
} // namespace rtc

namespace network {

class SecurityService;
class VoiceAudioIO;
class VoiceMixer;
class OpusVoiceEncoder;
class ScreenTileEncoder;
class ScreenCanvas;

/// Etat d'un appel vocal, expose a l'UI (QML) pour piloter l'affichage.
enum class CallState {
    Idle,          ///< Aucun appel en cours.
    Calling,       ///< Invitations envoyees, personne n'a encore repondu (sortant).
    Ringing,       ///< Invitation recue, en attente de decision utilisateur (entrant).
    Connecting,    ///< Reponse echangee, negociation ICE/DTLS en cours.
    Connected,     ///< Au moins un participant relie, flux audio etabli.
    Ending
};

/// Participant d'un appel, vu de ce poste (vous n'en faites pas partie).
struct VoiceParticipant {
    QHostAddress address;
    quint16 port = 0;
    /// "invited"    invitation envoyee, sonnerie chez lui ;
    /// "inviting"   il vous invite (sonnerie ici) ;
    /// "connecting" reponse donnee, audio en cours d'etablissement ;
    /// "joined"     dans l'appel.
    QString status;
    bool muted = false;
    bool speaking = false;
};

/**
 * @brief Appels vocaux peer-to-peer via WebRTC (issues #60 et #61), a deux
 * ou en groupe (4 personnes au plus, vous compris).
 *
 * Un appel de groupe relie chaque participant directement a chacun des
 * autres (maillage complet, sans serveur intermediaire) : chaque liaison a sa
 * propre session media (rtc::PeerConnection de libdatachannel) et sa liaison
 * de signalisation (VoiceSignalingChannel). L'appel porte un identifiant
 * commun (callId) :
 *  - inviter : offre « group » envoyee a la personne, qui sonne ;
 *  - quand elle a rejoint, celui qui l'a invitee lui transmet les autres
 *    participants (« call-roster ») ; elle leur envoie une offre « mesh »,
 *    acceptee sans sonnerie puisqu'elle porte le callId de l'appel en cours ;
 *  - tout participant peut inviter, dans la limite de 4 personnes ;
 *  - quitter retire ce poste de l'appel ; les autres continuent. L'appel
 *    s'arrete quand il ne reste plus personne avec qui parler.
 *
 * La voix locale est captee une fois (VoiceAudioIO, 16 kHz), encodee en Opus
 * (ou G.711 pour un poste d'une version anterieure) et envoyee a chacun ; les
 * voix recues sont decodees puis mixees (VoiceMixer) au rythme du
 * haut-parleur.
 *
 * Aucun serveur STUN/TURN externe n'est configure : LocaLink fonctionne
 * en LAN, les candidats ICE "host" (adresses locales) suffisent.
 */
class VoiceService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(network::CallState state READ state NOTIFY stateChanged)

public:
    /// Taille maximale d'un appel, vous compris.
    static constexpr int kMaxParticipants = 4;

    explicit VoiceService(SecurityService *securityService, QObject *parent = nullptr);
    ~VoiceService() override;

    /// Demarre l'ecoute des appels entrants (a appeler une fois au demarrage
    /// de l'application, comme MessagingServer::start()).
    bool startListening(quint16 signalingPort = 12347);
    void setPermissionManager(QObject *manager);
    void stopListening();

    /// Appel a deux : invite un seul poste.
    bool call(const QHostAddress &peerAddress, quint16 signalingPort = 12347);

    /// Appel de groupe : invite 1 a 3 postes en meme temps.
    bool callGroup(const QList<QPair<QHostAddress, quint16>> &peers);

    /// Pendant un appel : invite une personne de plus (4 personnes au plus).
    bool invite(const QHostAddress &peerAddress, quint16 signalingPort = 12347);

    /// Port de signalisation par défaut utilisé par startListening() et call().
    static quint16 defaultSignalingPort();

    /// Accepte l'invitation actuellement en sonnerie (etat Ringing).
    void acceptCall();

    /// Refuse l'invitation en sonnerie, ou quitte l'appel en cours : les
    /// autres participants continuent sans ce poste.
    void hangUp();

    /// Coupe/reactive le microphone local sans interrompre l'appel ; les
    /// autres participants en sont informes.
    void setMuted(bool muted);
    bool isMuted() const;

    CallState state() const { return m_state; }

    /// Participants de l'appel en cours (hors ce poste), dans l'ordre d'arrivee.
    QList<VoiceParticipant> participants() const;
    /// Invitation en sonnerie : personnes deja dans l'appel (hors celle qui invite).
    QList<SignalingRosterEntry> inviteRoster() const { return m_inviteRoster; }
    /// Appel de groupe : invitation de groupe, ou plus d'un autre participant.
    bool isGroupCall() const;
    bool canInvite() const;
    bool isLocalSpeaking() const { return m_localSpeaking; }
    /// Toutes les adresses rencontrees pendant le dernier appel (journal),
    /// conservees jusqu'au suivant.
    QStringList callParticipantAddresses() const { return m_seenAddresses; }

    // ---- Partage d'ecran : une presentation a la fois ------------------------
    /// Personne ne presente et l'appel est etabli.
    bool canPresent() const;
    bool isPresenting() const { return m_presenting; }
    QString presentingTitle() const { return m_presentTitle; }
    /// Commence a presenter (title : « Écran 1 », titre de fenetre...). Les
    /// images arrivent ensuite par pushScreenFrame().
    bool startPresenting(const QString &title);
    void stopPresenting();
    /// Derniere image capturee (envoyee au plus 10 fois par seconde).
    void pushScreenFrame(const QImage &frame);
    QImage localScreenFrame() const;
    /// Participant qui presente (adresse nulle si personne, ou si c'est vous).
    QHostAddress presenterAddress() const;
    QString presenterTitle() const;
    /// Ecran recompose du participant qui presente.
    QImage remoteScreen() const;
    /// Les images de la presentation arrivent en retard (connexion lente).
    bool isRemoteScreenSlow() const;

signals:
    void stateChanged(network::CallState state);

    /// Emis a la reception d'une invitation, avant que l'appel ne passe a
    /// l'etat Ringing, pour que l'UI puisse afficher l'identite de
    /// l'appelant.
    void incomingCall(const QHostAddress &callerAddress);

    /// Emis juste apres qu'un appel sortant ait reellement demarre
    /// (invitations parties, etat passe a Calling), symetrique de
    /// incomingCall() ci-dessus. N'est PAS emis si call() echoue avant ce
    /// point : aucune tentative n'a eu lieu, rien a journaliser.
    void outgoingCallStarted(const QHostAddress &peerAddress);

    /// Emis lorsque la session audio est etablie avec un premier participant
    /// (critere d'acceptation de l'issue #61).
    void callConnected();

    void callEnded(const QString &reason);
    void errorOccurred(const QString &message);

    /// Liste ou etat des participants modifies (arrivee, depart, micro, parole).
    void participantsChanged();
    void participantJoined(const QHostAddress &address);
    /// reason : "left" (a quitte), "connection-lost"...
    void participantLeft(const QHostAddress &address, const QString &reason);
    /// reason : "declined", "busy", "noanswer", "full".
    void participantDeclined(const QHostAddress &address, const QString &reason);

    /// Quelqu'un (vous compris) a commence ou arrete de presenter.
    void presentationChanged();
    /// Nouvelles images de la presentation (au plus ~30 fois par seconde).
    void remoteScreenChanged();
    /// Votre presentation s'est arretee sans que vous l'ayez demande
    /// ("conflict" : un autre participant avait commence juste avant).
    void presentingInterrupted(const QString &reason);
    /// Ce participant ne peut pas voir l'ecran (version trop ancienne).
    void screenUnsupported(const QHostAddress &address);

private:
    struct Peer;
    enum class PeerRole { Invitee, Inviter, Mesh };
    enum class PeerStatus { Dialing, Invited, Inviting, Connecting, Joined };

    void setState(CallState newState);
    void recomputeState();
    void resetCall();
    Peer *peerFor(int linkId) const;
    Peer *peerAt(const QHostAddress &address, quint16 port) const;
    int dial(const QHostAddress &address, quint16 port, PeerRole role);
    void createPeerConnection(Peer &peer);
    void releasePeerConnection(Peer &peer);
    /// Retire un participant ; hangupReason non vide : il en est informe.
    void removePeer(int linkId, const QString &hangupReason = QString());
    void endCallIfAlone(const QString &reason);
    void finishCall(const QString &reason);
    SignalingMessage baseMessage(SignalingMessageType type) const;
    QList<SignalingRosterEntry> joinedRoster(int exceptLinkId) const;
    void sendRoster(Peer &peer);
    void sendState(Peer &peer);

    void onSignalingMessage(int linkId, const network::SignalingMessage &message, const QHostAddress &peerAddress);
    void onOffer(int linkId, const SignalingMessage &message, const QHostAddress &peerAddress);
    void onRemoteHangup(int linkId, const QString &reason);
    void onLinkConnected(int linkId);
    void onLinkClosed(int linkId);
    void onPeerConnectionState(int linkId, int state);
    void onRtpPacket(int linkId, const QByteArray &packet);
    void onCapturedAudioFrame(const QByteArray &pcm16);
    void onHousekeeping();
    void onMixTick();
    void wireScreenChannel(int linkId, const std::shared_ptr<rtc::DataChannel> &channel);
    void onScreenMessage(int linkId, const QByteArray &message);
    void onScreenChannelOpen(int linkId);
    void onScreenTick();
    void sendScreenTiles();
    void updatePresenter();
    void requestScreenRefresh(int linkId);
    void startAudioWithRetry();
    void scheduleAudioRetry();
    void onAudioRetryTimeout();
    void onAudioFault(const QString &reason);

    static constexpr int kInviteTimeoutMs = 30'000;
    static constexpr int kRingingTimeoutMs = 30'000;
    static constexpr int kConnectingTimeoutMs = 20'000;
    static constexpr int kAudioRetryIntervalMs = 1'000;
    static constexpr int kMaxAudioRetryAttempts = 5;
    static constexpr int kPlaybackLeadMs = 60;
    static constexpr int kLossGraceMs = 1'500;
    static constexpr int kSpeakingHoldMs = 450;

    SecurityService *m_securityService = nullptr;
    std::unique_ptr<VoiceSignalingChannel> m_signaling;
    std::unique_ptr<VoiceAudioIO> m_audioIo;
    std::unique_ptr<VoiceMixer> m_mixer;
    std::unique_ptr<OpusVoiceEncoder> m_encoder;

    std::map<int, std::unique_ptr<Peer>> m_peers;   // par numero de liaison
    int m_nextOrder = 0;

    CallState m_state = CallState::Idle;
    QString m_callId;
    bool m_groupInvite = false;      // appel lance (ou recu) comme appel de groupe
    bool m_everConnected = false;
    QString m_lastRemoteReason;
    QList<SignalingRosterEntry> m_inviteRoster;
    QStringList m_seenAddresses;

    QTimer m_housekeeping;
    QTimer m_mixTimer;
    QTimer m_audioRetryTimer;
    int m_audioRetryAttempts = 0;
    int m_mixTicks = 0;
    bool m_localSpeaking = false;
    qint64 m_localVoiceAtMs = 0;

    // Partage d'ecran.
    static constexpr int kScreenTickMs = 100;               // 10 images/s au plus
    static constexpr std::size_t kScreenBufferLimit = 1u << 20;
    static constexpr int kScreenUnsupportedAfterMs = 6'000;
    bool m_presenting = false;
    qint64 m_presentingSince = 0;
    quint32 m_presentToken = 0;
    QString m_presentTitle;
    std::unique_ptr<ScreenTileEncoder> m_screenEncoder;
    QImage m_pendingScreen;
    QTimer m_screenTimer;
    std::unique_ptr<ScreenCanvas> m_canvas;
    int m_presenterLinkId = 0;
    QTimer m_screenNotify;
};

} // namespace network

#endif // NETWORK_VOICESERVICE_H
