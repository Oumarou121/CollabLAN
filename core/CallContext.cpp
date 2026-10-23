#include "CallContext.h"

#include <QHostAddress>
#include <QVariantMap>

namespace core {

CallContext::CallContext(QObject *parent)
    : QObject(parent)
{
}

CallContext::~CallContext() = default;

void CallContext::setVoiceService(network::VoiceService *service)
{
    if (m_voiceService == service) {
        return;
    }

    if (m_voiceService) {
        disconnect(m_voiceService, nullptr, this, nullptr);
    }

    m_voiceService = service;

    if (m_voiceService) {
        connect(m_voiceService, &network::VoiceService::stateChanged,
                this, &CallContext::onStateChanged);
        connect(m_voiceService, &network::VoiceService::incomingCall,
                this, &CallContext::onIncomingCall);
        connect(m_voiceService, &network::VoiceService::callEnded,
                this, &CallContext::onCallEnded);
        connect(m_voiceService, &network::VoiceService::errorOccurred,
                this, &CallContext::onErrorOccurred);
        connect(m_voiceService, &network::VoiceService::participantsChanged,
                this, &CallContext::participantsChanged);
        connect(m_voiceService, &network::VoiceService::participantJoined,
                this, [this](const QHostAddress &address) { emit participantJoined(address.toString()); });
        connect(m_voiceService, &network::VoiceService::participantLeft,
                this, [this](const QHostAddress &address, const QString &reason) {
                    emit participantLeft(address.toString(), reason);
                });
        connect(m_voiceService, &network::VoiceService::participantDeclined,
                this, [this](const QHostAddress &address, const QString &reason) {
                    emit participantDeclined(address.toString(), reason);
                });

        // Etat initial : VoiceService peut deja exister depuis un moment
        // (creee tot dans Application::initialize()) au moment ou ce
        // contexte lui est attache ; on resynchronise plutot que de rester
        // bloque sur "idle" par defaut.
        onStateChanged(m_voiceService->state());
    }

    emit voiceServiceChanged();
}

bool CallContext::isMuted() const
{
    return m_voiceService ? m_voiceService->isMuted() : false;
}

void CallContext::setMuted(bool muted)
{
    if (!m_voiceService || m_voiceService->isMuted() == muted) {
        return;
    }
    m_voiceService->setMuted(muted);
    emit mutedChanged();
}

bool CallContext::call(const QString &address, int signalingPort)
{
    if (!m_voiceService) {
        emit errorOccurred(tr("Le service d'appel n'est pas disponible."));
        return false;
    }

    const QHostAddress host(address);
    if (host.isNull()) {
        emit errorOccurred(tr("Adresse invalide : %1").arg(address));
        return false;
    }

    const quint16 port = signalingPort > 0 ? static_cast<quint16>(signalingPort)
                                          : network::VoiceService::defaultSignalingPort();
    const bool started = m_voiceService->call(host, port);
    if (started) {
        m_remoteAddress = address;
        emit remoteAddressChanged();
    }
    return started;
}

bool CallContext::callGroup(const QVariantList &peers)
{
    if (!m_voiceService) {
        emit errorOccurred(tr("Le service d'appel n'est pas disponible."));
        return false;
    }
    QList<QPair<QHostAddress, quint16>> targets;
    for (const QVariant &value : peers) {
        const QVariantMap peer = value.toMap();
        const QHostAddress host(peer.value(QStringLiteral("address")).toString());
        if (host.isNull())
            continue;
        const int port = peer.value(QStringLiteral("signalingPort")).toInt();
        targets.append(qMakePair(host, port > 0 ? static_cast<quint16>(port)
                                                : network::VoiceService::defaultSignalingPort()));
    }
    if (targets.isEmpty() || targets.size() > network::VoiceService::kMaxParticipants - 1)
        return false;
    const bool started = m_voiceService->callGroup(targets);
    if (started) {
        m_remoteAddress = targets.first().first.toString();
        emit remoteAddressChanged();
    }
    return started;
}

bool CallContext::invite(const QString &address, int signalingPort)
{
    if (!m_voiceService)
        return false;
    const QHostAddress host(address);
    if (host.isNull())
        return false;
    const quint16 port = signalingPort > 0 ? static_cast<quint16>(signalingPort)
                                          : network::VoiceService::defaultSignalingPort();
    return m_voiceService->invite(host, port);
}

QVariantList CallContext::participants() const
{
    QVariantList list;
    if (!m_voiceService)
        return list;
    for (const network::VoiceParticipant &p : m_voiceService->participants()) {
        QVariantMap entry;
        entry[QStringLiteral("address")] = p.address.toString();
        entry[QStringLiteral("port")] = p.port;
        entry[QStringLiteral("status")] = p.status;
        entry[QStringLiteral("muted")] = p.muted;
        entry[QStringLiteral("speaking")] = p.speaking;
        list.append(entry);
    }
    return list;
}

QVariantList CallContext::inviteRoster() const
{
    QVariantList list;
    if (!m_voiceService)
        return list;
    for (const network::SignalingRosterEntry &e : m_voiceService->inviteRoster()) {
        QVariantMap entry;
        entry[QStringLiteral("address")] = e.address;
        entry[QStringLiteral("port")] = e.port;
        list.append(entry);
    }
    return list;
}

bool CallContext::isGroupCall() const
{
    return m_voiceService && m_voiceService->isGroupCall();
}

bool CallContext::canInvite() const
{
    return m_voiceService && m_voiceService->canInvite();
}

bool CallContext::isLocalSpeaking() const
{
    return m_voiceService && m_voiceService->isLocalSpeaking();
}

void CallContext::acceptCall()
{
    if (m_voiceService) {
        m_voiceService->acceptCall();
    }
}

void CallContext::hangUp()
{
    if (m_voiceService) {
        m_voiceService->hangUp();
    }
}

void CallContext::toggleMute()
{
    setMuted(!isMuted());
}

void CallContext::onStateChanged(network::CallState state)
{
    const QString newState = stateToString(state);
    if (m_callState == newState) {
        return;
    }
    m_callState = newState;
    emit callStateChanged();
    // canInvite depend aussi de l'etat de l'appel.
    emit participantsChanged();

    if (state == network::CallState::Idle && !m_remoteAddress.isEmpty()) {
        m_remoteAddress.clear();
        emit remoteAddressChanged();
    }

    // Le mute local ne survit pas a un appel : on repart propre au suivant
    // (evite la surprise "je suis mute sans l'avoir demande" au prochain
    // appel si l'utilisateur avait coupe son micro juste avant de raccrocher).
    if (state == network::CallState::Idle && m_voiceService && m_voiceService->isMuted()) {
        m_voiceService->setMuted(false);
        emit mutedChanged();
    }
}

void CallContext::onIncomingCall(const QHostAddress &callerAddress)
{
    m_remoteAddress = callerAddress.toString();
    emit remoteAddressChanged();
    emit incomingCall(m_remoteAddress);
}

void CallContext::onCallEnded(const QString &reason)
{
    emit callEnded(reason);
}

void CallContext::onErrorOccurred(const QString &message)
{
    emit errorOccurred(message);
}

QString CallContext::stateToString(network::CallState state)
{
    switch (state) {
    case network::CallState::Idle:       return QStringLiteral("idle");
    case network::CallState::Calling:    return QStringLiteral("calling");
    case network::CallState::Ringing:    return QStringLiteral("ringing");
    case network::CallState::Connecting: return QStringLiteral("connecting");
    case network::CallState::Connected:  return QStringLiteral("connected");
    case network::CallState::Ending:     return QStringLiteral("ending");
    }
    return QStringLiteral("idle");
}

} // namespace core
