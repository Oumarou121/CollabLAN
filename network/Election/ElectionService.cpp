#include "ElectionService.h"

#include <QUdpSocket>
#include <QNetworkDatagram>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>
#include <QDebug>
#include <QUuid>
#include <QNetworkInterface>
#include <algorithm>

namespace network {

namespace {
const char *kPacketType = "localink.election";
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
        m_activeServerAddress = QHostAddress::LocalHost;
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
    if (m_priorityWeight == weight)
        return;
    m_priorityWeight = weight;
    emit priorityWeightChanged();
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

quint16 ElectionService::messagingPort() const
{
    return m_messagingPort;
}

void ElectionService::setMessagingPort(quint16 port)
{
    m_messagingPort = port;
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
    emit heartbeatTimeoutMsChanged();
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
    if (role == models::ServerRole::Server || role == models::ServerRole::TempServer) {
        m_activeServerUuid = m_localMachineUuid;
        m_activeServerAddress = QHostAddress::LocalHost;
    }
}

models::ServerRole ElectionService::role() const
{
    return m_role;
}

QString ElectionService::roleLabel() const
{
    return models::serverRoleToString(m_role);
}

int ElectionService::epoch() const
{
    return m_epoch;
}

QString ElectionService::activeServerUuid() const
{
    return m_activeServerUuid;
}

QHostAddress ElectionService::activeServerAddress() const
{
    return m_activeServerAddress;
}

quint16 ElectionService::activeServerPort() const
{
    return m_activeServerPort;
}

void ElectionService::reclaimAsOfficialServer()
{
    // Section 7.3 : une fois la fusion confirmee (sync_ack, hors perimetre
    // de ce service), le serveur officiel reprend la main : nouvel epoch,
    // diffusion server_promoted(temporary=false).
    enterServerRole(m_epoch + 1, /*temporary=*/false);
}

void ElectionService::stepDownToClient()
{
    if (m_role != models::ServerRole::Server && m_role != models::ServerRole::TempServer)
        return; // deja Client : rien a faire

    // Contrairement au cas reconciliationRequired (server_promoted recu avec
    // epoch superieur pendant que ce poste croit encore etre Server), ici
    // c'est une demission deliberee : on applique la transition vers Client
    // sans passer par la reconciliation ni attendre reclaimAsOfficialServer().
    m_heartbeatTimer->stop();
    applyRole(models::ServerRole::Client);
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
    // Un heartbeat ne portait jusqu'ici que l'epoch. Un serveur officiel
    // redemarre avec un epoch persiste plus grand ignorait alors le heartbeat
    // d'un TEMP_SERVER plus ancien, sans savoir qu'il devait tout de meme
    // effectuer la reconciliation avant de reprendre la main.
    packet["temporary"] = (m_role == models::ServerRole::TempServer);
    packet["messaging_port"] = m_messagingPort;

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
    m_activeServerAddress = QHostAddress::LocalHost;
    m_activeServerPort = m_messagingPort;
    // Ce poste est sa propre autorite : rien a valider en TLS pour lui-meme
    // (voir setRequireValidatedServer).
    m_validatedServerUuid = m_localMachineUuid;
    m_validatedServerAddress = QHostAddress::LocalHost;
    applyRole(newRole);
    emit epochChanged();
    emit activeServerUuidChanged();

    QJsonObject packet;
    packet["type"] = QString::fromLatin1(kPacketType);
    packet["version"] = kPacketVersion;
    packet["msg"] = QString::fromLatin1(kMsgServerPromoted);
    packet["epoch"] = m_epoch;
    packet["machine_uuid"] = m_localMachineUuid;
    packet["temporary"] = temporary;
    packet["messaging_port"] = m_messagingPort;

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
    emit roleLabelChanged();
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
        handlePacket(datagram.data(), datagram.senderAddress());
    }
}

void ElectionService::handlePacket(const QByteArray &data, const QHostAddress &senderAddress)
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
        const bool remoteTemporary = obj.value("temporary").toBool(false);
        // messaging_port : toInt(0) -- un pair qui n'aurait pas encore ce champ
        // (ancien format) laisse le port a 0, traite comme "inconnu" par
        // l'appelant plutot que de connecter silencieusement au mauvais port.
        const quint16 remotePort = static_cast<quint16>(obj.value("messaging_port").toInt(0));

        // Cas de retour du SERVER officiel : son epoch persiste peut etre
        // superieur a celui du TEMP_SERVER elu pendant son absence. Ce
        // heartbeat est pourtant l'unique signal qui permet de retrouver le
        // temporaire et de lancer la fusion. L'ancien "return" sur epoch
        // inferieur creait un deadlock : le Server n'entamait jamais la
        // reconciliation, et le TempServer ne pouvait donc jamais redevenir
        // Client. On conserve l'epoch local (jamais de retour en arriere),
        // mais on adopte l'adresse/port du temporaire pour le joindre.
        if (remoteEpoch < m_epoch) {
            if (m_role == models::ServerRole::Server && remoteTemporary) {
                if (deferUntilValidated(serverUuid, senderAddress, remotePort, m_epoch,
                                         remoteTemporary, /*viaPromotion=*/false))
                    return;
                qInfo() << "ElectionService: TEMP_SERVER detecte avec epoch inferieur"
                        << remoteEpoch << "(serveur officiel:" << m_epoch
                        << ") - reconciliation requise avant reprise";
                applyRemoteServer(serverUuid, senderAddress, remotePort, m_epoch,
                                   remoteTemporary, /*viaPromotion=*/false);
            }
            return;
        }

        // Le client adopte l'epoch du serveur legitime : c'est ce qui permet
        // ensuite a startElection()/enterServerRole() de repartir de la bonne
        // valeur (epoch+1) plutot que de l'epoch initial jamais mis a jour.
        if (deferUntilValidated(serverUuid, senderAddress, remotePort, remoteEpoch,
                                 remoteTemporary, /*viaPromotion=*/false))
            return;

        applyRemoteServer(serverUuid, senderAddress, remotePort, remoteEpoch,
                           remoteTemporary, /*viaPromotion=*/false);
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
        const quint16 remotePort = static_cast<quint16>(obj.value("messaging_port").toInt(0));

        // Le broadcast UDP boucle generalement vers l'emetteur lui-meme sur le
        // meme hote : on ignore silencieusement notre propre server_promoted
        // (deja applique et deja emis dans enterServerRole()), avant meme de
        // regarder l'epoch, pour ne pas se le faire rejeter comme split-brain.
        if (machineUuid == m_localMachineUuid)
            return;

        // Regle anti split-brain (section 7) : tout server_promoted avec un
        // epoch strictement inferieur a l'epoch local est ignore.
        //
        // CORRECTIF (epoch a egalite) : la regle d'origine ignorait aussi les
        // epochs EGAUX ("<="), ce qui cree un deadlock quand deux postes sont
        // promus independamment sans s'etre jamais entendus. A epoch egal, on
        // depart de facon deterministe par machine_uuid : le plus grand (au
        // sens chaine) gagne. La comparaison etant symetrique, un seul des
        // deux cotes voit le "remote" gagnant et cede.
        if (remoteEpoch < m_epoch
            || (remoteEpoch == m_epoch && machineUuid <= m_localMachineUuid)) {
            emit splitBrainAttemptIgnored(remoteEpoch, machineUuid);
            return;
        }

        // Un epoch arbitrairement grand suffisait ici a faire basculer tout le
        // reseau vers n'importe quelle machine : c'est precisement ce que
        // setRequireValidatedServer() empeche (voir ElectionService.h).
        if (deferUntilValidated(machineUuid, senderAddress, remotePort, remoteEpoch,
                                 temporary, /*viaPromotion=*/true))
            return;

        applyRemoteServer(machineUuid, senderAddress, remotePort, remoteEpoch,
                           temporary, /*viaPromotion=*/true);
        return;
    }
}

void ElectionService::setRequireValidatedServer(bool require)
{
    m_requireValidatedServer = require;
}

bool ElectionService::requiresValidatedServer() const
{
    return m_requireValidatedServer;
}

QString ElectionService::pendingServerUuid() const
{
    return m_pendingServer.machineUuid;
}

bool ElectionService::deferUntilValidated(const QString &machineUuid, const QHostAddress &address,
                                           quint16 port, int epoch, bool temporary, bool viaPromotion)
{
    if (!m_requireValidatedServer)
        return false;

    // Deja valide a cette adresse : les heartbeats suivants du meme serveur ne
    // repassent pas par une validation (sinon chaque battement rouvrirait une
    // connexion). L'adresse fait partie de la cle : un tiers qui rejoue l'UUID
    // du serveur legitime depuis une autre machine est traite comme inconnu.
    if (machineUuid == m_validatedServerUuid && address.isEqual(m_validatedServerAddress))
        return false;

    // Validation deja demandee pour cette meme annonce : on ne reemet pas le
    // signal a chaque heartbeat (3 s) tant que l'appelant n'a pas tranche.
    if (m_pendingServer.machineUuid == machineUuid
        && m_pendingServer.address.isEqual(address)
        && m_pendingServer.epoch >= epoch) {
        return true;
    }

    m_pendingServer = PendingServer{machineUuid, address, port, epoch, temporary, viaPromotion};
    qInfo() << "ElectionService: serveur annonce" << machineUuid << address
            << "- validation TLS requise avant adoption";
    emit serverEndpointPending(machineUuid, address, port);
    return true;
}

void ElectionService::confirmPendingServer(const QString &machineUuid)
{
    if (m_pendingServer.machineUuid.isEmpty() || m_pendingServer.machineUuid != machineUuid)
        return;

    const PendingServer pending = m_pendingServer;
    m_pendingServer = PendingServer{};
    applyRemoteServer(pending.machineUuid, pending.address, pending.port, pending.epoch,
                       pending.temporary, pending.viaPromotion);
}

void ElectionService::rejectPendingServer(const QString &machineUuid, const QString &reason)
{
    if (m_pendingServer.machineUuid.isEmpty() || m_pendingServer.machineUuid != machineUuid)
        return;

    m_pendingServer = PendingServer{};
    qWarning() << "ElectionService: serveur annonce" << machineUuid << "rejete -" << reason;
    // m_lastHeartbeatSeenMs n'est volontairement pas rafraichi : faute de
    // serveur valide, le delai d'attente finit par declencher une election,
    // plutot que de laisser le poste suspendu a une annonce non verifiee.
    emit serverEndpointRejected(machineUuid, reason);
}

void ElectionService::applyRemoteServer(const QString &machineUuid, const QHostAddress &address,
                                         quint16 port, int epoch, bool temporary, bool viaPromotion)
{
    m_validatedServerUuid = machineUuid;
    m_validatedServerAddress = address;

    const bool epochChangedFlag = (m_epoch != epoch);
    m_epoch = epoch;

    const bool activeServerChangedFlag = (m_activeServerUuid != machineUuid);
    m_activeServerUuid = machineUuid;
    m_activeServerAddress = address;
    m_activeServerPort = port;
    m_lastHeartbeatSeenMs = QDateTime::currentMSecsSinceEpoch();
    m_heartbeatEverSeen = true;

    if (epochChangedFlag)
        emit epochChanged();
    if (activeServerChangedFlag)
        emit activeServerUuidChanged();

    if (viaPromotion) {
        // Une election en cours localement est annulee : quelqu'un d'autre a
        // deja tranche avec un epoch superieur.
        m_electionInProgress = false;
        m_electionWindowTimer->stop();
        m_candidates.clear();
    }

    // Section 7.1/7.3 : si CE poste est le Server officiel, l'annonce d'un
    // TempServer NE DOIT PAS le faire retomber en Client en silence : il doit
    // passer par la reconciliation (SyncService) puis reprendre la main
    // lui-meme (reclaimAsOfficialServer()).
    if (m_role == models::ServerRole::Server) {
        emit reconciliationRequired(machineUuid);
        return;
    }

    if (viaPromotion) {
        // Un autre poste a ete promu : on redevient/reste Client et on bascule
        // notre connexion vers lui (a la charge de l'appelant, via
        // activeServerUuid() / le signal serverPromoted).
        applyRole(models::ServerRole::Client);
        emit serverPromoted(m_epoch, machineUuid, temporary);
    }
}

} // namespace network
