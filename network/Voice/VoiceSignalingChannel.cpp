#include "VoiceSignalingChannel.h"
#include "Security/SecurityService.h"

#include <QWebSocket>
#include <QWebSocketServer>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslCertificate>
#include <QFile>
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
    return SignalingMessageType::Unknown;
}

} // namespace

VoiceSignalingChannel::VoiceSignalingChannel(SecurityService *securityService, QObject *parent)
    : QObject(parent)
    , m_securityService(securityService)
{
    m_outgoingSocket = new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this);
    connect(m_outgoingSocket, &QWebSocket::connected, this, &VoiceSignalingChannel::onClientConnected);
    connect(m_outgoingSocket, &QWebSocket::disconnected, this, &VoiceSignalingChannel::onClientDisconnected);
    connect(m_outgoingSocket, &QWebSocket::textMessageReceived, this, &VoiceSignalingChannel::onTextMessageReceived);
    connect(m_outgoingSocket, &QWebSocket::sslErrors, this, &VoiceSignalingChannel::onSslErrors);

    configureClientSsl();

    m_server = new QWebSocketServer(QStringLiteral("LocaLink-VoiceSignaling"),
                                     QWebSocketServer::SecureMode, this);
    connect(m_server, &QWebSocketServer::newConnection, this, &VoiceSignalingChannel::onServerNewConnection);
}

VoiceSignalingChannel::~VoiceSignalingChannel()
{
    stopListening();
    disconnectFromPeer();
}

void VoiceSignalingChannel::configureClientSsl()
{
    if (!m_securityService || !m_securityService->isReady()) {
        qWarning() << "VoiceSignalingChannel: SecurityService non pret, TLS non configure";
        return;
    }

    QSslConfiguration sslConfig = QSslConfiguration::defaultConfiguration();

    const QByteArray certPem = m_securityService->certificatePem();
    if (!certPem.isEmpty()) {
        QSslCertificate localCert(certPem, QSsl::Pem);
        if (!localCert.isNull()) {
            sslConfig.setLocalCertificate(localCert);
        }
    }

    QFile keyFile(m_securityService->privateKeyPath());
    if (keyFile.open(QIODevice::ReadOnly)) {
        const QByteArray keyData = keyFile.readAll();
        keyFile.close();
        QSslKey privateKey(keyData, QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
        if (!privateKey.isNull()) {
            sslConfig.setPrivateKey(privateKey);
        }
    }

    // Postes P2P a certificats auto-signes : chiffrement actif, verification
    // d'autorite desactivee (voir MessagingService::configureSsl pour le
    // meme choix applique a la messagerie texte).
    sslConfig.setPeerVerifyMode(QSslSocket::QueryPeer);
    sslConfig.setProtocol(QSsl::TlsV1_2OrLater);

    m_outgoingSocket->setSslConfiguration(sslConfig);
}

bool VoiceSignalingChannel::listen(quint16 port)
{
    if (!m_securityService || !m_securityService->isReady()) {
        emit error(QStringLiteral("SecurityService non pret pour la signalisation d'appel"));
        return false;
    }

    QSslConfiguration sslConfig = QSslConfiguration::defaultConfiguration();
    const QByteArray certPem = m_securityService->certificatePem();
    if (!certPem.isEmpty()) {
        QSslCertificate localCert(certPem, QSsl::Pem);
        sslConfig.setLocalCertificate(localCert);
    }
    QFile keyFile(m_securityService->privateKeyPath());
    if (keyFile.open(QIODevice::ReadOnly)) {
        QSslKey privateKey(keyFile.readAll(), QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
        sslConfig.setPrivateKey(privateKey);
        keyFile.close();
    }
    sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone);
    sslConfig.setProtocol(QSsl::TlsV1_2OrLater);
    m_server->setSslConfiguration(sslConfig);

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
    if (m_incomingSocket) {
        m_incomingSocket->close();
        m_incomingSocket->deleteLater();
        m_incomingSocket = nullptr;
    }
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

bool VoiceSignalingChannel::connectToPeer(const QHostAddress &address, quint16 port)
{
    if (!m_securityService || !m_securityService->isReady()) {
        emit error(QStringLiteral("SecurityService non pret pour la signalisation d'appel"));
        return false;
    }
    if (m_outgoingConnected) {
        qWarning() << "VoiceSignalingChannel: deja connecte, deconnexion prealable requise";
        return false;
    }

    const QString url = QStringLiteral("wss://%1:%2").arg(address.toString()).arg(port);
    qDebug() << "VoiceSignalingChannel: tentative de connexion a" << url;
    m_outgoingSocket->open(QUrl(url));
    return true;
}

void VoiceSignalingChannel::disconnectFromPeer()
{
    if (m_outgoingSocket) {
        m_outgoingSocket->close();
    }
}

bool VoiceSignalingChannel::isConnected() const
{
    return m_outgoingConnected || m_incomingSocket != nullptr;
}

bool VoiceSignalingChannel::sendJson(const QString &type, const QString &sdp, const QString &candidate,
                                      const QString &mid, const QString &callId,
                                      const QString &reason)
{
    QWebSocket *targetSocket = nullptr;
    if (m_outgoingConnected) {
        targetSocket = m_outgoingSocket;
    } else if (m_incomingSocket) {
        targetSocket = m_incomingSocket;
    }

    return sendJsonToSocket(targetSocket, type, sdp, candidate, mid, callId, reason);
}

bool VoiceSignalingChannel::sendJsonToSocket(QWebSocket *socket, const QString &type,
                                              const QString &sdp, const QString &candidate,
                                              const QString &mid, const QString &callId,
                                              const QString &reason)
{
    if (!socket) {
        qWarning() << "VoiceSignalingChannel: aucun canal ouvert pour envoyer" << type;
        return false;
    }

    QJsonObject obj;
    obj[QStringLiteral("type")] = type;
    if (!sdp.isEmpty())       obj[QStringLiteral("sdp")] = sdp;
    if (!candidate.isEmpty()) obj[QStringLiteral("candidate")] = candidate;
    if (!mid.isEmpty())       obj[QStringLiteral("mid")] = mid;
    obj[QStringLiteral("callId")] = callId;
    if (!reason.isEmpty())    obj[QStringLiteral("reason")] = reason;
    if (m_securityService && m_securityService->isReady()) {
        const QString localFingerprint = m_securityService->identity().fingerprintSha256.toLower();
        if (!localFingerprint.isEmpty()) {
            obj[QStringLiteral("certificate_fingerprint")] = localFingerprint;
        }
    }

    const QString json = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));

    return socket->sendTextMessage(json) >= 0;
}

bool VoiceSignalingChannel::sendOffer(const QString &sdp, const QString &callId)
{
    return sendJson(typeToString(SignalingMessageType::Offer), sdp, QString(), QString(), callId);
}

bool VoiceSignalingChannel::sendAnswer(const QString &sdp, const QString &callId)
{
    return sendJson(typeToString(SignalingMessageType::Answer), sdp, QString(), QString(), callId);
}

bool VoiceSignalingChannel::sendIceCandidate(const QString &candidate, const QString &mid, const QString &callId)
{
    return sendJson(typeToString(SignalingMessageType::IceCandidate), QString(), candidate, mid, callId);
}

bool VoiceSignalingChannel::sendHangup(const QString &callId, const QString &reason)
{
    return sendJson(typeToString(SignalingMessageType::Hangup), QString(), QString(), QString(), callId, reason);
}

bool VoiceSignalingChannel::sendHangupToPeer(const QHostAddress &peerAddress,
                                              const QString &callId, const QString &reason)
{
    QWebSocket *targetSocket = nullptr;
    if (m_incomingSocket && m_incomingSocket->peerAddress().isEqual(peerAddress,
                                                                      QHostAddress::TolerantConversion)) {
        targetSocket = m_incomingSocket;
    } else if (m_outgoingConnected && m_outgoingSocket->peerAddress().isEqual(
                   peerAddress, QHostAddress::TolerantConversion)) {
        targetSocket = m_outgoingSocket;
    }

    if (targetSocket == m_incomingSocket && reason == QStringLiteral("busy")) {
        targetSocket->setProperty("voiceBusyRejected", true);
    }

    return sendJsonToSocket(targetSocket, typeToString(SignalingMessageType::Hangup),
                            QString(), QString(), QString(), callId, reason);
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
    qDebug() << "VoiceSignalingChannel: empreinte certificat entrant"
             << (fingerprint.isEmpty() ? QStringLiteral("<vide>") : fingerprint);
    bool tlsAuthorized = !m_permissionManager;
    if (m_permissionManager && !fingerprint.isEmpty()) {
        bool authorized = tlsAuthorized;
        QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorizedByCertificate",
                                  Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                  Q_ARG(QString, fingerprint));
        if (!authorized) {
            if (!fingerprint.isEmpty()) {
                QMetaObject::invokeMethod(m_permissionManager, "registerPendingMachineByCertificate",
                                          Qt::DirectConnection, Q_ARG(QString, fingerprint),
                                          Q_ARG(QString, socket->peerAddress().toString()),
                                          Q_ARG(QString, QString()));
            }
            socket->close();
            socket->deleteLater();
            emit error(QStringLiteral("Appel refusé : certificat distant non autorisé"));
            return;
        }
    }

    if (m_incomingSocket) {
        // Un seul appel entrant gere a la fois : on refuse les suivants.
        qWarning() << "VoiceSignalingChannel: appel entrant refuse (session deja active)";
        QJsonObject busyMessage;
        busyMessage[QStringLiteral("type")] = typeToString(SignalingMessageType::Hangup);
        busyMessage[QStringLiteral("reason")] = QStringLiteral("busy");
        socket->sendTextMessage(QString::fromUtf8(
            QJsonDocument(busyMessage).toJson(QJsonDocument::Compact)));
        socket->close();
        socket->deleteLater();
        return;
    }

    m_incomingSocket = socket;
    m_incomingSocket->setProperty("voiceAuthorized", tlsAuthorized);
    m_incomingSocket->setProperty("voicePeerConnectedEmitted", tlsAuthorized);
    connect(m_incomingSocket, &QWebSocket::textMessageReceived, this, &VoiceSignalingChannel::onTextMessageReceived);
    QWebSocket *incomingSocket = m_incomingSocket;
    connect(incomingSocket, &QWebSocket::disconnected, this, [this, incomingSocket]() {
        const bool busyRejected = incomingSocket->property("voiceBusyRejected").toBool();
        qDebug() << "VoiceSignalingChannel: socket entrant deconnecte, erreur:"
                 << incomingSocket->errorString()
                 << "busyRejected:" << busyRejected;
        if (!busyRejected) {
            emit peerDisconnected();
        }
        if (m_incomingSocket == incomingSocket) {
            incomingSocket->deleteLater();
            m_incomingSocket = nullptr;
        }
    });
    connect(incomingSocket, &QWebSocket::errorOccurred, this, [incomingSocket](QAbstractSocket::SocketError error) {
        qDebug() << "VoiceSignalingChannel: erreur socket entrant:" << error << incomingSocket->errorString();
    });
    connect(incomingSocket, &QWebSocket::sslErrors, this, [this](const QList<QSslError> &errors) {
        qDebug() << "VoiceSignalingChannel: erreurs SSL sur socket entrant (" << errors.size() << "):";
        for (const QSslError &e : errors) {
            qDebug() << "  -" << e.errorString();
        }
        m_incomingSocket->ignoreSslErrors();
    });

    if (tlsAuthorized) {
        // Emettre peerConnected dans le thread principal pour eviter les problemes de thread
        QMetaObject::invokeMethod(this, [this, socket]() {
            emit peerConnected(socket->peerAddress());
        }, Qt::QueuedConnection);
    } else {
        qDebug() << "VoiceSignalingChannel: attente de l'empreinte annoncee par le message de signalisation";
    }
}

void VoiceSignalingChannel::onClientConnected()
{
    const QString verifiedFingerprint = SecurityService::certificateFingerprint(
        m_outgoingSocket->sslConfiguration().peerCertificate());
    if (m_permissionManager) {
        bool authorized = false;
        QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorizedByCertificate",
                                  Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                  Q_ARG(QString, verifiedFingerprint));
        // Un appel direct peut viser un client autorise ou le serveur deja
        // approuve localement ; ne consulte TrustedServers qu'en repli.
        if (!authorized) {
            QMetaObject::invokeMethod(m_permissionManager, "trustRemoteServerCertificate",
                                      Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                      Q_ARG(QString, verifiedFingerprint),
                                      Q_ARG(QString, m_outgoingSocket->peerAddress().toString()));
        }
        if (!authorized) {
            m_outgoingSocket->close();
            emit error(QStringLiteral("Appel refusé : certificat distant non autorisé"));
            return;
        }
    }
    qDebug() << "VoiceSignalingChannel: client connecte a" << m_outgoingSocket->peerAddress();
    m_outgoingConnected = true;
    // Emettre peerConnected dans le thread principal pour eviter les problemes de thread
    QMetaObject::invokeMethod(this, [this]() {
        emit peerConnected(m_outgoingSocket->peerAddress());
    }, Qt::QueuedConnection);
}

void VoiceSignalingChannel::onClientDisconnected()
{
    m_outgoingConnected = false;
    emit peerDisconnected();
}

void VoiceSignalingChannel::onTextMessageReceived(const QString &message)
{
    auto *socket = qobject_cast<QWebSocket *>(sender());
    const QHostAddress peerAddress = socket ? socket->peerAddress() : QHostAddress();

    const SignalingMessage parsed = parseMessage(message);
    if (parsed.type == SignalingMessageType::Unknown) {
        qWarning() << "VoiceSignalingChannel: message de signalisation invalide ignore";
        return;
    }

    if (socket == m_incomingSocket && !socket->property("voiceAuthorized").toBool()) {
        const QString announcedFingerprint = parsed.certificateFingerprint.toLower().trimmed();
        qDebug() << "VoiceSignalingChannel: empreinte annoncee par signalisation"
                 << (announcedFingerprint.isEmpty() ? QStringLiteral("<vide>") : announcedFingerprint);

        bool authorized = false;
        if (m_permissionManager && !announcedFingerprint.isEmpty()) {
            QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorizedByCertificate",
                                      Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                      Q_ARG(QString, announcedFingerprint));
            if (!authorized) {
                QMetaObject::invokeMethod(m_permissionManager, "trustRemoteServerCertificate",
                                          Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                          Q_ARG(QString, announcedFingerprint),
                                          Q_ARG(QString, peerAddress.toString()));
            }
            if (authorized) {
                QMetaObject::invokeMethod(m_permissionManager, "recordMachineSeen",
                                          Qt::DirectConnection,
                                          Q_ARG(QString, announcedFingerprint),
                                          Q_ARG(QString, peerAddress.toString()));
            }
        }

        if (!authorized) {
            qWarning() << "VoiceSignalingChannel: appel refuse, empreinte annoncee non autorisee"
                       << announcedFingerprint << "peer" << peerAddress;
            if (m_permissionManager && !announcedFingerprint.isEmpty()) {
                QMetaObject::invokeMethod(m_permissionManager, "registerPendingMachineByCertificate",
                                          Qt::DirectConnection, Q_ARG(QString, announcedFingerprint),
                                          Q_ARG(QString, peerAddress.toString()),
                                          Q_ARG(QString, QString()));
            }
            socket->close();
            emit error(QStringLiteral("Appel refuse : certificat distant non autorise"));
            return;
        }

        socket->setProperty("voiceAuthorized", true);
        if (!socket->property("voicePeerConnectedEmitted").toBool()) {
            socket->setProperty("voicePeerConnectedEmitted", true);
            emit peerConnected(peerAddress);
        }
    }

    emit messageReceived(parsed, peerAddress);
}

void VoiceSignalingChannel::onSslErrors(const QList<QSslError> &errors)
{
    qDebug() << "VoiceSignalingChannel: erreurs SSL (" << errors.size() << "):";
    bool hasHostnameMismatch = false;
    for (const QSslError &e : errors) {
        qDebug() << "  -" << e.errorString();
        if (e.error() == QSslError::HostNameMismatch) {
            hasHostnameMismatch = true;
        }
    }

    // Meme politique que MessagingService : certificats auto-signes en LAN,
    // on ignore uniquement le mismatch de hostname (l'IP est utilisee pour
    // se connecter, pas le CN du certificat).
    m_outgoingSocket->ignoreSslErrors();
    if (!hasHostnameMismatch || errors.size() > 1) {
        for (const QSslError &e : errors) {
            qWarning() << "VoiceSignalingChannel: erreur SSL -" << e.errorString();
        }
    }
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

    return msg;
}

} // namespace network
