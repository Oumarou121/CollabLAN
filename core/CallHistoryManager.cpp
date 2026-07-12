#include "CallHistoryManager.h"

#include <QDebug>
#include <QUuid>

#include "database/DatabaseManager.h"
#include "UserManager.h"
#include "Discovery/DiscoveryService.h"

namespace core {

CallHistoryManager::CallHistoryManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_repository(dbManager ? dbManager->database() : QSqlDatabase())
{
}

CallHistoryManager::~CallHistoryManager() = default;

void CallHistoryManager::setVoiceService(network::VoiceService *voiceService)
{
    if (m_voiceService) {
        m_voiceService->disconnect(this);
    }

    m_voiceService = voiceService;
    if (!m_voiceService) {
        return;
    }

    connect(m_voiceService, &network::VoiceService::outgoingCallStarted,
            this, &CallHistoryManager::onOutgoingCallStarted);
    connect(m_voiceService, &network::VoiceService::incomingCall,
            this, &CallHistoryManager::onIncomingCall);
    connect(m_voiceService, &network::VoiceService::stateChanged,
            this, &CallHistoryManager::onStateChanged);
    connect(m_voiceService, &network::VoiceService::callEnded,
            this, &CallHistoryManager::onCallEnded);
}

void CallHistoryManager::setUserManager(UserManager *userManager)
{
    m_userManager = userManager;
}

void CallHistoryManager::setDiscoveryService(network::DiscoveryService *discoveryService)
{
    m_discoveryService = discoveryService;
}

std::vector<models::CallHistoryEntry> CallHistoryManager::allCalls(int limit, int offset) const
{
    return m_repository.findAll(limit, offset);
}

std::vector<models::CallHistoryEntry> CallHistoryManager::userCalls(int userId, int limit, int offset) const
{
    return m_repository.findByUser(userId, limit, offset);
}

QString CallHistoryManager::resolvePeerName(const QHostAddress &peerAddress) const
{
    if (!m_discoveryService) {
        return QString();
    }
    const QList<network::DiscoveredPeer> peers = m_discoveryService->peers();
    for (const network::DiscoveredPeer &peer : peers) {
        if (peer.address == peerAddress) {
            return peer.name;
        }
    }
    return QString();
}

void CallHistoryManager::beginEntry(network::CallState triggerState, models::CallDirection direction,
                                     const QHostAddress &peerAddress)
{
    Q_UNUSED(triggerState);

    models::CallHistoryEntry entry;
    entry.setCallUuid(QUuid::createUuid().toString(QUuid::WithoutBraces));
    entry.setLocalUserId(m_userManager && m_userManager->currentUserId().has_value()
                              ? *m_userManager->currentUserId() : -1);
    entry.setDirection(direction);
    entry.setPeerAddress(peerAddress.toString());
    entry.setPeerName(resolvePeerName(peerAddress));
    entry.setStatus(models::CallStatus::InProgress);
    entry.setStartedAt(QDateTime::currentDateTimeUtc());

    const int id = m_repository.create(entry);
    if (id < 0) {
        qWarning() << "CallHistoryManager: echec de l'enregistrement de l'appel -"
                   << m_repository.lastError();
        resetActiveState();
        return;
    }

    entry.setId(id);
    m_activeId = id;
    m_activeDirection = direction;
    m_activeReachedConnected = false;
    m_activeConnectedAt = QDateTime();
    m_activeLastState = triggerState;

    emit callRecorded(id, entry);
}

void CallHistoryManager::resetActiveState()
{
    m_activeId = -1;
    m_activeReachedConnected = false;
    m_activeConnectedAt = QDateTime();
    m_activeLastState = network::CallState::Idle;
}

void CallHistoryManager::onOutgoingCallStarted(const QHostAddress &peerAddress)
{
    beginEntry(network::CallState::Calling, models::CallDirection::Outgoing, peerAddress);
}

void CallHistoryManager::onIncomingCall(const QHostAddress &peerAddress)
{
    // Emis avant que VoiceService ne passe a l'etat Ringing (voir
    // VoiceService::incomingCall) : on enregistre l'entree des ce point,
    // m_activeLastState sera mis a jour vers Ringing par onStateChanged()
    // juste apres.
    beginEntry(network::CallState::Idle, models::CallDirection::Incoming, peerAddress);
}

void CallHistoryManager::onStateChanged(network::CallState state)
{
    if (m_activeId <= 0) {
        return;
    }

    if (state == network::CallState::Connected && !m_activeReachedConnected) {
        m_activeReachedConnected = true;
        m_activeConnectedAt = QDateTime::currentDateTimeUtc();
        m_repository.markConnected(m_activeId, m_activeConnectedAt);
    }

    // On ne retient que le dernier etat *actif* (jamais Idle) atteint
    // avant la bascule finale : teardownSession() passe toujours
    // directement d'un etat actif a Idle (l'etat "Ending" de l'enum n'est
    // en pratique jamais utilise), donc au moment ou callEnded() sera
    // recu, m_activeLastState contiendra encore la bonne valeur.
    if (state != network::CallState::Idle) {
        m_activeLastState = state;
    }
}

void CallHistoryManager::onCallEnded(const QString &reason)
{
    if (m_activeId <= 0) {
        return;
    }

    const int id = m_activeId;
    const QDateTime endedAt = QDateTime::currentDateTimeUtc();

    models::CallStatus status;
    std::optional<int> durationSeconds;

    if (m_activeReachedConnected) {
        status = models::CallStatus::Completed;
        durationSeconds = static_cast<int>(m_activeConnectedAt.secsTo(endedAt));
    } else if (m_activeDirection == models::CallDirection::Outgoing) {
        if (reason == QStringLiteral("local-hangup")) {
            status = models::CallStatus::Cancelled;
        } else if (reason == QStringLiteral("remote-hangup")) {
            status = models::CallStatus::Rejected;
        } else {
            status = models::CallStatus::Failed;
        }
    } else { // Incoming, jamais connecte
        if (m_activeLastState == network::CallState::Ringing) {
            status = (reason == QStringLiteral("local-hangup"))
                         ? models::CallStatus::Rejected
                         : models::CallStatus::Missed;
        } else {
            // Deja accepte (Connecting) mais jamais totalement etabli :
            // classe comme echec technique plutot que "manque".
            status = models::CallStatus::Failed;
        }
    }

    m_repository.markEnded(id, status, endedAt, durationSeconds);
    resetActiveState();

    emit callFinalized(id, status);
}

} // namespace core
