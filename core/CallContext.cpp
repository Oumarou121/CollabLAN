#include "CallContext.h"

#include <QHostAddress>

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
