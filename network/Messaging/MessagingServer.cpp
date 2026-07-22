#include "MessagingServer.h"

#include "Security/SecurityService.h"

#include <QWebSocketServer>
#include <QWebSocket>
#include <QHostAddress>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslCertificate>
#include <QFile>
#include <QDebug>
#include <QMetaObject>
#include <QJsonDocument>
#include <QJsonObject>

namespace network {

MessagingServer::MessagingServer(SecurityService *securityService, QObject *parent)
    : QObject(parent)
    , m_securityService(securityService)
{
}

MessagingServer::~MessagingServer()
{
    stop();
}

bool MessagingServer::start(quint16 port)
{
    if (m_server) {
        qWarning() << "Server already running";
        return false;
    }

    // Créer le serveur WebSocket sécurisé
    m_server = new QWebSocketServer(QStringLiteral("CollabLAN Messaging Server"), QWebSocketServer::SecureMode, this);

    // Configurer SSL/TLS avec SecurityService
    bool sslConfigured = false;
    if (m_securityService && m_securityService->isReady()) {
        QSslConfiguration sslConfig = m_server->sslConfiguration();
        QList<QSslCertificate> certs = QSslCertificate::fromData(m_securityService->certificatePem());

        QFile keyFile(m_securityService->privateKeyPath());
        if (!certs.isEmpty() && keyFile.open(QIODevice::ReadOnly)) {
            const QByteArray keyData = keyFile.readAll();
            keyFile.close();
            QSslKey privateKey(keyData, QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);

            if (!privateKey.isNull()) {
                // Sans la cle privee, le handshake TLS echoue systematiquement
                // (le certificat seul ne suffit pas au serveur pour prouver sa
                // possession de la cle) : c'etait le bug qui empechait toute
                // reconciliation SERVER<->TEMP_SERVER reelle via WebSocket.
                sslConfig.setLocalCertificate(certs.first());
                sslConfig.setPrivateKey(privateKey);
                sslConfig.setPeerVerifyMode(QSslSocket::QueryPeer); // Pour le développement local
                m_server->setSslConfiguration(sslConfig);
                sslConfigured = true;
            } else {
                qWarning() << "Cle privee TLS illisible, bascule en mode non securise";
            }
        } else {
            qWarning() << "Certificat ou cle privee TLS introuvable, bascule en mode non securise";
        }
    }

    if (!sslConfigured) {
        qWarning() << "SecurityService not ready, using insecure mode";
        // En mode développement, on peut utiliser un mode non sécurisé
        delete m_server;
        m_server = new QWebSocketServer(QStringLiteral("CollabLAN Messaging Server"), QWebSocketServer::NonSecureMode, this);
    }

    connect(m_server, &QWebSocketServer::newConnection, this, &MessagingServer::onNewConnection);

    if (m_server->listen(QHostAddress::Any, port)) {
        qDebug() << "MessagingServer started on port" << m_server->serverPort();
        return true;
    } else {
        qWarning() << "Failed to start MessagingServer:" << m_server->errorString();
        delete m_server;
        m_server = nullptr;
        return false;
    }
}

void MessagingServer::stop()
{
    if (m_server) {
        // Déconnecter tous les clients
        for (QWebSocket *client : m_clients) {
            client->close();
        }
        m_clients.clear();
        m_clientUuids.clear();
        m_clientFingerprints.clear();
        m_clientAuthorized.clear();

        m_server->close();
        delete m_server;
        m_server = nullptr;
        qDebug() << "MessagingServer stopped";
    }
}

bool MessagingServer::isRunning() const
{
    return m_server && m_server->isListening();
}

quint16 MessagingServer::port() const
{
    return m_server ? m_server->serverPort() : 0;
}

int MessagingServer::broadcastMessage(const QString &message, const QHostAddress &excludeAddress)
{
    int sentCount = 0;
    for (QWebSocket *client : m_clients) {
        if (!excludeAddress.isNull() && client->peerAddress() == excludeAddress) {
            continue;
        }
        client->sendTextMessage(message);
        ++sentCount;
    }
    return sentCount;
}

int MessagingServer::sendToUuids(const QString &message, const QStringList &uuids)
{
    if (uuids.isEmpty()) {
        return 0;
    }

    int sentCount = 0;
    for (auto it = m_clientUuids.constBegin(); it != m_clientUuids.constEnd(); ++it) {
        if (uuids.contains(it.value())) {
            it.key()->sendTextMessage(message);
            ++sentCount;
        }
    }
    return sentCount;
}

void MessagingServer::setPermissionManager(QObject *manager)
{
    m_permissionManager = manager;
}

void MessagingServer::onNewConnection()
{
    QWebSocket *client = m_server->nextPendingConnection();
    if (!client) {
        return;
    }

    const QHostAddress clientAddress = client->peerAddress();
    qDebug() << "New client connected:" << clientAddress;
    const QString fingerprint = SecurityService::certificateFingerprint(
        client->sslConfiguration().peerCertificate());
    m_clientFingerprints.insert(client, fingerprint);

    // Vérifier si la machine est autorisée (issue #70)
    bool authorized = false;
    if (m_permissionManager) {
        QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorizedByCertificate",
                                   Qt::DirectConnection,
                                   Q_RETURN_ARG(bool, authorized),
                                   Q_ARG(QString, fingerprint));
        if (authorized) {
            QMetaObject::invokeMethod(m_permissionManager, "recordMachineSeen",
                                      Qt::DirectConnection, Q_ARG(QString, fingerprint),
                                      Q_ARG(QString, clientAddress.toString()));
        } else if (!fingerprint.trimmed().isEmpty()) {
            // Machine inconnue/pending/revoked : on l'enregistre quand meme
            // pour qu'elle apparaisse dans l'admin ("Machine detectee -
            // autorisation requise"), sans jamais l'autoriser ici.
            QMetaObject::invokeMethod(m_permissionManager, "registerPendingMachineByCertificate",
                                      Qt::DirectConnection, Q_ARG(QString, fingerprint),
                                      Q_ARG(QString, clientAddress.toString()),
                                      Q_ARG(QString, QString()));
        }
    }
    m_clientAuthorized.insert(client, authorized);

    connect(client, &QWebSocket::textMessageReceived, this, &MessagingServer::onTextMessageReceived);
    connect(client, &QWebSocket::disconnected, this, &MessagingServer::onSocketDisconnected);

    m_clients.append(client);
    emit clientConnected(clientAddress);
}

void MessagingServer::onTextMessageReceived(const QString &message)
{
    QWebSocket *client = qobject_cast<QWebSocket*>(sender());
    if (!client) {
        return;
    }

    // Handshake d'identification : chaque client envoie son userUuid juste
    // apres connexion (cf. Application::sendIdentifyIfReady). On l'intercepte
    // ici plutot que de le laisser remonter jusqu'a MessagingManager, qui ne
    // sait traiter que les types "message"/"group_created"/"member_added"/"member_removed".
    // Sans ce handshake, le serveur ne peut associer aucune connexion a un
    // utilisateur, et sendToUuids() ne peut donc cibler personne (issue #2).
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8(), &parseError);
    if (parseError.error == QJsonParseError::NoError && doc.isObject()) {
        const QJsonObject obj = doc.object();
        if (obj.value(QStringLiteral("type")).toString() == QStringLiteral("identify")) {
            const QString claimedFingerprint = obj.value(QStringLiteral("certificate_fingerprint")).toString().toLower();
            if (claimedFingerprint.isEmpty() || claimedFingerprint != m_clientFingerprints.value(client)) {
                client->close();
                return;
            }
            const QString userUuid = obj.value(QStringLiteral("userUuid")).toString();
            if (!userUuid.isEmpty()) {
                m_clientUuids.insert(client, userUuid);
                qDebug() << "Client" << client->peerAddress() << "identifie comme utilisateur" << userUuid;
            }
            bool authorized = false;
            if (m_permissionManager) {
                QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorizedByCertificate",
                                          Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                          Q_ARG(QString, m_clientFingerprints.value(client)));
            }
            m_clientAuthorized.insert(client, authorized);
            return;
        }
    }

    const QString messageType = (parseError.error == QJsonParseError::NoError && doc.isObject())
        ? doc.object().value(QStringLiteral("type")).toString()
        : QString();

    if (!m_clientAuthorized.value(client, false)
        && messageType != QStringLiteral("authorized_machine_event")) {
        qWarning() << "Message ignored from pending machine" << client->peerAddress();
        return;
    }

    qDebug() << "Message received from" << client->peerAddress() << ":" << message;
    emit messageReceived(message, client->peerAddress());
}

void MessagingServer::onSocketDisconnected()
{
    QWebSocket *client = qobject_cast<QWebSocket*>(sender());
    if (!client) {
        return;
    }

    qDebug() << "Client disconnected:" << client->peerAddress();
    emit clientDisconnected(client->peerAddress());

    m_clients.removeAll(client);
    m_clientUuids.remove(client);
    m_clientFingerprints.remove(client);
    m_clientAuthorized.remove(client);
    client->deleteLater();
}

} // namespace network
