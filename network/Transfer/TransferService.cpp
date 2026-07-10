#include "TransferService.h"

#include <QTcpServer>
#include <QTcpSocket>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QDataStream>
#include <QStandardPaths>
#include <QUuid>
#include <QDebug>

namespace network {

const QByteArray TransferService::kMagic = QByteArrayLiteral("CLFT");

namespace {

// Serialise (fileName, fileSize) dans un QByteArray auto-suffisant,
// utilise a la fois pour l'envoi (writeHeader) et la reception (parse).
QByteArray encodeHeader(const QString &fileName, qint64 fileSize)
{
    QByteArray payload;
    QDataStream stream(&payload, QIODevice::WriteOnly);
    stream.setVersion(QDataStream::Qt_6_0);
    stream << fileName << static_cast<qint64>(fileSize);
    return payload;
}

bool decodeHeader(const QByteArray &payload, QString *fileName, qint64 *fileSize)
{
    QDataStream stream(payload);
    stream.setVersion(QDataStream::Qt_6_0);
    stream >> *fileName >> *fileSize;
    return stream.status() == QDataStream::Ok;
}

// Prefixe un payload par sa taille (quint32, ordre reseau via QDataStream).
QByteArray frameOf(const QByteArray &payload)
{
    QByteArray frame;
    QDataStream stream(&frame, QIODevice::WriteOnly);
    stream.setVersion(QDataStream::Qt_6_0);
    stream << static_cast<quint32>(payload.size());
    frame.append(payload);
    return frame;
}

} // namespace

TransferService::TransferService(QObject *parent)
    : QObject(parent)
{
}

TransferService::~TransferService()
{
    stop();
}

bool TransferService::start(quint16 port)
{
    if (m_server) {
        qWarning() << "TransferService already running";
        return false;
    }

    m_server = new QTcpServer(this);
    connect(m_server, &QTcpServer::newConnection, this, &TransferService::onNewConnection);

    if (!m_server->listen(QHostAddress::Any, port)) {
        qWarning() << "Failed to start TransferService:" << m_server->errorString();
        delete m_server;
        m_server = nullptr;
        return false;
    }

    qDebug() << "TransferService listening on port" << m_server->serverPort();
    return true;
}

void TransferService::stop()
{
    if (m_server) {
        m_server->close();
        delete m_server;
        m_server = nullptr;
    }

    for (auto it = m_receiveStates.begin(); it != m_receiveStates.end(); ++it) {
        QTcpSocket *socket = it.key();
        if (it.value().file) {
            it.value().file->close();
            delete it.value().file;
        }
        socket->disconnect(this);
        socket->close();
        socket->deleteLater();
    }
    m_receiveStates.clear();

    for (auto it = m_sendStates.begin(); it != m_sendStates.end(); ++it) {
        QTcpSocket *socket = it.key();
        if (it.value().file) {
            it.value().file->close();
            delete it.value().file;
        }
        socket->disconnect(this);
        socket->close();
        socket->deleteLater();
    }
    m_sendStates.clear();
}

bool TransferService::isRunning() const
{
    return m_server && m_server->isListening();
}

quint16 TransferService::port() const
{
    return m_server ? m_server->serverPort() : 0;
}

qint64 TransferService::blockSize()
{
    return kBlockSize;
}

void TransferService::setReceiveDirectory(const QString &dir)
{
    m_receiveDirOverride = dir;
}

QString TransferService::receiveDirectory() const
{
    if (!m_receiveDirOverride.isEmpty()) {
        return m_receiveDirOverride;
    }
    const QString base = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    return base + QStringLiteral("/CollabLAN Transfers");
}

QString TransferService::makeTransferKey(QTcpSocket *socket)
{
    Q_UNUSED(socket);
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

// ---------------------------------------------------------------------
// Cote expediteur
// ---------------------------------------------------------------------

bool TransferService::sendFile(const QHostAddress &host, quint16 port, const QString &filePath)
{
    auto *file = new QFile(filePath);
    if (!file->open(QIODevice::ReadOnly)) {
        qWarning() << "TransferService: cannot open file for sending:" << filePath;
        delete file;
        return false;
    }

    auto *socket = new QTcpSocket(this);

    SendState state;
    state.transferKey = makeTransferKey(socket);
    state.file = file;
    state.filePath = filePath;
    state.fileSize = file->size();
    state.bytesSent = 0;
    state.headerSent = false;
    state.waitingForAck = false;
    m_sendStates.insert(socket, state);

    connect(socket, &QTcpSocket::connected, this, &TransferService::onClientSocketConnected);
    connect(socket, &QTcpSocket::readyRead, this, &TransferService::onClientSocketReadyRead);
    connect(socket, &QTcpSocket::bytesWritten, this, &TransferService::onClientSocketBytesWritten);
    connect(socket, &QTcpSocket::errorOccurred, this, &TransferService::onClientSocketErrorOccurred);

    socket->connectToHost(host, port);
    return true;
}

void TransferService::onClientSocketConnected()
{
    auto *socket = qobject_cast<QTcpSocket*>(sender());
    if (!socket || !m_sendStates.contains(socket)) {
        return;
    }

    SendState &state = m_sendStates[socket];
    const QFileInfo info(state.filePath);
    emit transferStarted(state.transferKey, info.fileName(), state.fileSize, false);

    const QByteArray header = encodeHeader(info.fileName(), state.fileSize);
    socket->write(frameOf(header));
    state.waitingForAck = true;
}

void TransferService::onClientSocketBytesWritten(qint64 bytes)
{
    Q_UNUSED(bytes);
    // Rien a faire ici : on attend l'accuse de reception explicite avant
    // d'envoyer le bloc suivant (voir onClientSocketReadyRead), le
    // simple ecoulement des octets sur le socket ne suffit pas a
    // garantir que le destinataire a bien ecrit le bloc sur disque.
}

void TransferService::onClientSocketReadyRead()
{
    auto *socket = qobject_cast<QTcpSocket*>(sender());
    if (!socket || !m_sendStates.contains(socket)) {
        return;
    }

    SendState &state = m_sendStates[socket];

    // Consomme les octets d'accuse de reception disponibles (un octet
    // par bloc envoye). On peut en recevoir plusieurs d'un coup si le
    // reseau/systeme groupe les paquets.
    while (socket->bytesAvailable() > 0 && state.waitingForAck) {
        char ack = 0;
        if (socket->read(&ack, 1) != 1) {
            break;
        }
        if (ack != kAckByte) {
            finishSend(socket, false, QStringLiteral("Accuse de reception invalide"));
            return;
        }
        state.waitingForAck = false;
        sendNextBlock(socket);
    }
}

void TransferService::sendNextBlock(QTcpSocket *socket)
{
    if (!m_sendStates.contains(socket)) {
        return;
    }
    SendState &state = m_sendStates[socket];

    if (state.bytesSent >= state.fileSize) {
        finishSend(socket, true);
        return;
    }

    const QByteArray chunk = state.file->read(kBlockSize);
    if (chunk.isEmpty() && state.bytesSent < state.fileSize) {
        finishSend(socket, false, QStringLiteral("Erreur de lecture du fichier"));
        return;
    }

    socket->write(frameOf(chunk));
    state.bytesSent += chunk.size();
    state.waitingForAck = true;

    emit transferProgress(state.transferKey, state.bytesSent, state.fileSize);
}

void TransferService::onClientSocketErrorOccurred()
{
    auto *socket = qobject_cast<QTcpSocket*>(sender());
    if (!socket) {
        return;
    }
    finishSend(socket, false, socket->errorString());
}

void TransferService::finishSend(QTcpSocket *socket, bool success, const QString &errorString)
{
    if (!m_sendStates.contains(socket)) {
        return;
    }
    SendState state = m_sendStates.take(socket);

    if (state.file) {
        state.file->close();
        delete state.file;
    }

    if (success) {
        emit transferCompleted(state.transferKey, state.filePath);
    } else {
        emit transferFailed(state.transferKey, errorString);
    }

    socket->disconnect(this);
    socket->close();
    socket->deleteLater();
}

// ---------------------------------------------------------------------
// Cote destinataire
// ---------------------------------------------------------------------

void TransferService::onNewConnection()
{
    while (m_server->hasPendingConnections()) {
        QTcpSocket *socket = m_server->nextPendingConnection();
        if (!socket) {
            continue;
        }

        ReceiveState state;
        state.transferKey = makeTransferKey(socket);
        m_receiveStates.insert(socket, state);

        connect(socket, &QTcpSocket::readyRead, this, &TransferService::onServerSocketReadyRead);
        connect(socket, &QTcpSocket::disconnected, this, &TransferService::onServerSocketDisconnected);
    }
}

void TransferService::onServerSocketReadyRead()
{
    auto *socket = qobject_cast<QTcpSocket*>(sender());
    if (!socket || !m_receiveStates.contains(socket)) {
        return;
    }

    ReceiveState &state = m_receiveStates[socket];
    state.buffer.append(socket->readAll());

    // Traite autant de trames completes que possible dans le tampon.
    while (true) {
        if (state.pendingBlockSize < 0) {
            if (state.buffer.size() < static_cast<int>(sizeof(quint32))) {
                break; // Pas encore assez d'octets pour lire la taille de la trame.
            }
            QDataStream sizeStream(state.buffer);
            sizeStream.setVersion(QDataStream::Qt_6_0);
            quint32 len = 0;
            sizeStream >> len;
            state.pendingBlockSize = len;
            state.buffer.remove(0, sizeof(quint32));
        }

        if (state.buffer.size() < state.pendingBlockSize) {
            break; // Attend le reste de la trame.
        }

        const QByteArray payload = state.buffer.left(static_cast<int>(state.pendingBlockSize));
        state.buffer.remove(0, static_cast<int>(state.pendingBlockSize));
        state.pendingBlockSize = -1;

        if (!state.headerParsed) {
            QString fileName;
            qint64 fileSize = 0;
            if (!decodeHeader(payload, &fileName, &fileSize) || fileSize < 0) {
                finishReceive(socket, false, QStringLiteral("En-tete de transfert invalide"));
                return;
            }

            // N'utiliser que le nom de fichier (pas de chemin) pour eviter
            // toute ecriture en dehors du repertoire de reception.
            state.fileName = QFileInfo(fileName).fileName();
            state.fileSize = fileSize;
            state.headerParsed = true;

            const QString dir = receiveDirectory();
            QDir().mkpath(dir);
            state.destinationPath = QDir(dir).filePath(state.fileName);

            state.file = new QFile(state.destinationPath);
            if (!state.file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                finishReceive(socket, false, QStringLiteral("Impossible de creer le fichier local"));
                return;
            }

            emit transferStarted(state.transferKey, state.fileName, state.fileSize, true);

            socket->write(QByteArray(1, kAckByte));

            if (state.fileSize == 0) {
                finishReceive(socket, true);
                return;
            }
            continue;
        }

        // Bloc de donnees.
        if (state.file->write(payload) != payload.size()) {
            finishReceive(socket, false, QStringLiteral("Erreur d'ecriture disque"));
            return;
        }
        state.bytesReceived += payload.size();
        emit transferProgress(state.transferKey, state.bytesReceived, state.fileSize);

        socket->write(QByteArray(1, kAckByte));

        if (state.bytesReceived >= state.fileSize) {
            finishReceive(socket, true);
            return;
        }
    }
}

void TransferService::onServerSocketDisconnected()
{
    auto *socket = qobject_cast<QTcpSocket*>(sender());
    if (!socket) {
        return;
    }

    if (m_receiveStates.contains(socket)) {
        const ReceiveState &state = m_receiveStates[socket];
        const bool incomplete = !state.headerParsed || state.bytesReceived < state.fileSize;
        if (incomplete) {
            finishReceive(socket, false, QStringLiteral("Connexion interrompue"));
            return;
        }
    }

    socket->deleteLater();
}

void TransferService::finishReceive(QTcpSocket *socket, bool success, const QString &errorString)
{
    if (!m_receiveStates.contains(socket)) {
        socket->deleteLater();
        return;
    }
    ReceiveState state = m_receiveStates.take(socket);

    if (state.file) {
        state.file->close();
        delete state.file;
    }

    if (success) {
        emit transferCompleted(state.transferKey, state.destinationPath);
    } else {
        emit transferFailed(state.transferKey, errorString);
        if (!state.destinationPath.isEmpty()) {
            QFile::remove(state.destinationPath);
        }
    }

    socket->disconnect(this);
    socket->close();
    socket->deleteLater();
}

} // namespace network
