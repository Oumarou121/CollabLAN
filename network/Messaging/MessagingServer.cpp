#include "MessagingServer.h"

#include "Security/SecurityService.h"

#include <QWebSocketServer>
#include <QWebSocket>
#include <QHostAddress>
#include <QSslConfiguration>
#include <QSslKey>
#include <QDebug>

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
    if (m_securityService && m_securityService->isReady()) {
        QSslConfiguration sslConfig = m_server->sslConfiguration();
        QList<QSslCertificate> certs = QSslCertificate::fromData(m_securityService->certificatePem());
        if (!certs.isEmpty()) {
            sslConfig.setLocalCertificate(certs.first());
        }
        sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone); // Pour le développement local
        m_server->setSslConfiguration(sslConfig);
    } else {
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

void MessagingServer::onNewConnection()
{
    QWebSocket *client = m_server->nextPendingConnection();
    if (!client) {
        return;
    }

    qDebug() << "New client connected:" << client->peerAddress();

    connect(client, &QWebSocket::textMessageReceived, this, &MessagingServer::onTextMessageReceived);
    connect(client, &QWebSocket::disconnected, this, &MessagingServer::onSocketDisconnected);

    m_clients.append(client);
    emit clientConnected(client->peerAddress());
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
