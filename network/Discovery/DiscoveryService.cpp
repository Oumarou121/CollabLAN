#include "DiscoveryService.h"

#include <QUdpSocket>
#include <QNetworkDatagram>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QHostInfo>
#include <QUuid>
#include <QDateTime>
#include <QNetworkInterface>
#include <QMetaObject>

namespace network {

namespace {
// Marqueur inclus dans chaque paquet pour ignorer tout trafic UDP
// broadcast qui ne proviendrait pas de LocaLink (autre appli sur le meme port).
const char *kPacketType = "localink.discovery";
const int kPacketVersion = 1;
}

DiscoveryService::DiscoveryService(QObject *parent)
    : QObject(parent)
{
    qRegisterMetaType<network::DiscoveredPeer>("network::DiscoveredPeer");

    m_localId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_localName = QHostInfo::localHostName();

    m_socket = new QUdpSocket(this);
    connect(m_socket, &QUdpSocket::readyRead, this, &DiscoveryService::readPendingDatagrams);

    m_announceTimer = new QTimer(this);
    connect(m_announceTimer, &QTimer::timeout, this, &DiscoveryService::sendAnnounce);

    m_cleanupTimer = new QTimer(this);
    connect(m_cleanupTimer, &QTimer::timeout, this, &DiscoveryService::checkStalePeers);
}

DiscoveryService::~DiscoveryService()
{
    stop();
}

bool DiscoveryService::start()
{
    if (m_running)
        return true;

    // ShareAddress + ReuseAddressHint permettent a plusieurs instances de
    // l'application (y compris sur la meme machine, utile pour les tests
    // locaux) de se lier au meme port UDP simultanement.
    const bool bound = m_socket->bind(
        QHostAddress::AnyIPv4,
        m_port,
        QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint);

    if (!bound)
        return false;

    m_running = true;

    // Premiere annonce immediate pour minimiser le delai de decouverte,
    // puis annonces periodiques.
    sendAnnounce();
    m_announceTimer->start(m_announceIntervalMs);
    m_cleanupTimer->start(qMax(1000, m_peerTimeoutMs / 2));

    emit started();
    return true;
}

void DiscoveryService::stop()
{
    if (!m_running)
        return;

    m_announceTimer->stop();
    m_cleanupTimer->stop();
    m_socket->close();
    m_peers.clear();
    m_running = false;

    emit stopped();
}

bool DiscoveryService::isRunning() const
{
    return m_running;
}

QString DiscoveryService::localId() const
{
    return m_localId;
}

void DiscoveryService::setLocalId(const QString &id)
{
    if (id.isEmpty()) return;
    if (m_running) {
        qWarning() << "[Discovery] setLocalId() ignoré : DiscoveryService déjà démarré avec"
                   << m_localId;
        return;
    }
    m_localId = id;
}

QString DiscoveryService::localName() const
{
    return m_localName;
}

void DiscoveryService::setLocalName(const QString &name)
{
    m_localName = name;
}

QString DiscoveryService::localUserUuid() const
{
    return m_localUserUuid;
}

void DiscoveryService::setLocalUserUuid(const QString &uuid)
{
    m_localUserUuid = uuid;
}

void DiscoveryService::setLocalCertificateFingerprint(const QString &fingerprint)
{
    m_localCertificateFingerprint = fingerprint.toLower();
}

QString DiscoveryService::localStatus() const
{
    return m_localStatus;
}

void DiscoveryService::setLocalStatus(const QString &status)
{
    if (m_localStatus == status) return;
    m_localStatus = status;
    emit localStatusChanged();
}

quint16 DiscoveryService::port() const
{
    return m_port;
}

void DiscoveryService::setPort(quint16 port)
{
    if (m_running) {
        qWarning("DiscoveryService::setPort: impossible de changer le port pendant l'execution, appelez stop() d'abord.");
        return;
    }
    m_port = port;
}

int DiscoveryService::announceIntervalMs() const
{
    return m_announceIntervalMs;
}

void DiscoveryService::setAnnounceIntervalMs(int ms)
{
    m_announceIntervalMs = ms;
    if (m_running)
        m_announceTimer->start(m_announceIntervalMs);
}

int DiscoveryService::peerTimeoutMs() const
{
    return m_peerTimeoutMs;
}

void DiscoveryService::setPeerTimeoutMs(int ms)
{
    m_peerTimeoutMs = ms;
    if (m_running)
        m_cleanupTimer->start(qMax(1000, m_peerTimeoutMs / 2));
}

QList<DiscoveredPeer> DiscoveryService::peers() const
{
    return m_peers.values();
}

QVariantList DiscoveryService::machineCandidates() const
{
    QVariantList result;
    for (const auto &peer : m_peers) {
        QVariantMap candidate;
        candidate.insert(QStringLiteral("id"), peer.id);
        candidate.insert(QStringLiteral("name"), peer.name);
        candidate.insert(QStringLiteral("ip"), peer.address.toString());
        candidate.insert(QStringLiteral("fingerprint"), peer.certificateFingerprint);
        result.append(candidate);
    }
    return result;
}

void DiscoveryService::setPermissionManager(QObject *manager)
{
    m_permissionManager = manager;
}

quint16 DiscoveryService::transferPort() const
{
    return m_transferPort;
}

void DiscoveryService::setTransferPort(quint16 port)
{
    m_transferPort = port;
}

quint16 DiscoveryService::signalingPort() const
{
    return m_signalingPort;
}

void DiscoveryService::setSignalingPort(quint16 port)
{
    m_signalingPort = port;
}

void DiscoveryService::sendAnnounce()
{
    QJsonObject packet;
    packet["type"] = QString::fromLatin1(kPacketType);
    packet["version"] = kPacketVersion;
    packet["id"] = m_localId;
    packet["name"] = m_localName;
    // Bug #2 (recipient_uuid toujours vide) : diffuse aussi le compte
    // utilisateur actuellement connecte, comme le fait deja "name" pour le
    // nom d'utilisateur. Absent (chaine vide) tant qu'aucune authentification
    // n'a reussi sur ce poste, cf. setLocalUserUuid().
    packet["userUuid"] = m_localUserUuid;
    packet["certificateFingerprint"] = m_localCertificateFingerprint;
    packet["status"] = m_localStatus;
    packet["port"] = m_port;
    packet["transferPort"] = static_cast<int>(m_transferPort);
    packet["signalingPort"] = static_cast<int>(m_signalingPort);

    const QByteArray data = QJsonDocument(packet).toJson(QJsonDocument::Compact);

    // Broadcast global : simple et suffisant pour un reseau local plat (LAN).
    m_socket->writeDatagram(data, QHostAddress::Broadcast, m_port);

    // Complement : diffuse aussi sur l'adresse de broadcast de chaque
    // interface active, pour couvrir les configurations ou le broadcast
    // "255.255.255.255" est filtre par certains routeurs/VM.
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

void DiscoveryService::readPendingDatagrams()
{
    while (m_socket->hasPendingDatagrams()) {
        const QNetworkDatagram datagram = m_socket->receiveDatagram();
        if (!datagram.isValid())
            continue;

        handleAnnouncePacket(datagram.data(), datagram.senderAddress());
    }
}

void DiscoveryService::handleAnnouncePacket(const QByteArray &data, const QHostAddress &senderAddress)
{
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject())
        return;

    const QJsonObject obj = doc.object();
    if (obj.value("type").toString() != QString::fromLatin1(kPacketType))
        return; // trafic UDP non lie a LocaLink sur ce port : on ignore

    const QString peerId = obj.value("id").toString();
    if (peerId.isEmpty() || peerId == m_localId)
        return; // annonce invalide ou provenant de nous-memes

    DiscoveredPeer peer;
    peer.id = peerId;
    peer.name = obj.value("name").toString();
    peer.userUuid = obj.value("userUuid").toString();
    peer.certificateFingerprint = obj.value("certificateFingerprint").toString().toLower();
    peer.status = obj.value("status").toString(QStringLiteral("online"));
    peer.address = senderAddress;
    peer.port = static_cast<quint16>(obj.value("port").toInt(m_port));
    peer.transferPort = static_cast<quint16>(obj.value("transferPort").toInt(m_transferPort));
    peer.signalingPort = static_cast<quint16>(obj.value("signalingPort").toInt(m_signalingPort));
    peer.lastSeenMs = QDateTime::currentMSecsSinceEpoch();

    const auto existingIt = m_peers.constFind(peerId);
    const bool isNewPeer = (existingIt == m_peers.constEnd());
    const bool hasChanged = !isNewPeer
        && (existingIt->name != peer.name
            || existingIt->userUuid != peer.userUuid
            || existingIt->certificateFingerprint != peer.certificateFingerprint
            || existingIt->status != peer.status
            || existingIt->address != peer.address
            || existingIt->port != peer.port
            || existingIt->transferPort != peer.transferPort
            || existingIt->signalingPort != peer.signalingPort);

    m_peers.insert(peerId, peer);

    // DIAGNOSTIC (poste detecte alors qu'il est cense etre hors reseau) :
    // la liste des postes est purement pilotee par la reception reelle de
    // ces paquets, sans aucune autre source -- si un poste apparait a tort,
    // ce log permet d'identifier immediatement PAR QUELLE INTERFACE/IP
    // source ses annonces arrivent (carte Ethernet oubliee, carte virtuelle
    // Hyper-V/WSL/Docker/VirtualBox, hotspot, Wi-Fi "associe sans Internet"...).
    if (isNewPeer)
        qInfo() << "[Discovery] Nouveau poste detecte:" << peer.name << "id:" << peerId
                << "depuis" << senderAddress.toString() << ":" << peer.port;

    if (isNewPeer)
        emit peerDiscovered(peer);
    else if (hasChanged)
        emit peerUpdated(peer);
}

void DiscoveryService::checkStalePeers()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QList<DiscoveredPeer> stalePeers;

    for (auto it = m_peers.constBegin(); it != m_peers.constEnd(); ++it) {
        if (now - it.value().lastSeenMs > m_peerTimeoutMs)
            stalePeers.append(it.value());
    }

    for (const DiscoveredPeer &peer : stalePeers) {
        m_peers.remove(peer.id);
        emit peerLost(peer);
    }
}

} // namespace network