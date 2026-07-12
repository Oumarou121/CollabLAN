#include "MessagingServer.h"

#include "Security/SecurityService.h"

#include <QWebSocketServer>
#include <QWebSocket>
#include <QHostAddress>
#include <QSslConfiguration>
#include <QSslKey>
#include <QFile>
#include <QDebug>
#include <QMetaObject>

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
                sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone); // Pour le développement local
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

int MessagingServer::broadcastMessage(const QString &message)
{
    int sentCount = 0;
    for (QWebSocket *client : m_clients) {
        client->sendTextMessage(message);
        ++sentCount;
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

    // Vérifier si la machine est autorisée (issue #70)
    if (m_permissionManager) {
        bool authorized = true;
        QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorized",
                                   Qt::DirectConnection,
                                   Q_RETURN_ARG(bool, authorized),
                                   Q_ARG(QString, clientAddress.toString()));
        if (!authorized) {
            qWarning() << "Connection refused: machine" << clientAddress.toString() << "is not authorized";
            client->close();
            client->deleteLater();
            emit connectionRefused(clientAddress, QStringLiteral("Machine not authorized"));
            return;
        }
    }

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
    client->deleteLater();
}

} // namespace network