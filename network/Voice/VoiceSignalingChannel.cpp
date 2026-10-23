#include "VoiceSignalingChannel.h"
#include "NetworkAddress.h"
#include "Security/SecurityService.h"

#include <QWebSocket>
#include <QWebSocketServer>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslKey>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>


namespace network {

void VoiceSignalingChannel::setPermissionManager(QObject *manager)
{
    m_permissionManager = manager;
}

namespace {

QString typeToString(SignalingMessageType type)
{
    switch (type) {
    case SignalingMessageType::Offer:        return QStringLiteral("call-offer");
    case SignalingMessageType::Answer:       return QStringLiteral("call-answer");
    case SignalingMessageType::IceCandidate: return QStringLiteral("ice-candidate");
    case SignalingMessageType::Hangup:       return QStringLiteral("call-hangup");
    case SignalingMessageType::Roster:       return QStringLiteral("call-roster");
    case SignalingMessageType::State:        return QStringLiteral("call-state");
    case SignalingMessageType::Unknown:      break;
    }
    return QStringLiteral("unknown");
}

SignalingMessageType typeFromString(const QString &type)
{
    if (type == QStringLiteral("call-offer"))   return SignalingMessageType::Offer;
    if (type == QStringLiteral("call-answer"))  return SignalingMessageType::Answer;
    if (type == QStringLiteral("ice-candidate")) return SignalingMessageType::IceCandidate;
    if (type == QStringLiteral("call-hangup"))  return SignalingMessageType::Hangup;
    if (type == QStringLiteral("call-roster"))  return SignalingMessageType::Roster;
    if (type == QStringLiteral("call-state"))   return SignalingMessageType::State;
    return SignalingMessageType::Unknown;
}

// Certificat et cle du poste, communs aux liaisons sortantes et a l'ecoute.
QSslConfiguration localSslConfiguration(SecurityService *securityService)
{
    QSslConfiguration sslConfig = QSslConfiguration::defaultConfiguration();
    const QByteArray certPem = securityService->certificatePem();
    if (!certPem.isEmpty()) {
        QSslCertificate localCert(certPem, QSsl::Pem);
        if (!localCert.isNull())
            sslConfig.setLocalCertificate(localCert);
    }
    QFile keyFile(securityService->privateKeyPath());
    if (keyFile.open(QIODevice::ReadOnly)) {
        QSslKey privateKey(keyFile.readAll(), QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
        if (!privateKey.isNull())
            sslConfig.setPrivateKey(privateKey);
    }
    // Postes P2P a certificats auto-signes : chiffrement actif, verification
    // d'autorite desactivee ; QueryPeer demande le certificat du pair, dont
    // l'empreinte est ensuite comparee aux machines autorisees.
    sslConfig.setPeerVerifyMode(QSslSocket::QueryPeer);
    sslConfig.setProtocol(QSsl::TlsV1_2OrLater);
    return sslConfig;
}

} // namespace

VoiceSignalingChannel::VoiceSignalingChannel(SecurityService *securityService, QObject *parent)
    : QObject(parent)
    , m_securityService(securityService)
{
    m_server = new QWebSocketServer(QStringLiteral("LocaLink-VoiceSignaling"),
                                     QWebSocketServer::SecureMode, this);
    connect(m_server, &QWebSocketServer::newConnection, this, &VoiceSignalingChannel::onServerNewConnection);
}

VoiceSignalingChannel::~VoiceSignalingChannel()
{
    stopListening();
    closeAllLinks();
}

void VoiceSignalingChannel::configureClientSsl(QWebSocket *socket) const
{
    if (!m_securityService || !m_securityService->isReady()) {
        qWarning() << "VoiceSignalingChannel: SecurityService non pret, TLS non configure";
        return;
    }
    socket->setSslConfiguration(localSslConfiguration(m_securityService));
}

bool VoiceSignalingChannel::listen(quint16 port)
{
    if (!m_securityService || !m_securityService->isReady()) {
        emit error(QStringLiteral("SecurityService non pret pour la signalisation d'appel"));
        return false;
    }

    // QueryPeer : le certificat de l'appelant est DEMANDE (auto-signe, donc pas de verification
    // d'autorite), puis son empreinte est comparee a la liste des machines autorisees.
    // Avec VerifyNone, aucun certificat client n'etait demande et l'autorisation reposait sur une
    // empreinte simplement annoncee dans la signalisation, recopiable depuis la decouverte UDP.
    m_server->setSslConfiguration(localSslConfiguration(m_securityService));

    if (!m_server->listen(QHostAddress::AnyIPv4, port)) {
        emit error(QStringLiteral("Impossible d'ecouter les appels entrants sur le port %1 : %2")
                       .arg(port).arg(m_server->errorString()));
        return false;
    }

    qDebug() << "VoiceSignalingChannel: ecoute des appels entrants sur le port" << m_server->serverPort();
    return true;
}

void VoiceSignalingChannel::stopListening()
{
    if (m_server && m_server->isListening()) {
        m_server->close();
    }
}

bool VoiceSignalingChannel::isListening() const
{
    return m_server && m_server->isListening();
}

quint16 VoiceSignalingChannel::listenPort() const
{
    return m_server ? m_server->serverPort() : 0;
}

int VoiceSignalingChannel::linkOf(const QWebSocket *socket) const
{
    for (auto it = m_links.constBegin(); it != m_links.constEnd(); ++it) {
        if (it->socket == socket)
            return it.key();
    }
    return 0;
}

int VoiceSignalingChannel::connectToPeer(const QHostAddress &address, quint16 port)
{
    if (!m_securityService || !m_securityService->isReady()) {
        emit error(QStringLiteral("SecurityService non pret pour la signalisation d'appel"));
        return 0;
    }

    const int linkId = m_nextLinkId++;
    auto *socket = new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this);
    configureClientSsl(socket);
    m_links.insert(linkId, Link{socket, true, false});

    connect(socket, &QWebSocket::connected, this, [this, linkId]() { onOutgoingConnected(linkId); });
    connect(socket, &QWebSocket::disconnected, this, [this, linkId]() { onSocketClosed(linkId); });
    connect(socket, &QWebSocket::textMessageReceived, this,
            [this, linkId](const QString &message) { onTextMessage(linkId, message); });
    connect(socket, &QWebSocket::sslErrors, this, [socket](const QList<QSslError> &errors) {
        // Meme politique que MessagingService : certificats auto-signes en LAN
        // (l'IP sert a se connecter, pas le CN) ; l'identite est verifiee
        // ensuite par l'empreinte du certificat (onOutgoingConnected).
        bool onlyHostnameMismatch = true;
        for (const QSslError &e : errors) {
            if (e.error() != QSslError::HostNameMismatch && e.error() != QSslError::SelfSignedCertificate)
                onlyHostnameMismatch = false;
        }
        if (!onlyHostnameMismatch) {
            for (const QSslError &e : errors)
                qWarning() << "VoiceSignalingChannel: erreur SSL -" << e.errorString();
        }
        socket->ignoreSslErrors();
    });

    const QString url = QStringLiteral("wss://%1:%2").arg(address.toString()).arg(port);
    qDebug() << "VoiceSignalingChannel: liaison" << linkId << "vers" << url;
    socket->open(QUrl(url));
    return linkId;
}

void VoiceSignalingChannel::onOutgoingConnected(int linkId)
{
    const auto it = m_links.find(linkId);
    if (it == m_links.end())
        return;
    QWebSocket *socket = it->socket;
    const QString verifiedFingerprint = SecurityService::certificateFingerprint(
        socket->sslConfiguration().peerCertificate());
    if (m_permissionManager) {
        bool authorized = false;
        // Un appel direct peut viser un client autorise (ici ou par le serveur
        // actif) ou le serveur deja approuve ; trustRemoteServerCertificate
        // n'est consulte qu'en repli.
        QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorizedOrTrustedServer",
                                  Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                  Q_ARG(QString, verifiedFingerprint));
        if (!authorized) {
            QMetaObject::invokeMethod(m_permissionManager, "trustRemoteServerCertificate",
                                      Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                      Q_ARG(QString, verifiedFingerprint),
                                      Q_ARG(QString, canonicalAddress(socket->peerAddress()).toString()));
        }
        if (!authorized) {
            emit error(QStringLiteral("Appel refusé : certificat distant non autorisé"));
            socket->close();
            return;
        }
    }
    qDebug() << "VoiceSignalingChannel: liaison" << linkId << "connectee a" << socket->peerAddress();
    it->ready = true;
    const QHostAddress peer = canonicalAddress(socket->peerAddress());
    // Emis apres le retour au boucle d'evenements : l'appelant de
    // connectToPeer() a enregistre la liaison avant d'en etre notifie.
    QMetaObject::invokeMethod(this, [this, linkId, peer]() {
        if (m_links.contains(linkId))
            emit peerConnected(linkId, peer);
    }, Qt::QueuedConnection);
}

void VoiceSignalingChannel::onServerNewConnection()
{
    QWebSocket *socket = m_server->nextPendingConnection();
    if (!socket) {
        return;
    }

    qDebug() << "VoiceSignalingChannel: nouvelle connexion entrante de" << socket->peerAddress();

    const QString fingerprint = SecurityService::certificateFingerprint(
        socket->sslConfiguration().peerCertificate());
    if (m_permissionManager && fingerprint.isEmpty()) {
        // Pas de certificat client : identite non prouvee, appel refuse.
        qWarning() << "VoiceSignalingChannel: appel refuse, aucun certificat presente par" << socket->peerAddress();
        socket->close();
        socket->deleteLater();
        emit error(QStringLiteral("Appel refusé : certificat distant absent"));
        return;
    }
    if (m_permissionManager) {
        bool authorized = false;
        // Un client appele par son serveur : ce serveur n'est pas une machine
        // autorisee de la liste locale, mais un serveur approuve (TrustedServers).
        // Meme regle que MessagingServer ; la verification ne cree aucune
        // confiance nouvelle (contrairement a trustRemoteServerCertificate).
        QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorizedOrTrustedServer",
                                  Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                  Q_ARG(QString, fingerprint));
        if (!authorized) {
            QMetaObject::invokeMethod(m_permissionManager, "registerPendingMachineByCertificate",
                                      Qt::DirectConnection, Q_ARG(QString, fingerprint),
                                      Q_ARG(QString, canonicalAddress(socket->peerAddress()).toString()),
                                      Q_ARG(QString, QString()));
            socket->close();
            socket->deleteLater();
            emit error(QStringLiteral("Appel refusé : certificat distant non autorisé"));
            return;
        }
        QMetaObject::invokeMethod(m_permissionManager, "recordMachineSeen",
                                  Qt::DirectConnection, Q_ARG(QString, fingerprint),
                                  Q_ARG(QString, canonicalAddress(socket->peerAddress()).toString()));
    }

    // Identite prouvee par TLS et machine autorisee : la liaison est prete.
    // Qu'un appel soit deja en cours n'est pas decide ici : VoiceService
    // repond « occupe » a une offre etrangere, mais accueille un membre de
    // l'appel en cours (appel de groupe).
    const int linkId = m_nextLinkId++;
    m_links.insert(linkId, Link{socket, false, true});
    socket->setParent(this);
    connect(socket, &QWebSocket::disconnected, this, [this, linkId]() { onSocketClosed(linkId); });
    connect(socket, &QWebSocket::textMessageReceived, this,
            [this, linkId](const QString &message) { onTextMessage(linkId, message); });
    connect(socket, &QWebSocket::sslErrors, this, [socket](const QList<QSslError> &) {
        socket->ignoreSslErrors();
    });

    const QHostAddress peer = canonicalAddress(socket->peerAddress());
    QMetaObject::invokeMethod(this, [this, linkId, peer]() {
        if (m_links.contains(linkId))
            emit peerConnected(linkId, peer);
    }, Qt::QueuedConnection);
}

void VoiceSignalingChannel::onSocketClosed(int linkId)
{
    const auto it = m_links.find(linkId);
    if (it == m_links.end())
        return;
    QWebSocket *socket = it->socket;
    m_links.erase(it);
    socket->deleteLater();
    emit peerDisconnected(linkId);
}

void VoiceSignalingChannel::closeLink(int linkId)
{
    const auto it = m_links.find(linkId);
    if (it == m_links.end())
        return;
    QWebSocket *socket = it->socket;
    // Retiree avant close() : la fermeture voulue ne remonte pas en
    // peerDisconnected (VoiceService a deja oublie ce participant).
    m_links.erase(it);
    socket->disconnect(this);
    socket->close();
    socket->deleteLater();
}

void VoiceSignalingChannel::closeAllLinks()
{
    const QList<int> ids = m_links.keys();
    for (int id : ids)
        closeLink(id);
}

bool VoiceSignalingChannel::isLinkOpen(int linkId) const
{
    const auto it = m_links.constFind(linkId);
    return it != m_links.constEnd() && it->ready;
}

QString VoiceSignalingChannel::serialize(const SignalingMessage &message, const QString &localFingerprint)
{
    QJsonObject obj;
    obj[QStringLiteral("type")] = typeToString(message.type);
    if (!message.sdp.isEmpty())       obj[QStringLiteral("sdp")] = message.sdp;
    if (!message.candidate.isEmpty()) obj[QStringLiteral("candidate")] = message.candidate;
    if (!message.mid.isEmpty())       obj[QStringLiteral("mid")] = message.mid;
    obj[QStringLiteral("callId")] = message.callId;
    if (!message.reason.isEmpty())    obj[QStringLiteral("reason")] = message.reason;
    if (message.signalingPort > 0)    obj[QStringLiteral("port")] = message.signalingPort;
    if (message.group)                obj[QStringLiteral("group")] = true;
    if (message.mesh)                 obj[QStringLiteral("mesh")] = true;
    if (message.type == SignalingMessageType::State)
        obj[QStringLiteral("muted")] = message.muted;
    if (!message.roster.isEmpty()) {
        QJsonArray roster;
        for (const SignalingRosterEntry &entry : message.roster) {
            QJsonObject e;
            e[QStringLiteral("address")] = entry.address;
            e[QStringLiteral("port")] = entry.port;
            roster.append(e);
        }
        obj[QStringLiteral("roster")] = roster;
    }
    if (!localFingerprint.isEmpty())
        obj[QStringLiteral("certificate_fingerprint")] = localFingerprint;
    return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

bool VoiceSignalingChannel::send(int linkId, const SignalingMessage &message)
{
    const auto it = m_links.constFind(linkId);
    if (it == m_links.constEnd() || !it->ready) {
        qWarning() << "VoiceSignalingChannel: liaison" << linkId << "fermee, message"
                   << typeToString(message.type) << "non envoye";
        return false;
    }
    QString fingerprint;
    if (m_securityService && m_securityService->isReady())
        fingerprint = m_securityService->identity().fingerprintSha256.toLower();
    return it->socket->sendTextMessage(serialize(message, fingerprint)) >= 0;
}

void VoiceSignalingChannel::onTextMessage(int linkId, const QString &message)
{
    const auto it = m_links.constFind(linkId);
    if (it == m_links.constEnd() || !it->ready) {
        // Liaison sortante dont le poste n'a pas (encore) ete reconnu : rien
        // n'est accepte avant la verification de son certificat.
        return;
    }
    const QHostAddress peerAddress = canonicalAddress(it->socket->peerAddress());

    const SignalingMessage parsed = parseMessage(message);
    if (parsed.type == SignalingMessageType::Unknown) {
        qWarning() << "VoiceSignalingChannel: message de signalisation invalide ignore";
        return;
    }

    emit messageReceived(linkId, parsed, peerAddress);
}

SignalingMessage VoiceSignalingChannel::parseMessage(const QString &json)
{
    SignalingMessage msg;

    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject()) {
        return msg;
    }
    const QJsonObject obj = doc.object();

    msg.type = typeFromString(obj.value(QStringLiteral("type")).toString());
    msg.sdp = obj.value(QStringLiteral("sdp")).toString();
    msg.candidate = obj.value(QStringLiteral("candidate")).toString();
    msg.mid = obj.value(QStringLiteral("mid")).toString();
    msg.callId = obj.value(QStringLiteral("callId")).toString();
    msg.reason = obj.value(QStringLiteral("reason")).toString();
    msg.certificateFingerprint = obj.value(QStringLiteral("certificate_fingerprint")).toString().toLower();
    const int port = obj.value(QStringLiteral("port")).toInt();
    msg.signalingPort = port > 0 && port <= 65535 ? static_cast<quint16>(port) : 0;
    msg.group = obj.value(QStringLiteral("group")).toBool();
    msg.mesh = obj.value(QStringLiteral("mesh")).toBool();
    msg.muted = obj.value(QStringLiteral("muted")).toBool();
    const QJsonArray roster = obj.value(QStringLiteral("roster")).toArray();
    // Un appel de groupe compte 4 personnes au plus : une liste plus longue
    // est tronquee plutot que de faire ouvrir des dizaines de liaisons.
    for (int i = 0; i < roster.size() && i < 8; ++i) {
        const QJsonObject e = roster.at(i).toObject();
        const QHostAddress address(e.value(QStringLiteral("address")).toString());
        const int entryPort = e.value(QStringLiteral("port")).toInt();
        if (address.isNull() || entryPort <= 0 || entryPort > 65535)
            continue;
        msg.roster.append({canonicalAddress(address).toString(), static_cast<quint16>(entryPort)});
    }

    return msg;
}

} // namespace network
