#include "MessagingService.h"

#include <QWebSocket>
#include <QDebug>

namespace network {

MessagingService::MessagingService(QObject *parent)
    : QObject(parent)
{
    m_socket = new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this);

    connect(m_socket, &QWebSocket::connected, this, &MessagingService::onConnected);
    connect(m_socket, &QWebSocket::disconnected, this, &MessagingService::onDisconnected);
    connect(m_socket, &QWebSocket::textMessageReceived, this, &MessagingService::onTextMessageReceived);
    connect(m_socket, &QWebSocket::errorOccurred, this, &MessagingService::onError);
}

MessagingService::~MessagingService()
{
    if (m_socket) {
        m_socket->close();
        m_socket->deleteLater();
    }
}

bool MessagingService::connectToHost(const QHostAddress &address, quint16 port)
{
    if (m_connected) {
        qWarning() << "Already connected, disconnect first";
        return false;
    }

    const QString url = QStringLiteral("ws://%1:%2").arg(address.toString()).arg(port);
    m_socket->open(QUrl(url));
    return true;
}

void MessagingService::disconnectFromHost()
{
    if (m_socket) {
        m_socket->close();
    }
}

bool MessagingService::sendMessage(const QString &message)
{
    if (!m_connected || !m_socket) {
        qWarning() << "Cannot send message: not connected";
        return false;
    }

    const qint64 bytesSent = m_socket->sendTextMessage(message);
    if (bytesSent < 0) {
        qWarning() << "Failed to send message:" << m_socket->errorString();
        return false;
    }

    return true;
}

bool MessagingService::isConnected() const
{
    return m_connected;
}

QHostAddress MessagingService::peerAddress() const
{
    if (!m_connected || !m_socket) {
        return QHostAddress();
    }
    return m_socket->peerAddress();
}

quint16 MessagingService::peerPort() const
{
    if (!m_connected || !m_socket) {
        return 0;
    }
    return m_socket->peerPort();
}

void MessagingService::onConnected()
{
    m_connected = true;
    qDebug() << "WebSocket connected to" << m_socket->peerAddress() << ":" << m_socket->peerPort();
    emit connected();
}

void MessagingService::onDisconnected()
{
    m_connected = false;
    qDebug() << "WebSocket disconnected";
    emit disconnected();
}

void MessagingService::onTextMessageReceived(const QString &message)
{
    qDebug() << "Message received:" << message;
    emit messageReceived(message);
}

void MessagingService::onError()
{
    qWarning() << "WebSocket error:" << m_socket->errorString();
    emit error(m_socket->errorString());
}

} // namespace network
