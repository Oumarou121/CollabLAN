#include "CallContext.h"
#include "ScreenCapture.h"

#include <QHostAddress>
#include <QVariantMap>

namespace core {

CallContext::CallContext(QObject *parent)
    : QObject(parent)
    , m_capture(new ScreenCapture(this))
{
    connect(m_capture, &ScreenCapture::frameReady, this, [this](const QImage &frame) {
        if (!m_voiceService)
            return;
        m_voiceService->pushScreenFrame(frame);
        // Apercu de la bande (presentateur) : une image par seconde suffit.
        if (!m_localFrameAge.isValid() || m_localFrameAge.elapsed() > 1000) {
            m_localFrameAge.start();
            ++m_localFrameId;
            emit localFrameChanged();
        }
    });
    connect(m_capture, &ScreenCapture::failed, this, [this](const QString &message) {
        if (m_voiceService)
            m_voiceService->stopPresenting();
        emit errorOccurred(tr("La présentation s'est arrêtée : %1").arg(message));
        emit presentingStopped(QStringLiteral("capture"));
    });
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
        connect(m_voiceService, &network::VoiceService::presentationChanged,
                this, &CallContext::onPresentationChanged);
        connect(m_voiceService, &network::VoiceService::remoteScreenChanged, this, [this]() {
            ++m_screenFrameId;
            emit screenFrameChanged();
        });
        connect(m_voiceService, &network::VoiceService::presentingInterrupted, this, [this](const QString &reason) {
            m_capture->stop();
            emit presentingStopped(reason);
        });
        connect(m_voiceService, &network::VoiceService::screenUnsupported,
                this, [this](const QHostAddress &address) { emit screenUnsupported(address.toString()); });

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

// ---- Partage d'ecran ------------------------------------------------------

bool CallContext::isPresenting() const
{
    return m_voiceService && m_voiceService->isPresenting();
}

bool CallContext::canPresent() const
{
    return m_voiceService && m_voiceService->canPresent();
}

QString CallContext::presentingTitle() const
{
    return m_voiceService ? m_voiceService->presentingTitle() : QString();
}

QString CallContext::presenterAddress() const
{
    if (!m_voiceService)
        return QString();
    const QHostAddress address = m_voiceService->presenterAddress();
    return address.isNull() ? QString() : address.toString();
}

QString CallContext::presenterTitle() const
{
    return m_voiceService ? m_voiceService->presenterTitle() : QString();
}

bool CallContext::isScreenSlow() const
{
    return m_voiceService && m_voiceService->isRemoteScreenSlow();
}

QImage CallContext::remoteScreen() const
{
    return m_voiceService ? m_voiceService->remoteScreen() : QImage();
}

QImage CallContext::localScreen() const
{
    return m_voiceService ? m_voiceService->localScreenFrame() : QImage();
}

QImage CallContext::sourceThumbnail(const QString &sourceId) const
{
    // Apercus pris par shareSources() : QScreen::grabWindow ne doit etre
    // appele que sur le fil de l interface (sous X11 notamment), jamais depuis
    // le fil de chargement des images.
    return m_thumbnails.value(sourceId);
}

QVariantList CallContext::shareSources()
{
    QVariantList list;
    m_thumbnails.clear();
    for (const ScreenCapture::Source &source : m_capture->sources()) {
        if (source.kind == QLatin1String("screen"))
            m_thumbnails.insert(source.id, m_capture->thumbnail(source.id, 320));
        QVariantMap entry;
        entry[QStringLiteral("id")] = source.id;
        entry[QStringLiteral("kind")] = source.kind;
        entry[QStringLiteral("title")] = source.title;
        entry[QStringLiteral("detail")] = source.detail;
        list.append(entry);
    }
    return list;
}

bool CallContext::startPresenting(const QString &sourceId)
{
    if (!m_voiceService || !m_voiceService->canPresent())
        return false;
    if (!m_capture->start(sourceId)) {
        emit errorOccurred(tr("Cet écran ou cette fenêtre ne peut pas être capturé."));
        return false;
    }
    if (!m_voiceService->startPresenting(m_capture->title())) {
        m_capture->stop();
        return false;
    }
    return true;
}

void CallContext::stopPresenting()
{
    m_capture->stop();
    if (m_voiceService)
        m_voiceService->stopPresenting();
}

void CallContext::onPresentationChanged()
{
    // Presentation terminee ailleurs (appel fini, conflit) : la capture s'arrete.
    if (m_voiceService && !m_voiceService->isPresenting() && m_capture->isActive())
        m_capture->stop();
    const QString presenter = presenterAddress();
    if (presenter != m_lastPresenter) {
        const QString previous = m_lastPresenter;
        m_lastPresenter = presenter;
        if (!previous.isEmpty())
            emit presentationStopped(previous);
        if (!presenter.isEmpty())
            emit presentationStarted(presenter);
    }
    emit presentationChanged();
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
    // canInvite et canPresent dependent aussi de l'etat de l'appel.
    emit participantsChanged();
    emit presentationChanged();

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
