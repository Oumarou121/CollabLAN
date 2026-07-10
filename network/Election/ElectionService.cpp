#include "ElectionService.h"

#include <QUdpSocket>
#include <QNetworkDatagram>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>
#include <QUuid>
#include <QNetworkInterface>
#include <algorithm>

namespace network {

namespace {
const char *kPacketType = "collablan.election";
const int kPacketVersion = 1;

const char *kMsgHeartbeat = "heartbeat";
const char *kMsgElectionCandidate = "election_candidate";
const char *kMsgServerPromoted = "server_promoted";
}

ElectionService::ElectionService(QObject *parent)
    : QObject(parent)
{
    m_localMachineUuid = QUuid::createUuid().toString(QUuid::WithoutBraces);

    m_socket = new QUdpSocket(this);
    connect(m_socket, &QUdpSocket::readyRead, this, &ElectionService::readPendingDatagrams);

    m_heartbeatTimer = new QTimer(this);
    connect(m_heartbeatTimer, &QTimer::timeout, this, &ElectionService::sendHeartbeat);

    m_timeoutTimer = new QTimer(this);
    connect(m_timeoutTimer, &QTimer::timeout, this, &ElectionService::checkHeartbeatTimeout);

    m_electionWindowTimer = new QTimer(this);
    m_electionWindowTimer->setSingleShot(true);
    connect(m_electionWindowTimer, &QTimer::timeout, this, &ElectionService::concludeElection);
}

ElectionService::~ElectionService()
{
    stop();
}

bool ElectionService::start()
{
    if (m_running)
        return true;

    const bool bound = m_socket->bind(
        QHostAddress::AnyIPv4,
        m_port,
        QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint);

    if (!bound)
        return false;

    m_running = true;
    m_heartbeatEverSeen = false;
    m_lastHeartbeatSeenMs = QDateTime::currentMSecsSinceEpoch();

    // Si ce poste demarre deja en role Server/TempServer (etat restaure
    // depuis la base), il commence a emettre son heartbeat immediatement.
    if (m_role == models::ServerRole::Server || m_role == models::ServerRole::TempServer) {
        m_activeServerUuid = m_localMachineUuid;
        sendHeartbeat();
    }

    m_heartbeatTimer->start(m_heartbeatIntervalMs);
    // Verification periodique du timeout, a une cadence plus fine que le
    // timeout lui-meme pour ne pas rater la fenetre.
    m_timeoutTimer->start(qMax(500, m_heartbeatTimeoutMs / 4));

    emit started();
    return true;
}

void ElectionService::stop()
{
    if (!m_running)
        return;

    m_heartbeatTimer->stop();
    m_timeoutTimer->stop();
    m_electionWindowTimer->stop();
    m_socket->close();
    m_candidates.clear();
    m_electionInProgress = false;
    m_running = false;

    emit stopped();
}

bool ElectionService::isRunning() const
{
    return m_running;
}

QString ElectionService::localMachineUuid() const
{
    return m_localMachineUuid;
}

void ElectionService::setLocalMachineUuid(const QString &uuid)
{
    if (!uuid.isEmpty())
        m_localMachineUuid = uuid;
}

int ElectionService::priorityWeight() const
{
    return m_priorityWeight;
}

void ElectionService::setPriorityWeight(int weight)
{
    m_priorityWeight = weight;
}

quint16 ElectionService::port() const
{
    return m_port;
}

void ElectionService::setPort(quint16 port)
{
    if (m_running) {
        qWarning("ElectionService::setPort: impossible de changer le port pendant l'execution, appelez stop() d'abord.");
        return;
    }
    m_port = port;
}

int ElectionService::heartbeatIntervalMs() const
{
    return m_heartbeatIntervalMs;
}

void ElectionService::setHeartbeatIntervalMs(int ms)
{
    m_heartbeatIntervalMs = ms;
    if (m_running)
        m_heartbeatTimer->start(m_heartbeatIntervalMs);
}

int ElectionService::heartbeatTimeoutMs() const
{
    return m_heartbeatTimeoutMs;
}

void ElectionService::setHeartbeatTimeoutMs(int ms)
{
    m_heartbeatTimeoutMs = ms;
    if (m_running)
        m_timeoutTimer->start(qMax(500, m_heartbeatTimeoutMs / 4));
}

int ElectionService::electionWindowMs() const
{
    return m_electionWindowMs;
}

void ElectionService::setElectionWindowMs(int ms)
{
    m_electionWindowMs = ms;
}

void ElectionService::setInitialState(models::ServerRole role, int epoch)
{
    m_role = role;
    m_epoch = epoch;
    if (role == models::ServerRole::Server || role == models::ServerRole::TempServer)
        m_activeServerUuid = m_localMachineUuid;
}

models::ServerRole ElectionService::role() const
{
    return m_role;
}

int ElectionService::epoch() const
{
    return m_epoch;
}

QString ElectionService::activeServerUuid() const
{
    return m_activeServerUuid;
}

void ElectionService::reclaimAsOfficialServer()
{
    // Section 7.3 : une fois la fusion confirmee (sync_ack, hors perimetre
    // de ce service), le serveur officiel reprend la main : nouvel epoch,
    // diffusion server_promoted(temporary=false).
    enterServerRole(m_epoch + 1, /*temporary=*/false);
}

void ElectionService::sendHeartbeat()
{
    if (!m_running)
        return;
    if (m_role != models::ServerRole::Server && m_role != models::ServerRole::TempServer)
        return;

    QJsonObject packet;
    packet["type"] = QString::fromLatin1(kPacketType);
    packet["version"] = kPacketVersion;
    packet["msg"] = QString::fromLatin1(kMsgHeartbeat);
    packet["server_uuid"] = m_localMachineUuid;
    packet["epoch"] = m_epoch;

    broadcastPacket(QJsonDocument(packet).toJson(QJsonDocument::Compact));
}

void ElectionService::checkHeartbeatTimeout()
{
    if (!m_running)
        return;

    // Un poste en role Server/TempServer n'a pas a surveiller son propre
    // heartbeat : c'est lui qui l'emet.
    if (m_role == models::ServerRole::Server || m_role == models::ServerRole::TempServer)
        return;

    if (m_electionInProgress)
        return;

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - m_lastHeartbeatSeenMs > m_heartbeatTimeoutMs) {
        emit heartbeatLost();
        startElection();
    }
}

void ElectionService::startElection()
{
    m_electionInProgress = true;
    m_candidates.clear();

    Candidate self{m_localMachineUuid, m_priorityWeight};
    m_candidates.append(self);

    QJsonObject packet;
    packet["type"] = QString::fromLatin1(kPacketType);
    packet["version"] = kPacketVersion;
    packet["msg"] = QString::fromLatin1(kMsgElectionCandidate);
    packet["priority_weight"] = m_priorityWeight;
    packet["machine_uuid"] = m_localMachineUuid;

    broadcastPacket(QJsonDocument(packet).toJson(QJsonDocument::Compact));

    emit electionStarted();
    m_electionWindowTimer->start(m_electionWindowMs);
}

bool ElectionService::isBetterCandidate(const Candidate &a, const Candidate &b) const
{
    if (a.priorityWeight != b.priorityWeight)
        return a.priorityWeight < b.priorityWeight;
    return a.machineUuid < b.machineUuid;
}

void ElectionService::concludeElection()
{
    if (!m_electionInProgress)
        return;
    m_electionInProgress = false;

    if (m_candidates.isEmpty())
        return;

    Candidate winner = m_candidates.first();
    for (const Candidate &c : std::as_const(m_candidates)) {
        if (isBetterCandidate(c, winner))
            winner = c;
    }

    m_candidates.clear();

    if (winner.machineUuid == m_localMachineUuid) {
        enterServerRole(m_epoch + 1, /*temporary=*/true);
    }
    // Sinon : ce poste attend le server_promoted du gagnant (section 5.4),
    // il reste Client en attendant.
}

void ElectionService::enterServerRole(int newEpoch, bool temporary)
{
    const models::ServerRole newRole = temporary ? models::ServerRole::TempServer : models::ServerRole::Server;

    m_epoch = newEpoch;
    m_activeServerUuid = m_localMachineUuid;
    applyRole(newRole);

    QJsonObject packet;
    packet["type"] = QString::fromLatin1(kPacketType);
    packet["version"] = kPacketVersion;
    packet["msg"] = QString::fromLatin1(kMsgServerPromoted);
    packet["epoch"] = m_epoch;
    packet["machine_uuid"] = m_localMachineUuid;
    packet["temporary"] = temporary;

    broadcastPacket(QJsonDocument(packet).toJson(QJsonDocument::Compact));

    if (m_running && !m_heartbeatTimer->isActive())
        m_heartbeatTimer->start(m_heartbeatIntervalMs);
    // Emission immediate pour ne pas attendre le premier tick du timer :
    // les autres postes doivent basculer au plus vite (section 5.4/7.4).
    sendHeartbeat();

    emit serverPromoted(m_epoch, m_localMachineUuid, temporary);
}

void ElectionService::applyRole(models::ServerRole newRole)
{
    if (newRole == m_role)
        return;
    const models::ServerRole previous = m_role;
    m_role = newRole;
    emit roleChanged(newRole, previous);
}

void ElectionService::broadcastPacket(const QByteArray &data)
{
    if (!m_socket)
        return;

    m_socket->writeDatagram(data, QHostAddress::Broadcast, m_port);

    const auto interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : interfaces) {
        if (!(iface.flags() & QNetworkInterface::IsUp) || !(iface.flags() & QNetworkInterface::IsRunning))
            continue;
        if (iface.flags() & QNetworkInterface::IsLoopBack)
            continue;

        const auto entries = iface.addressEntries();
        for (const QNetworkAddressEntry &entry : entries) {
            const QHostAddress broadcastAddr = entry.broadcast();
            if (!broadcastAddr.isNull())
                m_socket->writeDatagram(data, broadcastAddr, m_port);
        }
    }
}

void ElectionService::readPendingDatagrams()
{
    while (m_socket->hasPendingDatagrams()) {
        const QNetworkDatagram datagram = m_socket->receiveDatagram();
        if (!datagram.isValid())
            continue;
        handlePacket(datagram.data());
    }
}

void ElectionService::handlePacket(const QByteArray &data)
{
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject())
        return;

    const QJsonObject obj = doc.object();
    if (obj.value("type").toString() != QString::fromLatin1(kPacketType))
        return;

    const QString msg = obj.value("msg").toString();

    if (msg == QString::fromLatin1(kMsgHeartbeat)) {
        const QString serverUuid = obj.value("server_uuid").toString();
        if (serverUuid.isEmpty() || serverUuid == m_localMachineUuid)
            return;

        const int remoteEpoch = obj.value("epoch").toInt();
        // Un heartbeat perime (epoch inferieur) est ignore : le serveur
        // legitime courant a deja une vue plus recente.
        if (remoteEpoch < m_epoch)
            return;

        m_lastHeartbeatSeenMs = QDateTime::currentMSecsSinceEpoch();
        m_heartbeatEverSeen = true;
        m_activeServerUuid = serverUuid;

        // Section 7.1 : le Server officiel qui etait hors-ligne et revient
        // constate qu'un autre poste emet deja un heartbeat en son nom (un
        // TempServer a pris le relais) : point d'accroche pour la
        // reconciliation via le futur SyncService.
        if (m_role == models::ServerRole::Server && serverUuid != m_localMachineUuid) {
            emit reconciliationRequired(serverUuid);
        }
        return;
    }

    if (msg == QString::fromLatin1(kMsgElectionCandidate)) {
        if (!m_electionInProgress)
            return; // on ne participe qu'aux elections qu'on a nous-memes detectees

        const QString machineUuid = obj.value("machine_uuid").toString();
        if (machineUuid.isEmpty() || machineUuid == m_localMachineUuid)
            return;

        Candidate c;
        c.machineUuid = machineUuid;
        c.priorityWeight = obj.value("priority_weight").toInt(100);
        m_candidates.append(c);
        return;
    }

    if (msg == QString::fromLatin1(kMsgServerPromoted)) {
        const int remoteEpoch = obj.value("epoch").toInt();
        const QString machineUuid = obj.value("machine_uuid").toString();
        const bool temporary = obj.value("temporary").toBool();

        // Le broadcast UDP boucle generalement vers l'emetteur lui-meme sur le
        // meme hote : on ignore silencieusement notre propre server_promoted
        // (deja applique et deja emis dans enterServerRole()), avant meme de
        // regarder l'epoch, pour ne pas se le faire rejeter comme split-brain.
        if (machineUuid == m_localMachineUuid)
            return;

        // Regle anti split-brain (section 7) : tout server_promoted avec un
        // epoch <= epoch local est ignore.
        if (remoteEpoch <= m_epoch) {
            emit splitBrainAttemptIgnored(remoteEpoch, machineUuid);
            return;
        }

        m_epoch = remoteEpoch;
        m_activeServerUuid = machineUuid;
        m_lastHeartbeatSeenMs = QDateTime::currentMSecsSinceEpoch();
        m_heartbeatEverSeen = true;

        // Une election en cours localement est annulee : quelqu'un d'autre
        // a deja tranche avec un epoch superieur.
        m_electionInProgress = false;
        m_electionWindowTimer->stop();
        m_candidates.clear();

        // Un autre poste a ete promu : on redevient/reste Client et on
        // bascule notre connexion vers lui (a la charge de l'appelant, via
        // activeServerUuid() / le signal serverPromoted).
        applyRole(models::ServerRole::Client);
        emit serverPromoted(m_epoch, machineUuid, temporary);
        return;
    }
}

} // namespace network
