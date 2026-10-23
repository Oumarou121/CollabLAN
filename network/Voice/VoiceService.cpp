#include "VoiceService.h"
#include "VoiceAudioIO.h"
#include "VoiceCodec.h"
#include "ScreenTiles.h"
#include "NetworkAddress.h"
#include "Security/SecurityService.h"

#include <rtc/rtc.hpp>

#include <QDateTime>
#include <QDebug>
#include <QElapsedTimer>
#include <QRandomGenerator>
#include <QUuid>

#include <algorithm>

namespace network {

namespace {

/// Aucun serveur STUN/TURN : LocaLink est un reseau local, seuls des
/// candidats ICE "host" (adresses locales des postes) sont necessaires
/// pour etablir la connexion directe entre les deux machines (issue #60).
rtc::Configuration lanOnlyConfiguration()
{
    rtc::Configuration config;
    // config.iceServers reste vide volontairement.
    //
    // disableAutoNegotiation = true : addTrack() ne doit PAS declencher sa
    // propre negociation automatique. Sans ca, cote appele, addTrack()
    // (appele avant setRemoteDescription() dans createPeerConnection())
    // programme une renegotiation qui se declenche juste APRES l'envoi de
    // la reponse SDP, produisant une 2e offre parasite qui cassait l'appel
    // en plein handshake DTLS. On declenche donc setLocalDescription()
    // nous-memes, une seule fois, au bon moment.
    config.disableAutoNegotiation = true;
    return config;
}

/// Un poste d'une version anterieure n'annonce que PCMU : on lui parle G.711.
bool sdpOffersOpus(const QString &sdp)
{
    return sdp.contains(QStringLiteral("opus/48000"), Qt::CaseInsensitive);
}

/// Seuil de parole (RMS normalise) : au-dessus du bruit de fond d'un micro de
/// bureau, en dessous d'une voix normale.
constexpr float kSpeakingLevel = 0.025f;

qint64 nowMs()
{
    return QDateTime::currentMSecsSinceEpoch();
}

} // namespace

// ---------------------------------------------------------------------
// Participant : une liaison de signalisation + une session media.
// ---------------------------------------------------------------------
struct VoiceService::Peer {
    int linkId = 0;
    int order = 0;
    QHostAddress address;
    quint16 port = 0;
    PeerRole role = PeerRole::Invitee;
    PeerStatus status = PeerStatus::Dialing;
    QElapsedTimer since;
    bool isCaller = false;
    bool useOpus = false;
    bool remoteMuted = false;
    bool speaking = false;
    bool lossPending = false;
    qint64 voiceAtMs = 0;

    std::shared_ptr<rtc::PeerConnection> pc;
    std::shared_ptr<rtc::Track> track;
    std::unique_ptr<OpusVoiceDecoder> decoder;
    std::uint32_t ssrc = 0;
    std::uint16_t rtpSequence = 0;
    std::uint32_t rtpTimestamp = 0;

    // Partage d'ecran : canal de donnees de la meme session (absent chez un
    // poste d'une version anterieure), et ce que ce participant a deja recu.
    std::shared_ptr<rtc::DataChannel> screen;
    ScreenViewerState screenState;
    bool screenUnsupportedNotified = false;
    bool remotePresenting = false;
    qint64 remotePresentingSince = 0;
    quint32 remotePresentToken = 0;
    QString remoteScreenTitle;

    void setStatus(PeerStatus s)
    {
        status = s;
        since.restart();
    }
};

VoiceService::VoiceService(SecurityService *securityService, QObject *parent)
    : QObject(parent)
    , m_securityService(securityService)
    , m_signaling(std::make_unique<VoiceSignalingChannel>(securityService, this))
    , m_audioIo(std::make_unique<VoiceAudioIO>(this))
    , m_mixer(std::make_unique<VoiceMixer>())
    , m_encoder(std::make_unique<OpusVoiceEncoder>())
{
    connect(m_signaling.get(), &VoiceSignalingChannel::messageReceived,
            this, &VoiceService::onSignalingMessage);
    connect(m_signaling.get(), &VoiceSignalingChannel::peerConnected,
            this, [this](int linkId, const QHostAddress &) { onLinkConnected(linkId); });
    connect(m_signaling.get(), &VoiceSignalingChannel::peerDisconnected,
            this, &VoiceService::onLinkClosed);
    connect(m_signaling.get(), &VoiceSignalingChannel::error,
            this, &VoiceService::errorOccurred);

    connect(m_audioIo.get(), &VoiceAudioIO::capturedFrame,
            this, &VoiceService::onCapturedAudioFrame);
    connect(m_audioIo.get(), &VoiceAudioIO::audioFault,
            this, &VoiceService::onAudioFault);

    m_housekeeping.setInterval(1000);
    connect(&m_housekeeping, &QTimer::timeout, this, &VoiceService::onHousekeeping);
    // Le haut-parleur donne le rythme : toutes les 10 ms, on complete son
    // tampon jusqu'a kPlaybackLeadMs de son mixe.
    m_mixTimer.setInterval(10);
    m_mixTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_mixTimer, &QTimer::timeout, this, &VoiceService::onMixTick);
    m_audioRetryTimer.setSingleShot(true);
    connect(&m_audioRetryTimer, &QTimer::timeout, this, &VoiceService::onAudioRetryTimeout);

    m_screenEncoder = std::make_unique<ScreenTileEncoder>();
    m_canvas = std::make_unique<ScreenCanvas>();
    m_screenTimer.setInterval(kScreenTickMs);
    connect(&m_screenTimer, &QTimer::timeout, this, &VoiceService::onScreenTick);
    // Les carreaux recus sont regroupes : l'ecran n'est redessine qu'au
    // plus une trentaine de fois par seconde.
    m_screenNotify.setSingleShot(true);
    m_screenNotify.setInterval(33);
    connect(&m_screenNotify, &QTimer::timeout, this, &VoiceService::remoteScreenChanged);
}

VoiceService::~VoiceService()
{
    for (auto &entry : m_peers)
        releasePeerConnection(*entry.second);
    m_peers.clear();
    m_signaling->closeAllLinks();
    stopListening();
}

void VoiceService::setPermissionManager(QObject *manager)
{
    m_signaling->setPermissionManager(manager);
}

bool VoiceService::startListening(quint16 signalingPort)
{
    return m_signaling->listen(signalingPort);
}

void VoiceService::stopListening()
{
    m_signaling->stopListening();
}

quint16 VoiceService::defaultSignalingPort()
{
    return 12347;
}

// ---------------------------------------------------------------------
// Etat global
// ---------------------------------------------------------------------

void VoiceService::setState(CallState newState)
{
    if (m_state == newState) {
        return;
    }
    m_state = newState;
    if (newState == CallState::Idle)
        m_housekeeping.stop();
    else if (!m_housekeeping.isActive())
        m_housekeeping.start();
    emit stateChanged(m_state);
}

void VoiceService::recomputeState()
{
    bool joined = false, inviting = false, connecting = false, pending = false;
    for (const auto &entry : m_peers) {
        const Peer &p = *entry.second;
        switch (p.status) {
        case PeerStatus::Joined: joined = true; break;
        case PeerStatus::Inviting: inviting = true; break;
        case PeerStatus::Connecting: connecting = true; break;
        case PeerStatus::Dialing:
            if (p.role == PeerRole::Mesh) connecting = true; else pending = true;
            break;
        case PeerStatus::Invited: pending = true; break;
        }
    }
    if (joined) setState(CallState::Connected);
    else if (inviting) setState(CallState::Ringing);
    else if (connecting) setState(CallState::Connecting);
    else if (pending) setState(CallState::Calling);
    else setState(CallState::Idle);
}

void VoiceService::resetCall()
{
    m_callId.clear();
    m_groupInvite = false;
    m_everConnected = false;
    m_inviteRoster.clear();
    m_seenAddresses.clear();
    m_mixer->clear();
    m_localSpeaking = false;
}

VoiceService::Peer *VoiceService::peerFor(int linkId) const
{
    const auto it = m_peers.find(linkId);
    return it == m_peers.end() ? nullptr : it->second.get();
}

VoiceService::Peer *VoiceService::peerAt(const QHostAddress &address, quint16 port) const
{
    const QHostAddress wanted = canonicalAddress(address);
    for (const auto &entry : m_peers) {
        if (entry.second->port == port && entry.second->address.isEqual(wanted, QHostAddress::TolerantConversion))
            return entry.second.get();
    }
    return nullptr;
}

QList<VoiceParticipant> VoiceService::participants() const
{
    std::vector<const Peer *> ordered;
    for (const auto &entry : m_peers)
        ordered.push_back(entry.second.get());
    std::sort(ordered.begin(), ordered.end(), [](const Peer *a, const Peer *b) { return a->order < b->order; });

    QList<VoiceParticipant> out;
    for (const Peer *p : ordered) {
        VoiceParticipant v;
        v.address = p->address;
        v.port = p->port;
        switch (p->status) {
        case PeerStatus::Dialing:
            v.status = p->role == PeerRole::Mesh ? QStringLiteral("connecting") : QStringLiteral("invited");
            break;
        case PeerStatus::Invited: v.status = QStringLiteral("invited"); break;
        case PeerStatus::Inviting: v.status = QStringLiteral("inviting"); break;
        case PeerStatus::Connecting: v.status = QStringLiteral("connecting"); break;
        case PeerStatus::Joined: v.status = QStringLiteral("joined"); break;
        }
        v.muted = p->remoteMuted;
        v.speaking = p->speaking;
        out.append(v);
    }
    return out;
}

bool VoiceService::isGroupCall() const
{
    return m_groupInvite || m_peers.size() > 1;
}

bool VoiceService::canInvite() const
{
    return (m_state == CallState::Calling || m_state == CallState::Connecting || m_state == CallState::Connected)
           && static_cast<int>(m_peers.size()) < kMaxParticipants - 1;
}

// ---------------------------------------------------------------------
// Demarrer, inviter, repondre, quitter
// ---------------------------------------------------------------------

bool VoiceService::call(const QHostAddress &peerAddress, quint16 signalingPort)
{
    return callGroup({qMakePair(peerAddress, signalingPort)});
}

bool VoiceService::callGroup(const QList<QPair<QHostAddress, quint16>> &peers)
{
    if (m_state != CallState::Idle) {
        emit errorOccurred(QStringLiteral("Un appel est deja en cours"));
        return false;
    }
    if (peers.isEmpty() || peers.size() > kMaxParticipants - 1)
        return false;

    resetCall();
    m_callId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_groupInvite = peers.size() > 1;
    int dialed = 0;
    for (const auto &target : peers) {
        if (target.first.isNull() || peerAt(target.first, target.second))
            continue;
        if (dial(target.first, target.second, PeerRole::Invitee) > 0)
            ++dialed;
    }
    if (dialed == 0) {
        resetCall();
        return false;
    }

    // La session media de chaque invite est creee une fois sa liaison de
    // signalisation connectee (onLinkConnected), qui envoie alors l'offre.
    recomputeState();
    emit participantsChanged();
    emit outgoingCallStarted(canonicalAddress(peers.first().first));
    return true;
}

bool VoiceService::invite(const QHostAddress &peerAddress, quint16 signalingPort)
{
    if (peerAddress.isNull() || peerAt(peerAddress, signalingPort))
        return false;
    if (!canInvite()) {
        if (m_state != CallState::Idle)
            emit participantDeclined(canonicalAddress(peerAddress), QStringLiteral("full"));
        return false;
    }
    if (dial(peerAddress, signalingPort, PeerRole::Invitee) <= 0)
        return false;
    m_groupInvite = true;
    recomputeState();
    emit participantsChanged();
    return true;
}

int VoiceService::dial(const QHostAddress &address, quint16 port, PeerRole role)
{
    const int linkId = m_signaling->connectToPeer(address, port);
    if (linkId <= 0)
        return 0;
    auto peer = std::make_unique<Peer>();
    peer->linkId = linkId;
    peer->order = m_nextOrder++;
    peer->address = canonicalAddress(address);
    peer->port = port;
    peer->role = role;
    peer->isCaller = true;
    peer->ssrc = QRandomGenerator::global()->generate();
    peer->setStatus(PeerStatus::Dialing);
    const QString key = peer->address.toString();
    if (!m_seenAddresses.contains(key))
        m_seenAddresses.append(key);
    m_peers.emplace(linkId, std::move(peer));
    return linkId;
}

void VoiceService::acceptCall()
{
    if (m_state != CallState::Ringing)
        return;
    for (auto &entry : m_peers) {
        Peer &p = *entry.second;
        if (p.status != PeerStatus::Inviting || !p.pc)
            continue;
        // C'est ICI, et seulement ici, que la reponse SDP part : le moment ou
        // l'utilisateur a reellement clique sur « Repondre ».
        try {
            p.pc->setLocalDescription();
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: echec setLocalDescription (reponse) -" << ex.what();
            return;
        }
        p.setStatus(PeerStatus::Connecting);
        break;
    }
    recomputeState();
    emit participantsChanged();
}

void VoiceService::hangUp()
{
    if (m_state == CallState::Idle) {
        return;
    }
    std::vector<int> ids;
    for (const auto &entry : m_peers)
        ids.push_back(entry.first);
    for (int id : ids) {
        const Peer *p = peerFor(id);
        const QString reason = p->status == PeerStatus::Inviting ? QStringLiteral("declined")
                             : (p->status == PeerStatus::Joined || p->status == PeerStatus::Connecting
                                || p->role == PeerRole::Mesh) ? QStringLiteral("left")
                             : QStringLiteral("cancel");
        removePeer(id, reason);
    }
    finishCall(QStringLiteral("local-hangup"));
}

void VoiceService::setMuted(bool muted)
{
    m_audioIo->setMuted(muted);
    if (muted)
        m_localSpeaking = false;
    for (auto &entry : m_peers) {
        if (entry.second->status == PeerStatus::Joined)
            sendState(*entry.second);
    }
}

bool VoiceService::isMuted() const
{
    return m_audioIo->isMuted();
}

// ---------------------------------------------------------------------
// Fin de liaison, fin d'appel
// ---------------------------------------------------------------------

void VoiceService::removePeer(int linkId, const QString &hangupReason)
{
    const auto it = m_peers.find(linkId);
    if (it == m_peers.end())
        return;
    std::unique_ptr<Peer> peer = std::move(it->second);
    m_peers.erase(it);

    if (!hangupReason.isEmpty() && m_signaling->isLinkOpen(linkId)) {
        SignalingMessage hangup = baseMessage(SignalingMessageType::Hangup);
        hangup.reason = hangupReason;
        m_signaling->send(linkId, hangup);
    }
    releasePeerConnection(*peer);
    m_mixer->remove(linkId);
    m_signaling->closeLink(linkId);
    if (linkId == m_presenterLinkId)
        updatePresenter();          // celui qui presentait est parti
    emit participantsChanged();
}

void VoiceService::endCallIfAlone(const QString &reason)
{
    if (m_state == CallState::Idle && m_peers.empty())
        return;
    if (m_peers.empty()) {
        finishCall(reason);
        return;
    }
    bool live = false;
    for (const auto &entry : m_peers) {
        const PeerStatus s = entry.second->status;
        if (s == PeerStatus::Joined || s == PeerStatus::Connecting || s == PeerStatus::Inviting
            || entry.second->role == PeerRole::Mesh)
            live = true;
    }
    if (m_everConnected && !live) {
        // Seules restent des invitations sans reponse : il n'y a plus
        // personne avec qui parler, elles sont annulees.
        std::vector<int> ids;
        for (const auto &entry : m_peers)
            ids.push_back(entry.first);
        for (int id : ids)
            removePeer(id, QStringLiteral("cancel"));
        finishCall(reason);
        return;
    }
    recomputeState();
}

void VoiceService::finishCall(const QString &reason)
{
    for (auto &entry : m_peers) {
        releasePeerConnection(*entry.second);
        m_signaling->closeLink(entry.first);
    }
    m_peers.clear();
    m_mixTimer.stop();
    m_audioRetryTimer.stop();
    m_audioRetryAttempts = 0;
    m_audioIo->stop();
    m_mixer->clear();
    m_callId.clear();
    m_inviteRoster.clear();
    m_groupInvite = false;
    m_localSpeaking = false;
    const bool hadPresentation = m_presenting || m_presenterLinkId != 0;
    m_presenting = false;
    m_presentTitle.clear();
    m_screenTimer.stop();
    m_pendingScreen = QImage();
    m_presenterLinkId = 0;
    m_canvas->clear();
    if (hadPresentation)
        emit presentationChanged();
    const bool wasActive = m_state != CallState::Idle;
    setState(CallState::Idle);
    emit participantsChanged();
    if (wasActive)
        emit callEnded(reason);
}

// ---------------------------------------------------------------------
// Session media d'un participant
// ---------------------------------------------------------------------

void VoiceService::createPeerConnection(Peer &peer)
{
    const int linkId = peer.linkId;
    peer.pc = std::make_shared<rtc::PeerConnection>(lanOnlyConfiguration());

    // Chaque candidat ICE local decouvert (adresse host du poste) est
    // transmis immediatement au participant (trickle ICE, issue #60). Les
    // rappels de libdatachannel arrivent sur ses propres threads : ils ne
    // retiennent que le numero de liaison, relu sur le thread de ce service
    // (le participant peut avoir ete retire entre-temps).
    peer.pc->onLocalCandidate([this, linkId](rtc::Candidate candidate) {
        const QString sdpMid = QString::fromStdString(candidate.mid());
        const QString candidateLine = QString::fromStdString(std::string(candidate));
        QMetaObject::invokeMethod(this, [this, linkId, candidateLine, sdpMid]() {
            if (!peerFor(linkId))
                return;
            SignalingMessage message = baseMessage(SignalingMessageType::IceCandidate);
            message.candidate = candidateLine;
            message.mid = sdpMid;
            m_signaling->send(linkId, message);
        }, Qt::QueuedConnection);
    });

    peer.pc->onLocalDescription([this, linkId](rtc::Description description) {
        const QString sdp = QString::fromStdString(std::string(description));
        const bool isOffer = description.type() == rtc::Description::Type::Offer;
        QMetaObject::invokeMethod(this, [this, linkId, sdp, isOffer]() {
            Peer *p = peerFor(linkId);
            if (!p)
                return;
            SignalingMessage message = baseMessage(isOffer ? SignalingMessageType::Offer
                                                           : SignalingMessageType::Answer);
            message.sdp = sdp;
            if (isOffer) {
                message.signalingPort = m_signaling->listenPort();
                message.mesh = p->role == PeerRole::Mesh;
                message.group = isGroupCall();
                // Invitation : qui est deja dans l'appel (affiche chez l'invite).
                if (p->role == PeerRole::Invitee)
                    message.roster = joinedRoster(linkId);
            }
            m_signaling->send(linkId, message);
        }, Qt::QueuedConnection);
    });

    peer.pc->onStateChange([this, linkId](rtc::PeerConnection::State state) {
        QMetaObject::invokeMethod(this, [this, linkId, state]() {
            onPeerConnectionState(linkId, static_cast<int>(state));
        }, Qt::QueuedConnection);
    });

    // Piste audio : Opus (prefere) puis PCMU, que comprennent les postes
    // d'une version anterieure. Le codec d'envoi suit ce que l'autre annonce.
    rtc::Description::Audio media("audio", rtc::Description::Direction::SendRecv);
    media.addOpusCodec(kRtpPayloadTypeOpus);
    media.addPCMUCodec(kRtpPayloadTypePcmu);
    media.addSSRC(peer.ssrc, "localink-audio");

    try {
        peer.track = peer.pc->addTrack(media);
    } catch (const std::exception &ex) {
        qWarning() << "VoiceService: echec addTrack -" << ex.what();
        return;
    }

    peer.track->onMessage([this, linkId](rtc::message_variant data) {
        if (!std::holds_alternative<rtc::binary>(data))
            return;
        const rtc::binary &bin = std::get<rtc::binary>(data);
        const QByteArray packet(reinterpret_cast<const char *>(bin.data()), static_cast<int>(bin.size()));
        QMetaObject::invokeMethod(this, [this, linkId, packet]() {
            onRtpPacket(linkId, packet);
        }, Qt::QueuedConnection);
    });

    // Partage d'ecran : canal de donnees ouvert des l'etablissement de la
    // session, cree par l'appelant avant son offre (qui l'annonce), recu par
    // l'appele. Un poste d'une version anterieure n'en ouvre pas : il ne
    // verra pas les presentations (signale a celui qui presente).
    if (peer.isCaller) {
        try {
            peer.screen = peer.pc->createDataChannel("localink-screen");
            wireScreenChannel(linkId, peer.screen);
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: canal de partage d'ecran indisponible -" << ex.what();
        }
    } else {
        peer.pc->onDataChannel([this, linkId](std::shared_ptr<rtc::DataChannel> channel) {
            wireScreenChannel(linkId, channel);
            QMetaObject::invokeMethod(this, [this, linkId, channel]() {
                if (Peer *p = peerFor(linkId))
                    p->screen = channel;
                else
                    channel->close();
            }, Qt::QueuedConnection);
        });
    }

    // disableAutoNegotiation = true : c'est nous qui declenchons l'offre,
    // une seule fois, cote appelant.
    if (peer.isCaller) {
        try {
            peer.pc->setLocalDescription();
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: echec setLocalDescription (offre) -" << ex.what();
        }
    }
}

void VoiceService::releasePeerConnection(Peer &peer)
{
    // On desarme les rappels AVANT close()/reset() : les threads internes de
    // libdatachannel peuvent encore en invoquer un pendant la fermeture.
    if (peer.pc) {
        peer.pc->onStateChange([](rtc::PeerConnection::State) {});
        peer.pc->onLocalDescription([](rtc::Description) {});
        peer.pc->onLocalCandidate([](rtc::Candidate) {});
        peer.pc->onDataChannel([](std::shared_ptr<rtc::DataChannel>) {});
    }
    if (peer.screen) {
        peer.screen->onMessage([](rtc::message_variant) {});
        peer.screen->onOpen([]() {});
        peer.screen->close();
        peer.screen.reset();
    }
    if (peer.track) {
        peer.track->onMessage([](rtc::message_variant) {});
        peer.track->close();
        peer.track.reset();
    }
    if (peer.pc) {
        peer.pc->close();
        peer.pc.reset();
    }
}

void VoiceService::onPeerConnectionState(int linkId, int stateValue)
{
    Peer *p = peerFor(linkId);
    if (!p)
        return;
    using State = rtc::PeerConnection::State;
    const auto state = static_cast<State>(stateValue);
    if (state == State::Connected) {
        p->lossPending = false;     // coupure passagere resorbee
        if (p->status == PeerStatus::Joined)
            return;
        p->setStatus(PeerStatus::Joined);
        const bool first = !m_everConnected;
        m_everConnected = true;
        const QHostAddress address = p->address;
        // Celui qui a invite presente les autres participants au nouveau
        // venu, qui va se relier a chacun.
        if (p->role == PeerRole::Invitee)
            sendRoster(*p);
        // Micro coupe ou presentation en cours : le nouveau venu le sait tout de suite.
        if (isMuted() || m_presenting)
            sendState(*p);
        recomputeState();
        // Windows peut repondre temporairement sans peripherique par defaut
        // pendant un changement de casque ou au reveil : startAudioWithRetry()
        // reessaie sans couper la session.
        startAudioWithRetry();
        if (!m_mixTimer.isActive())
            m_mixTimer.start();
        emit participantsChanged();
        if (first)
            emit callConnected();
        emit participantJoined(address);
    } else if (state == State::Disconnected && !p->lossPending) {
        // Le participant qui quitte ferme sa session juste apres avoir envoye
        // « call-hangup » : la coupure arrive souvent la premiere. On laisse
        // un instant au message pour que son depart ne soit pas pris pour
        // une perte de connexion.
        p->lossPending = true;
        QTimer::singleShot(kLossGraceMs, this, [this, linkId]() {
            const Peer *q = peerFor(linkId);
            if (q && q->lossPending)
                onPeerConnectionState(linkId, static_cast<int>(rtc::PeerConnection::State::Failed));
        });
    } else if (state == State::Failed) {
        const QHostAddress address = p->address;
        const bool wasJoined = p->status == PeerStatus::Joined;
        removePeer(linkId);
        if (wasJoined)
            emit participantLeft(address, QStringLiteral("connection-lost"));
        endCallIfAlone(QStringLiteral("connection-lost"));
    }
}

SignalingMessage VoiceService::baseMessage(SignalingMessageType type) const
{
    SignalingMessage message;
    message.type = type;
    message.callId = m_callId;
    return message;
}

QList<SignalingRosterEntry> VoiceService::joinedRoster(int exceptLinkId) const
{
    QList<SignalingRosterEntry> roster;
    for (const auto &entry : m_peers) {
        const Peer &p = *entry.second;
        if (entry.first == exceptLinkId || p.status != PeerStatus::Joined)
            continue;
        roster.append({p.address.toString(), p.port});
    }
    return roster;
}

void VoiceService::sendRoster(Peer &peer)
{
    SignalingMessage message = baseMessage(SignalingMessageType::Roster);
    message.roster = joinedRoster(peer.linkId);
    if (!message.roster.isEmpty())
        m_signaling->send(peer.linkId, message);
}

void VoiceService::sendState(Peer &peer)
{
    SignalingMessage message = baseMessage(SignalingMessageType::State);
    message.muted = isMuted();
    message.presenting = m_presenting;
    message.presentingSince = m_presentingSince;
    message.presentToken = m_presentToken;
    message.screenTitle = m_presentTitle;
    m_signaling->send(peer.linkId, message);
}

// ---------------------------------------------------------------------
// Signalisation
// ---------------------------------------------------------------------

void VoiceService::onLinkConnected(int linkId)
{
    Peer *p = peerFor(linkId);
    if (!p) {
        // Liaison entrante : on attend son offre.
        return;
    }
    if (!p->isCaller || p->status != PeerStatus::Dialing)
        return;
    p->setStatus(p->role == PeerRole::Invitee ? PeerStatus::Invited : PeerStatus::Connecting);
    createPeerConnection(*p);
    recomputeState();
    emit participantsChanged();
}

void VoiceService::onLinkClosed(int linkId)
{
    Peer *p = peerFor(linkId);
    if (!p)
        return;
    const QHostAddress address = p->address;
    const PeerStatus status = p->status;
    const PeerRole role = p->role;
    removePeer(linkId);
    if (status == PeerStatus::Joined || status == PeerStatus::Connecting)
        emit participantLeft(address, QStringLiteral("connection-lost"));
    else if (role == PeerRole::Invitee)
        emit participantDeclined(address, QStringLiteral("unreachable"));
    endCallIfAlone(status == PeerStatus::Joined ? QStringLiteral("connection-lost")
                                                : QStringLiteral("signaling-disconnected"));
}

void VoiceService::onSignalingMessage(int linkId, const SignalingMessage &message, const QHostAddress &peerAddress)
{
    switch (message.type) {
    case SignalingMessageType::Offer:
        onOffer(linkId, message, peerAddress);
        break;
    case SignalingMessageType::Answer: {
        Peer *p = peerFor(linkId);
        if (!p || !p->isCaller || !p->pc)
            return;
        try {
            p->pc->setRemoteDescription(rtc::Description(message.sdp.toStdString(), "answer"));
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: reponse SDP invalide -" << ex.what();
            return;
        }
        p->useOpus = sdpOffersOpus(message.sdp);
        p->setStatus(PeerStatus::Connecting);
        recomputeState();
        emit participantsChanged();
        break;
    }
    case SignalingMessageType::IceCandidate: {
        Peer *p = peerFor(linkId);
        if (!p || !p->pc)
            return;
        try {
            p->pc->addRemoteCandidate(rtc::Candidate(message.candidate.toStdString(), message.mid.toStdString()));
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: candidat ICE distant invalide -" << ex.what();
        }
        break;
    }
    case SignalingMessageType::Hangup:
        onRemoteHangup(linkId, message.reason);
        break;
    case SignalingMessageType::Roster: {
        if (!peerFor(linkId) || message.callId != m_callId)
            return;
        // Le nouveau venu se relie a chacun des participants annonces ; ceux
        // qui sont deja relies a lui (ou plein) sont ignores.
        for (const SignalingRosterEntry &entry : message.roster) {
            const QHostAddress address(entry.address);
            if (address.isNull() || peerAt(address, entry.port))
                continue;
            if (static_cast<int>(m_peers.size()) >= kMaxParticipants - 1)
                break;
            dial(address, entry.port, PeerRole::Mesh);
        }
        recomputeState();
        emit participantsChanged();
        break;
    }
    case SignalingMessageType::State: {
        Peer *p = peerFor(linkId);
        if (!p)
            return;
        if (p->remoteMuted != message.muted) {
            p->remoteMuted = message.muted;
            if (message.muted)
                p->speaking = false;
            emit participantsChanged();
        }
        const bool wasPresenting = p->remotePresenting;
        p->remotePresenting = message.presenting;
        p->remotePresentingSince = message.presentingSince;
        p->remotePresentToken = message.presentToken;
        p->remoteScreenTitle = message.presenting ? message.screenTitle : QString();
        if (message.presenting && m_presenting) {
            // Deux debuts presque simultanes : le premier garde la parole,
            // partout de la meme facon (heure de debut, puis jeton tire au sort).
            const bool theyWin = message.presentingSince < m_presentingSince
                || (message.presentingSince == m_presentingSince && message.presentToken < m_presentToken);
            if (theyWin) {
                stopPresenting();
                emit presentingInterrupted(QStringLiteral("conflict"));
            }
        }
        if (wasPresenting != message.presenting || linkId == m_presenterLinkId)
            updatePresenter();
        break;
    }
    case SignalingMessageType::Unknown:
        break;
    }
}

void VoiceService::onOffer(int linkId, const SignalingMessage &message, const QHostAddress &peerAddress)
{
    if (peerFor(linkId))
        return;     // renegociation non geree : une offre par liaison
    const quint16 port = message.signalingPort > 0 ? message.signalingPort : defaultSignalingPort();
    const auto refuse = [this, linkId, &message](const QString &reason) {
        SignalingMessage hangup;
        hangup.type = SignalingMessageType::Hangup;
        hangup.callId = message.callId;
        hangup.reason = reason;
        m_signaling->send(linkId, hangup);
        m_signaling->closeLink(linkId);
    };

    const bool sameCall = m_state != CallState::Idle && !m_callId.isEmpty() && message.callId == m_callId;
    if (sameCall) {
        // Un membre de l'appel en cours se relie a ce poste (offre « mesh »
        // ou invitation croisee) : accepte sans sonnerie.
        if (m_state == CallState::Ringing) {
            refuse(QStringLiteral("busy"));
            return;
        }
        if (static_cast<int>(m_peers.size()) >= kMaxParticipants - 1) {
            refuse(QStringLiteral("full"));
            return;
        }
        if (peerAt(peerAddress, port)) {
            refuse(QStringLiteral("duplicate"));
            return;
        }
        auto peer = std::make_unique<Peer>();
        peer->linkId = linkId;
        peer->order = m_nextOrder++;
        peer->address = canonicalAddress(peerAddress);
        peer->port = port;
        peer->role = PeerRole::Mesh;
        peer->isCaller = false;
        peer->useOpus = sdpOffersOpus(message.sdp);
        peer->ssrc = QRandomGenerator::global()->generate();
        peer->setStatus(PeerStatus::Connecting);
        Peer &p = *peer;
        m_peers.emplace(linkId, std::move(peer));
        if (!m_seenAddresses.contains(p.address.toString()))
            m_seenAddresses.append(p.address.toString());
        createPeerConnection(p);
        try {
            p.pc->setRemoteDescription(rtc::Description(message.sdp.toStdString(), "offer"));
            p.pc->setLocalDescription();
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: offre de liaison invalide -" << ex.what();
            removePeer(linkId, QStringLiteral("failed"));
            return;
        }
        recomputeState();
        emit participantsChanged();
        return;
    }

    if (m_state != CallState::Idle) {
        // Deja en communication (un autre appel) : occupe.
        qDebug() << "VoiceService: offre refusee (deja en communication)";
        refuse(QStringLiteral("busy"));
        return;
    }

    // Invitation : a deux, ou a un appel de groupe.
    resetCall();
    m_callId = message.callId;
    m_groupInvite = message.group || !message.roster.isEmpty();
    m_inviteRoster = message.roster;
    auto peer = std::make_unique<Peer>();
    peer->linkId = linkId;
    peer->order = m_nextOrder++;
    peer->address = canonicalAddress(peerAddress);
    peer->port = port;
    peer->role = PeerRole::Inviter;
    peer->isCaller = false;
    peer->useOpus = sdpOffersOpus(message.sdp);
    peer->ssrc = QRandomGenerator::global()->generate();
    peer->setStatus(PeerStatus::Inviting);
    Peer &p = *peer;
    m_peers.emplace(linkId, std::move(peer));
    m_seenAddresses.append(p.address.toString());
    for (const SignalingRosterEntry &entry : message.roster) {
        if (!m_seenAddresses.contains(entry.address))
            m_seenAddresses.append(entry.address);
    }
    createPeerConnection(p);
    try {
        p.pc->setRemoteDescription(rtc::Description(message.sdp.toStdString(), "offer"));
    } catch (const std::exception &ex) {
        qWarning() << "VoiceService: offre SDP invalide -" << ex.what();
        removePeer(linkId, QStringLiteral("failed"));
        resetCall();
        return;
    }
    // La reponse SDP n'est PAS generee ici : ce serait repondre avant que
    // l'utilisateur ait clique sur « Repondre » (cf. acceptCall()).
    // incomingCall() precede le passage a Ringing : le journal ouvre son
    // entree avant de voir la sonnerie (cf. CallHistoryManager).
    emit incomingCall(p.address);
    recomputeState();
    emit participantsChanged();
}

void VoiceService::onRemoteHangup(int linkId, const QString &reason)
{
    Peer *p = peerFor(linkId);
    if (!p)
        return;
    const QHostAddress address = p->address;
    const PeerStatus status = p->status;
    const PeerRole role = p->role;
    removePeer(linkId);

    if (role == PeerRole::Invitee && (status == PeerStatus::Invited || status == PeerStatus::Dialing)) {
        const QString why = reason == QStringLiteral("busy") ? reason
                          : reason == QStringLiteral("full") ? reason
                          : reason == QStringLiteral("timeout") ? QStringLiteral("noanswer")
                          : QStringLiteral("declined");
        if (why == QStringLiteral("busy") && !isGroupCall() && m_peers.empty())
            emit errorOccurred(QStringLiteral("La personne est deja en ligne."));
        emit participantDeclined(address, why);
    } else if (status == PeerStatus::Joined || status == PeerStatus::Connecting) {
        emit participantLeft(address, QStringLiteral("left"));
    }
    endCallIfAlone(QStringLiteral("remote-hangup"));
}

// ---------------------------------------------------------------------
// Delais
// ---------------------------------------------------------------------

void VoiceService::onHousekeeping()
{
    std::vector<int> ids;
    for (const auto &entry : m_peers)
        ids.push_back(entry.first);
    bool dropped = false;
    for (int id : ids) {
        Peer *p = peerFor(id);
        if (!p)
            continue;
        const qint64 elapsed = p->since.elapsed();
        const QHostAddress address = p->address;
        const bool pendingInvite = p->role == PeerRole::Invitee
                                   && (p->status == PeerStatus::Dialing || p->status == PeerStatus::Invited);
        if (pendingInvite && elapsed > kInviteTimeoutMs) {
            removePeer(id, QStringLiteral("timeout"));
            emit participantDeclined(address, QStringLiteral("noanswer"));
            dropped = true;
        } else if (p->status == PeerStatus::Inviting && elapsed > kRingingTimeoutMs) {
            removePeer(id, QStringLiteral("timeout"));
            dropped = true;
        } else if ((p->status == PeerStatus::Connecting
                    || (p->status == PeerStatus::Dialing && p->role == PeerRole::Mesh))
                   && elapsed > kConnectingTimeoutMs) {
            removePeer(id, QStringLiteral("timeout"));
            emit participantLeft(address, QStringLiteral("connection-lost"));
            dropped = true;
        } else if (m_presenting && p->status == PeerStatus::Joined && !p->screenUnsupportedNotified
                   && (!p->screen || !p->screen->isOpen()) && elapsed > kScreenUnsupportedAfterMs) {
            // Pas de canal de partage d'ecran : poste d'une version anterieure.
            p->screenUnsupportedNotified = true;
            emit screenUnsupported(address);
        }
    }
    if (dropped) {
        if (m_peers.empty() || !m_everConnected)
            emit errorOccurred(QStringLiteral("L'appel a expire avant d'etre etabli."));
        endCallIfAlone(QStringLiteral("timeout"));
    }
}

// ---------------------------------------------------------------------
// Audio
// ---------------------------------------------------------------------

void VoiceService::onRtpPacket(int linkId, const QByteArray &packet)
{
    Peer *p = peerFor(linkId);
    if (!p)
        return;
    const RtpParsedPacket parsed = parseRtpPacket(packet);
    if (!parsed.valid)
        return;
    QByteArray pcm;
    if (parsed.payloadType == kRtpPayloadTypePcmu) {
        pcm = resamplePcm16(decodeMuLaw(parsed.payload), kPcmuSampleRate, kVoiceSampleRate);
    } else if (parsed.payloadType == kRtpPayloadTypeOpus) {
        if (!p->decoder)
            p->decoder = std::make_unique<OpusVoiceDecoder>();
        pcm = p->decoder->decode(parsed.payload);
    } else {
        return;
    }
    for (int offset = 0; offset + kVoiceFrameBytes <= pcm.size(); offset += kVoiceFrameBytes) {
        const QByteArray frame = pcm.mid(offset, kVoiceFrameBytes);
        m_mixer->push(linkId, frame);
        if (!p->remoteMuted && pcm16Level(frame) > kSpeakingLevel)
            p->voiceAtMs = nowMs();
    }
}

void VoiceService::onCapturedAudioFrame(const QByteArray &pcm16)
{
    if (pcm16.size() != kVoiceFrameBytes)
        return;
    if (pcm16Level(pcm16) > kSpeakingLevel)
        m_localVoiceAtMs = nowMs();

    QByteArray opusPacket;
    QByteArray pcmuPayload;
    for (auto &entry : m_peers) {
        Peer &p = *entry.second;
        if (p.status != PeerStatus::Joined || !p.track || !p.track->isOpen())
            continue;
        QByteArray payload;
        std::uint8_t payloadType;
        std::uint32_t ticks;
        if (p.useOpus) {
            if (opusPacket.isEmpty())
                opusPacket = m_encoder->encode(pcm16);
            payload = opusPacket;
            payloadType = kRtpPayloadTypeOpus;
            ticks = kOpusFrameTicks;
        } else {
            if (pcmuPayload.isEmpty())
                pcmuPayload = encodeMuLaw(resamplePcm16(pcm16, kVoiceSampleRate, kPcmuSampleRate));
            payload = pcmuPayload;
            payloadType = kRtpPayloadTypePcmu;
            ticks = kPcmuFrameSamples;
        }
        if (payload.isEmpty())
            continue;
        const QByteArray rtpPacket = buildRtpPacket(payload, payloadType, p.rtpSequence++, p.rtpTimestamp,
                                                    p.ssrc, false);
        p.rtpTimestamp += ticks;
        rtc::binary bin(reinterpret_cast<const std::byte *>(rtpPacket.constData()),
                        reinterpret_cast<const std::byte *>(rtpPacket.constData() + rtpPacket.size()));
        try {
            p.track->send(bin);
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: echec envoi paquet RTP -" << ex.what();
        }
    }
}

void VoiceService::onMixTick()
{
    ++m_mixTicks;
    if (m_audioIo->hasPlayback()) {
        int buffered = m_audioIo->playbackBufferedMs();
        if (buffered < 0) {
            // Tampon inconnu : une trame toutes les deux echeances (20 ms).
            if (m_mixTicks % 2 == 0)
                m_audioIo->playFrame(m_mixer->mixNext());
        } else {
            for (int guard = 0; buffered < kPlaybackLeadMs && guard < 6; ++guard) {
                m_audioIo->playFrame(m_mixer->mixNext());
                buffered += kVoiceFrameMs;
            }
        }
    } else if (m_mixTicks % 2 == 0) {
        // Pas de haut-parleur : les files ne doivent pas grossir pour rien.
        m_mixer->mixNext();
    }

    // Qui parle, environ toutes les 100 ms.
    if (m_mixTicks % 10 != 0)
        return;
    const qint64 now = nowMs();
    bool changed = false;
    const bool local = !isMuted() && now - m_localVoiceAtMs < kSpeakingHoldMs;
    if (local != m_localSpeaking) {
        m_localSpeaking = local;
        changed = true;
    }
    for (auto &entry : m_peers) {
        Peer &p = *entry.second;
        const bool speaking = p.status == PeerStatus::Joined && !p.remoteMuted
                              && now - p.voiceAtMs < kSpeakingHoldMs;
        if (speaking != p.speaking) {
            p.speaking = speaking;
            changed = true;
        }
    }
    if (changed)
        emit participantsChanged();
}

void VoiceService::startAudioWithRetry()
{
    if (m_state != CallState::Connected || m_audioIo->isFullyActive()) {
        return;
    }

    if (m_audioIo->start()) {
        m_audioRetryTimer.stop();
        m_audioRetryAttempts = 0;
        qInfo() << "VoiceService: audio local initialise";
        return;
    }

    // Conserver le sens deja fonctionnel : un poste sans microphone doit
    // toujours pouvoir entendre ses correspondants pendant que le service
    // signale clairement l'indisponibilite persistante de l'autre sens.
    scheduleAudioRetry();
}

void VoiceService::scheduleAudioRetry()
{
    if (m_state != CallState::Connected || m_audioRetryTimer.isActive()) {
        return;
    }

    if (m_audioRetryAttempts >= kMaxAudioRetryAttempts) {
        qWarning() << "VoiceService: echec definitif de l'initialisation audio apres"
                   << m_audioRetryAttempts << "tentatives";
        if (m_audioIo->hasPlayback() && !m_audioIo->hasCapture()) {
            emit errorOccurred(QStringLiteral(
                "Microphone indisponible : vous pouvez toujours entendre vos correspondants."));
        } else if (m_audioIo->hasCapture() && !m_audioIo->hasPlayback()) {
            emit errorOccurred(QStringLiteral(
                "Haut-parleur ou casque indisponible : vos correspondants peuvent toujours vous entendre."));
        } else {
            emit errorOccurred(QStringLiteral(
                "Microphone ou haut-parleur indisponible sur ce poste : l'appel est connecte mais sans son."));
        }
        return;
    }

    ++m_audioRetryAttempts;
    qWarning() << "VoiceService: peripherique audio indisponible, nouvelle tentative"
               << m_audioRetryAttempts << "/" << kMaxAudioRetryAttempts;
    m_audioRetryTimer.start(kAudioRetryIntervalMs);
}

void VoiceService::onAudioRetryTimeout()
{
    startAudioWithRetry();
}

// ---------------------------------------------------------------------
// Partage d'ecran
// ---------------------------------------------------------------------

bool VoiceService::canPresent() const
{
    return m_state == CallState::Connected && !m_presenting && m_presenterLinkId == 0;
}

bool VoiceService::startPresenting(const QString &title)
{
    if (!canPresent())
        return false;
    m_presenting = true;
    m_presentingSince = QDateTime::currentMSecsSinceEpoch();
    m_presentToken = QRandomGenerator::global()->generate();
    m_presentTitle = title;
    m_screenEncoder = std::make_unique<ScreenTileEncoder>();
    m_pendingScreen = QImage();
    for (auto &entry : m_peers) {
        Peer &p = *entry.second;
        p.screenState.reset();
        p.screenUnsupportedNotified = false;
        if (p.status == PeerStatus::Joined) {
            p.since.restart();      // delai avant d'annoncer « version trop ancienne »
            sendState(p);
        }
    }
    m_screenTimer.start();
    emit presentationChanged();
    return true;
}

void VoiceService::stopPresenting()
{
    if (!m_presenting)
        return;
    m_presenting = false;
    m_presentTitle.clear();
    m_screenTimer.stop();
    m_pendingScreen = QImage();
    for (auto &entry : m_peers) {
        if (entry.second->status == PeerStatus::Joined)
            sendState(*entry.second);
    }
    emit presentationChanged();
}

void VoiceService::pushScreenFrame(const QImage &frame)
{
    // Seule la derniere image compte : elle part a la prochaine echeance.
    if (m_presenting && !frame.isNull())
        m_pendingScreen = frame;
}

QImage VoiceService::localScreenFrame() const
{
    return m_screenEncoder ? m_screenEncoder->frame() : QImage();
}

QHostAddress VoiceService::presenterAddress() const
{
    const Peer *p = peerFor(m_presenterLinkId);
    return p ? p->address : QHostAddress();
}

QString VoiceService::presenterTitle() const
{
    const Peer *p = peerFor(m_presenterLinkId);
    return p ? p->remoteScreenTitle : QString();
}

QImage VoiceService::remoteScreen() const
{
    return m_presenterLinkId != 0 ? m_canvas->image() : QImage();
}

bool VoiceService::isRemoteScreenSlow() const
{
    return m_presenterLinkId != 0 && m_canvas->lastFrameIncomplete();
}

void VoiceService::updatePresenter()
{
    // Celui qui a commence le premier (meme regle chez tous les participants).
    int best = 0;
    const Peer *bestPeer = nullptr;
    if (!m_presenting) {
        for (const auto &entry : m_peers) {
            const Peer &p = *entry.second;
            if (!p.remotePresenting)
                continue;
            if (!bestPeer || p.remotePresentingSince < bestPeer->remotePresentingSince
                || (p.remotePresentingSince == bestPeer->remotePresentingSince
                    && p.remotePresentToken < bestPeer->remotePresentToken)) {
                bestPeer = &p;
                best = entry.first;
            }
        }
    }
    if (best != m_presenterLinkId) {
        m_presenterLinkId = best;
        m_canvas->clear();
        if (best != 0)
            requestScreenRefresh(best);
        emit remoteScreenChanged();
    }
    emit presentationChanged();
}

void VoiceService::requestScreenRefresh(int linkId)
{
    const Peer *p = peerFor(linkId);
    if (!p || !p->screen || !p->screen->isOpen())
        return;
    const QByteArray request = screenRefreshRequest();
    try {
        p->screen->send(reinterpret_cast<const std::byte *>(request.constData()),
                        static_cast<size_t>(request.size()));
    } catch (const std::exception &ex) {
        qWarning() << "VoiceService: demande d'ecran non envoyee -" << ex.what();
    }
}

void VoiceService::wireScreenChannel(int linkId, const std::shared_ptr<rtc::DataChannel> &channel)
{
    if (!channel)
        return;
    // Rappels sur les threads de libdatachannel : seul le numero de liaison
    // est retenu, relu sur le thread de ce service.
    channel->onMessage([this, linkId](rtc::message_variant data) {
        if (!std::holds_alternative<rtc::binary>(data))
            return;
        const rtc::binary &bin = std::get<rtc::binary>(data);
        const QByteArray message(reinterpret_cast<const char *>(bin.data()), static_cast<int>(bin.size()));
        QMetaObject::invokeMethod(this, [this, linkId, message]() {
            onScreenMessage(linkId, message);
        }, Qt::QueuedConnection);
    });
    channel->onOpen([this, linkId]() {
        QMetaObject::invokeMethod(this, [this, linkId]() {
            onScreenChannelOpen(linkId);
        }, Qt::QueuedConnection);
    });
}

void VoiceService::onScreenChannelOpen(int linkId)
{
    if (linkId == m_presenterLinkId)
        requestScreenRefresh(linkId);
}

void VoiceService::onScreenMessage(int linkId, const QByteArray &message)
{
    Peer *p = peerFor(linkId);
    if (!p)
        return;
    if (isScreenRefreshRequest(message)) {
        p->screenState.reset();     // tout l'ecran repart a la prochaine echeance
        return;
    }
    if (linkId != m_presenterLinkId)
        return;
    const bool wasSlow = m_canvas->lastFrameIncomplete();
    const bool changed = m_canvas->apply(message);
    if ((changed || wasSlow != m_canvas->lastFrameIncomplete()) && !m_screenNotify.isActive())
        m_screenNotify.start();
}

void VoiceService::onScreenTick()
{
    if (!m_presenting)
        return;
    if (!m_pendingScreen.isNull()) {
        m_screenEncoder->setFrame(m_pendingScreen);
        m_pendingScreen = QImage();
    }
    sendScreenTiles();
}

void VoiceService::sendScreenTiles()
{
    if (!m_screenEncoder->hasFrame())
        return;
    const QSize size = m_screenEncoder->frameSize();
    for (auto &entry : m_peers) {
        Peer &p = *entry.second;
        if (p.status != PeerStatus::Joined || !p.screen || !p.screen->isOpen())
            continue;
        ScreenViewerState &viewer = p.screenState;
        const QVector<int> pending = m_screenEncoder->pendingTiles(viewer);
        if (pending.isEmpty())
            continue;
        if (viewer.frameSize != size) {
            viewer.sent.clear();
            viewer.frameSize = size;
        }
        // Un spectateur lent ne recoit que ce que son canal absorbe ; le
        // reste part aux echeances suivantes, sans ralentir les autres.
        bool complete = true;
        try {
            for (int index : pending) {
                if (p.screen->bufferedAmount() > kScreenBufferLimit) {
                    complete = false;
                    break;
                }
                const QByteArray message = m_screenEncoder->tileMessage(index);
                if (message.isEmpty() || static_cast<size_t>(message.size()) > p.screen->maxMessageSize()) {
                    viewer.sent.insert(index, m_screenEncoder->tileHash(index));   // carreau impossible a envoyer
                    continue;
                }
                p.screen->send(reinterpret_cast<const std::byte *>(message.constData()),
                               static_cast<size_t>(message.size()));
                viewer.sent.insert(index, m_screenEncoder->tileHash(index));
            }
            const QByteArray end = screenFrameEndMessage(m_screenEncoder->sequence(), complete);
            p.screen->send(reinterpret_cast<const std::byte *>(end.constData()), static_cast<size_t>(end.size()));
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: envoi de l'ecran interrompu -" << ex.what();
        }
    }
}

void VoiceService::onAudioFault(const QString &reason)
{
    if (m_state != CallState::Connected) {
        return;
    }

    qWarning() << "VoiceService:" << reason << "Reinitialisation audio demandee.";
    m_audioIo->stop();
    m_audioRetryAttempts = 0;
    scheduleAudioRetry();
}

} // namespace network
