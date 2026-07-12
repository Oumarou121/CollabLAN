#include "SyncNetworkService.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QTcpServer>
#include <QTcpSocket>

#include "SyncProtocol.h"

namespace network {

SyncNetworkService::SyncNetworkService(QString localMachineId, QString localMachineName, QObject *parent)
    : QObject(parent)
    , m_localMachineId(std::move(localMachineId))
    , m_localMachineName(std::move(localMachineName))
    , m_server(new QTcpServer(this))
{
    connect(m_server, &QTcpServer::newConnection, this, [this]() {
        while (m_server->hasPendingConnections()) {
            QTcpSocket *socket = m_server->nextPendingConnection();
            setupSocket(socket, QString());
        }
    });
}

SyncNetworkService::~SyncNetworkService() = default;

bool SyncNetworkService::start(quint16 port)
{
    return m_server->listen(QHostAddress::Any, port);
}

void SyncNetworkService::stop()
{
    m_server->close();
    const auto sockets = m_connections.keys();
    for (QTcpSocket *socket : sockets) {
        socket->disconnectFromHost();
    }
}

bool SyncNetworkService::isListening() const
{
    return m_server->isListening();
}

void SyncNetworkService::connectToPeer(const QString &peerId, const QHostAddress &address, quint16 port)
{
    if (connectionForPeer(peerId) != nullptr) {
        return; // deja connecte
    }

    QTcpSocket *socket = new QTcpSocket(this);
    setupSocket(socket, peerId);
    socket->connectToHost(address, port);
}

void SyncNetworkService::disconnectFromPeer(const QString &peerId)
{
    if (Connection *connection = connectionForPeer(peerId)) {
        connection->socket->disconnectFromHost();
    }
}

QStringList SyncNetworkService::connectedPeers() const
{
    QStringList peers;
    for (const Connection &connection : m_connections) {
        if (!connection.peerId.isEmpty()) {
            peers << connection.peerId;
        }
    }
    return peers;
}

void SyncNetworkService::setupSocket(QTcpSocket *socket, const QString &knownPeerId)
{
    Connection connection;
    connection.socket = socket;
    connection.peerId = knownPeerId;
    m_connections.insert(socket, connection);

    connect(socket, &QTcpSocket::connected, this, [this, socket]() {
        // Le HELLO permet au poste distant de nous identifier meme sur
        // une connexion sortante.
        socket->write(SyncProtocol::serialize(SyncProtocol::makeHello(m_localMachineId, m_localMachineName)));
    });

    connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
        auto it = m_connections.find(socket);
        if (it == m_connections.end()) {
            return;
        }
        it->buffer.append(socket->readAll());
        while (auto message = SyncProtocol::takeNextMessage(it->buffer)) {
            handleMessage(socket, *message);
        }
    });

    connect(socket, &QTcpSocket::disconnected, this, [this, socket]() {
        removeConnectionFor(socket);
        socket->deleteLater();
    });

    connect(socket, &QTcpSocket::errorOccurred, this, [this, socket](QAbstractSocket::SocketError) {
        removeConnectionFor(socket);
        socket->deleteLater();
    });
}

void SyncNetworkService::handleMessage(QTcpSocket *socket, const QJsonObject &message)
{
    Connection *connection = connectionForSocket(socket);
    if (!connection) {
        return;
    }

    const auto type = SyncProtocol::messageTypeFromString(message.value(QStringLiteral("type")).toString());

    if (type == SyncProtocol::MessageType::Hello) {
        const QString peerId = message.value(QStringLiteral("machineId")).toString();
        const bool wasKnown = !connection->peerId.isEmpty();
        connection->peerId = peerId;
        if (!wasKnown) {
            emit peerConnected(peerId);
        }
        return;
    }

    if (connection->peerId.isEmpty()) {
        return; // message applicatif recu avant le HELLO : ignore.
    }

    const QString peerId = connection->peerId;
    const QString folder = message.value(QStringLiteral("folder")).toString();

    switch (type) {
    case SyncProtocol::MessageType::SyncRequest:
        emit syncRequestReceived(peerId, folder);
        break;
    case SyncProtocol::MessageType::SyncResponse:
        emit syncResponseReceived(peerId, folder, message.value(QStringLiteral("files")).toArray());
        break;
    case SyncProtocol::MessageType::FileInfo:
        emit fileInfoReceived(peerId, folder,
                               message.value(QStringLiteral("path")).toString(),
                               message.value(QStringLiteral("hash")).toString(),
                               static_cast<qint64>(message.value(QStringLiteral("size")).toDouble()),
                               message.value(QStringLiteral("version")).toInt());
        break;
    case SyncProtocol::MessageType::FileRequest:
        emit fileRequestReceived(peerId, folder,
                                  message.value(QStringLiteral("path")).toString(),
                                  static_cast<qint64>(message.value(QStringLiteral("offset")).toDouble()));
        break;
    case SyncProtocol::MessageType::FileChunk:
        emit fileChunkReceived(peerId, folder,
                                message.value(QStringLiteral("path")).toString(),
                                static_cast<qint64>(message.value(QStringLiteral("offset")).toDouble()),
                                QByteArray::fromBase64(message.value(QStringLiteral("data")).toString().toLatin1()),
                                message.value(QStringLiteral("isLast")).toBool());
        break;
    case SyncProtocol::MessageType::DeleteFile:
        emit deleteFileReceived(peerId, folder,
                                 message.value(QStringLiteral("path")).toString(),
                                 message.value(QStringLiteral("version")).toInt());
        break;
    case SyncProtocol::MessageType::RenameFile:
        emit renameFileReceived(peerId, folder,
                                 message.value(QStringLiteral("oldPath")).toString(),
                                 message.value(QStringLiteral("newPath")).toString(),
                                 message.value(QStringLiteral("version")).toInt());
        break;
    case SyncProtocol::MessageType::SyncFinished:
        emit syncFinishedReceived(peerId, folder);
        break;
    default:
        break;
    }
}

void SyncNetworkService::sendToPeer(const QString &peerId, const QJsonObject &message)
{
    if (Connection *connection = connectionForPeer(peerId)) {
        connection->socket->write(SyncProtocol::serialize(message));
    }
}

void SyncNetworkService::removeConnectionFor(QTcpSocket *socket)
{
    const auto it = m_connections.find(socket);
    if (it == m_connections.end()) {
        return;
    }
    const QString peerId = it->peerId;
    m_connections.erase(it);
    if (!peerId.isEmpty()) {
        emit peerDisconnected(peerId);
    }
}

SyncNetworkService::Connection *SyncNetworkService::connectionForSocket(QTcpSocket *socket)
{
    auto it = m_connections.find(socket);
    return it == m_connections.end() ? nullptr : &(*it);
}

SyncNetworkService::Connection *SyncNetworkService::connectionForPeer(const QString &peerId)
{
    for (auto it = m_connections.begin(); it != m_connections.end(); ++it) {
        if (it->peerId == peerId) {
            return &(*it);
        }
    }
    return nullptr;
}

void SyncNetworkService::broadcastFileInfo(const QString &folder, const QString &path, const QString &hash, qint64 size, int version)
{
    const QJsonObject message = SyncProtocol::makeFileInfo(folder, path, hash, size, version);
    const QByteArray line = SyncProtocol::serialize(message);
    for (Connection &connection : m_connections) {
        if (!connection.peerId.isEmpty()) {
            connection.socket->write(line);
        }
    }
}

void SyncNetworkService::broadcastDeleteFile(const QString &folder, const QString &path, int version)
{
    const QByteArray line = SyncProtocol::serialize(SyncProtocol::makeDeleteFile(folder, path, version));
    for (Connection &connection : m_connections) {
        if (!connection.peerId.isEmpty()) {
            connection.socket->write(line);
        }
    }
}

void SyncNetworkService::broadcastRenameFile(const QString &folder, const QString &oldPath, const QString &newPath, int version)
{
    const QByteArray line = SyncProtocol::serialize(SyncProtocol::makeRenameFile(folder, oldPath, newPath, version));
    for (Connection &connection : m_connections) {
        if (!connection.peerId.isEmpty()) {
            connection.socket->write(line);
        }
    }
}

void SyncNetworkService::sendSyncRequest(const QString &peerId, const QString &folder)
{
    sendToPeer(peerId, SyncProtocol::makeSyncRequest(folder));
}

void SyncNetworkService::sendSyncResponse(const QString &peerId, const QString &folder, const QJsonArray &files)
{
    sendToPeer(peerId, SyncProtocol::makeSyncResponse(folder, files));
}

void SyncNetworkService::sendFileRequest(const QString &peerId, const QString &folder, const QString &path, qint64 offset)
{
    sendToPeer(peerId, SyncProtocol::makeFileRequest(folder, path, offset));
}

void SyncNetworkService::sendFileChunk(const QString &peerId, const QString &folder, const QString &path, qint64 offset, const QByteArray &data, bool isLast)
{
    sendToPeer(peerId, SyncProtocol::makeFileChunk(folder, path, offset, data, isLast));
}

void SyncNetworkService::sendSyncFinished(const QString &peerId, const QString &folder)
{
    sendToPeer(peerId, SyncProtocol::makeSyncFinished(folder));
}

} // namespace network
