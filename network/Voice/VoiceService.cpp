#include "VoiceService.h"
#include "VoiceAudioIO.h"
#include "Security/SecurityService.h"

#include <rtc/rtc.hpp>

#include <QDebug>
#include <QUuid>
#include <QRandomGenerator>

namespace network {

namespace {

/// Aucun serveur STUN/TURN : CollabLAN est un reseau local, seuls des
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
    // la reponse SDP, produisant une 2e offre parasite. Cette offre arrive
    // chez l'appelant alors qu'il est deja en communication : elle est
    // traitee comme "offre concurrente" et provoque un sendHangup() qui
    // casse l'appel en plein handshake DTLS (issue observee : "DTLS
    // handshake failed" systematique juste apres la connexion ICE).
    // On declenche donc setLocalDescription() nous-memes, une seule fois,
    // au bon moment (cf. VoiceService::createPeerConnection() et le cas
    // Offer de VoiceService::onSignalingMessage()).
    config.disableAutoNegotiation = true;
    return config;
}

} // namespace

VoiceService::VoiceService(SecurityService *securityService, QObject *parent)
    : QObject(parent)
    , m_securityService(securityService)
    , m_signaling(std::make_unique<VoiceSignalingChannel>(securityService, this))
    , m_audioIo(std::make_unique<VoiceAudioIO>(this))
{
    connect(m_signaling.get(), &VoiceSignalingChannel::messageReceived,
            this, &VoiceService::onSignalingMessage);
    connect(m_signaling.get(), &VoiceSignalingChannel::peerDisconnected,
            this, &VoiceService::onSignalingPeerDisconnected);
    connect(m_signaling.get(), &VoiceSignalingChannel::peerConnected,
            this, &VoiceService::onSignalingPeerConnected);
    connect(m_signaling.get(), &VoiceSignalingChannel::error,
            this, &VoiceService::errorOccurred);

    connect(m_audioIo.get(), &VoiceAudioIO::capturedFrame,
            this, &VoiceService::onCapturedAudioFrame);

    m_rtpSsrc = QRandomGenerator::global()->generate();
}

VoiceService::~VoiceService()
{
    teardownSession(QStringLiteral("shutdown"));
    stopListening();
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

void VoiceService::setState(CallState newState)
{
    if (m_state == newState) {
        return;
    }
    m_state = newState;
    emit stateChanged(m_state);
}

void VoiceService::createPeerConnection()
{
    m_peerConnection = std::make_shared<rtc::PeerConnection>(lanOnlyConfiguration());

    // Chaque candidat ICE local decouvert (adresse host du poste) est
    // transmis immediatement au correspondant via le canal de
    // signalisation (trickle ICE), conformement au critere de l'issue #60.
    m_peerConnection->onLocalCandidate([this](rtc::Candidate candidate) {
        const QString sdpMid = QString::fromStdString(candidate.mid());
        const QString candidateLine = QString::fromStdString(std::string(candidate));
        QMetaObject::invokeMethod(this, [this, candidateLine, sdpMid]() {
            m_signaling->sendIceCandidate(candidateLine, sdpMid, m_currentCallId);
        }, Qt::QueuedConnection);
    });

    m_peerConnection->onLocalDescription([this](rtc::Description description) {
        const QString sdp = QString::fromStdString(std::string(description));
        const bool isOffer = description.type() == rtc::Description::Type::Offer;
        qDebug() << "VoiceService: description locale generee, type:" << (isOffer ? "offer" : "answer")
                 << "taille:" << sdp.length();
        QMetaObject::invokeMethod(this, [this, sdp, isOffer]() {
            if (isOffer) {
                qDebug() << "VoiceService: envoi de l'offre SDP";
                m_signaling->sendOffer(sdp, m_currentCallId);
            } else {
                qDebug() << "VoiceService: envoi de la reponse SDP";
                m_signaling->sendAnswer(sdp, m_currentCallId);
            }
        }, Qt::QueuedConnection);
    });

    m_peerConnection->onStateChange([this](rtc::PeerConnection::State state) {
        QMetaObject::invokeMethod(this, [this, state]() {
            using State = rtc::PeerConnection::State;
            switch (state) {
            case State::Connected:
                setState(CallState::Connected);
                m_audioIo->start();
                emit callConnected();
                break;
            case State::Disconnected:
            case State::Failed:
                teardownSession(QStringLiteral("connection-lost"));
                break;
            case State::Closed:
                break;
            default:
                break;
            }
        }, Qt::QueuedConnection);
    });

    // Piste audio : format PCMU (G.711 mu-law, 8 kHz mono, RFC 3551),
    // choisi pour eviter toute dependance a un codec externe type Opus
    // tout en restant standard et lisible par n'importe quel decodeur
    // WebRTC. Voir VoiceAudioIO pour l'encodage/decodage.
    rtc::Description::Audio media("audio", rtc::Description::Direction::SendRecv);
    media.addSSRC(m_rtpSsrc, "collablan-audio");
    // RtpMap attend une unique chaine au format SDP "a=rtpmap" :
    // "<payloadType> <format>/<clockRate>" (ex. "0 PCMU/8000").
    rtc::Description::Media::RtpMap rtpMap(
        std::to_string(kRtpPayloadTypePcmu) + " PCMU/" + std::to_string(kVoiceSampleRate));
    media.addRtpMap(rtpMap);

    try {
        m_audioTrack = m_peerConnection->addTrack(media);
    } catch (const std::exception &ex) {
        qWarning() << "VoiceService: echec addTrack -" << ex.what();
        return;
    }
    wireTrackCallbacks();

    // disableAutoNegotiation = true (cf. lanOnlyConfiguration) : addTrack()
    // seul ne declenche plus rien. C'est nous qui declenchons explicitement
    // la generation de l'offre locale, une seule fois, cote appelant.
    if (m_isCaller) {
        try {
            m_peerConnection->setLocalDescription();
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: echec setLocalDescription (offre) -" << ex.what();
        }
    }
}

void VoiceService::wireTrackCallbacks()
{
    if (!m_audioTrack) {
        return;
    }

    m_audioTrack->onOpen([this]() {
        qDebug() << "VoiceService: piste audio ouverte, flux RTP actif dans les deux sens";
    });

    // Reception d'un paquet RTP distant : decodage mu-law puis lecture
    // locale (issue #61, critere "appel fonctionne dans les deux sens").
    m_audioTrack->onMessage([this](rtc::message_variant data) {
        if (!std::holds_alternative<rtc::binary>(data)) {
            return;
        }
        const rtc::binary &bin = std::get<rtc::binary>(data);
        QByteArray packet(reinterpret_cast<const char *>(bin.data()), static_cast<int>(bin.size()));

        const RtpParsedPacket parsed = parseRtpPacket(packet);
        if (!parsed.valid || parsed.payloadType != kRtpPayloadTypePcmu) {
            return;
        }
        const QByteArray pcm = decodeMuLaw(parsed.payload);

        QMetaObject::invokeMethod(this, [this, pcm]() {
            m_audioIo->playFrame(pcm);
        }, Qt::QueuedConnection);
    });
}

bool VoiceService::call(const QHostAddress &peerAddress, quint16 signalingPort)
{
    if (m_state != CallState::Idle) {
        emit errorOccurred(QStringLiteral("Un appel est deja en cours"));
        return false;
    }

    m_peerAddress = peerAddress;
    m_peerSignalingPort = signalingPort;
    m_isCaller = true;
    m_currentCallId = QUuid::createUuid().toString(QUuid::WithoutBraces);

    if (!m_signaling->connectToPeer(peerAddress, signalingPort)) {
        return false;
    }

    setState(CallState::Calling);
    // La PeerConnection sera creee dans onSignalingPeerConnected() une fois
    // que le socket WebSocket sera connecte. L'offre SDP est generee
    // automatiquement par libdatachannel des l'ajout de la piste (negociation
    // automatique) et transmise via onLocalDescription -> VoiceSignalingChannel::sendOffer.
    return true;
}

void VoiceService::acceptCall()
{
    if (m_state != CallState::Ringing) {
        return;
    }
    // La PeerConnection a deja ete creee et setRemoteDescription() appele
    // a la reception de l'offre (onSignalingMessage). Il ne reste qu'a
    // laisser libdatachannel generer la reponse (automatique des que la
    // piste locale est ajoutee), ce qui a egalement deja ete fait.
    setState(CallState::Connecting);
}

void VoiceService::hangUp()
{
    if (m_state == CallState::Idle) {
        return;
    }
    m_signaling->sendHangup(m_currentCallId);
    teardownSession(QStringLiteral("local-hangup"));
}

void VoiceService::setMuted(bool muted)
{
    m_audioIo->setMuted(muted);
}

bool VoiceService::isMuted() const
{
    return m_audioIo->isMuted();
}

void VoiceService::teardownSession(const QString &reason)
{
    if (m_state == CallState::Idle) {
        return;
    }

    m_audioIo->stop();

    if (m_peerConnection) {
        // On desarme les callbacks AVANT close()/reset() : les threads
        // internes de libdatachannel (il en demarre une vingtaine, cf.
        // "Spawning 20 threads" dans les logs) peuvent encore invoquer un
        // callback pendant qu'on detruit la session. Un callback qui
        // capture "this" et appelle QMetaObject::invokeMethod(this, ...)
        // sur un VoiceService en cours de destruction (ou deja detruit)
        // provoque un crash/assert cote Qt ("Cannot send events to objects
        // owned by a different thread"), observe a la fermeture simultanee
        // des deux instances.
        m_peerConnection->onStateChange([](rtc::PeerConnection::State) {});
        m_peerConnection->onLocalDescription([](rtc::Description) {});
        m_peerConnection->onLocalCandidate([](rtc::Candidate) {});
    }

    if (m_audioTrack) {
        m_audioTrack->close();
        m_audioTrack.reset();
    }
    if (m_peerConnection) {
        m_peerConnection->close();
        m_peerConnection.reset();
    }
    m_signaling->disconnectFromPeer();

    m_currentCallId.clear();
    m_isCaller = false;
    m_rtpSequence = 0;
    m_rtpTimestamp = 0;

    setState(CallState::Idle);
    emit callEnded(reason);
}

void VoiceService::onSignalingMessage(const SignalingMessage &message, const QHostAddress &peerAddress)
{
    qDebug() << "VoiceService: message de signalisation recu, type:" << static_cast<int>(message.type)
             << "callId:" << message.callId;

    switch (message.type) {
    case SignalingMessageType::Offer: {
        if (m_state != CallState::Idle) {
            // Deja en communication : on ignore les offres concurrentes.
            qDebug() << "VoiceService: offre ignoree (deja en communication)";
            m_signaling->sendHangup(message.callId);
            return;
        }
        qDebug() << "VoiceService: offre SDP recue, taille:" << message.sdp.length();
        m_peerAddress = peerAddress;
        m_isCaller = false;
        m_currentCallId = message.callId;

        createPeerConnection();
        m_peerConnection->setRemoteDescription(rtc::Description(message.sdp.toStdString(), "offer"));

        // disableAutoNegotiation = true : on declenche nous-memes la reponse
        // SDP, une seule fois, plutot que de laisser une eventuelle
        // negociation automatique parasite se produire (cf. lanOnlyConfiguration).
        try {
            m_peerConnection->setLocalDescription();
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: echec setLocalDescription (reponse) -" << ex.what();
        }

        setState(CallState::Ringing);
        emit incomingCall(peerAddress);
        break;
    }
    case SignalingMessageType::Answer: {
        if (m_state != CallState::Calling || !m_peerConnection) {
            return;
        }
        m_peerConnection->setRemoteDescription(rtc::Description(message.sdp.toStdString(), "answer"));
        setState(CallState::Connecting);
        break;
    }
    case SignalingMessageType::IceCandidate: {
        if (!m_peerConnection) {
            return;
        }
        try {
            m_peerConnection->addRemoteCandidate(
                rtc::Candidate(message.candidate.toStdString(), message.mid.toStdString()));
        } catch (const std::exception &ex) {
            qWarning() << "VoiceService: candidat ICE distant invalide -" << ex.what();
        }
        break;
    }
    case SignalingMessageType::Hangup:
        teardownSession(QStringLiteral("remote-hangup"));
        break;
    case SignalingMessageType::Unknown:
        break;
    }
}

void VoiceService::onSignalingPeerConnected()
{
    qDebug() << "VoiceService: socket de signalisation connecte";
    if (m_isCaller && m_state == CallState::Calling) {
        qDebug() << "VoiceService: creation de la PeerConnection (appelant)";
        createPeerConnection();
    }
}

void VoiceService::onSignalingPeerDisconnected()
{
    qDebug() << "VoiceService: socket de signalisation deconnecte";
    if (m_state != CallState::Idle) {
        teardownSession(QStringLiteral("signaling-disconnected"));
    }
}

void VoiceService::onCapturedAudioFrame(const QByteArray &pcm16)
{
    if (!m_audioTrack || !m_audioTrack->isOpen()) {
        return;
    }

    const QByteArray muLaw = encodeMuLaw(pcm16);

    const std::uint16_t seq = m_rtpSequence.fetch_add(1);
    // L'horloge RTP pour PCMU avance d'un tick par echantillon (clockRate
    // 8000 Hz), donc de kVoiceFrameSamples par trame de 20 ms envoyee.
    const std::uint32_t ts = m_rtpTimestamp.fetch_add(kVoiceFrameSamples);

    const QByteArray rtpPacket = buildRtpPacket(muLaw, kRtpPayloadTypePcmu, seq, ts, m_rtpSsrc, false);

    rtc::binary bin(reinterpret_cast<const std::byte *>(rtpPacket.constData()),
                     reinterpret_cast<const std::byte *>(rtpPacket.constData() + rtpPacket.size()));
    try {
        m_audioTrack->send(bin);
    } catch (const std::exception &ex) {
        qWarning() << "VoiceService: echec envoi paquet RTP -" << ex.what();
    }
}

} // namespace network