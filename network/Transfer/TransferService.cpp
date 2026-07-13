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
#include <QByteArray>

namespace network {

const QByteArray TransferService::kMagic = QByteArrayLiteral("CLFT");

namespace {

// Serialise (fileName, fileSize, senderUuid, recipientUuid, senderMachineId,
// compressionFlags) dans un QByteArray auto-suffisant.
//
// compressionFlags est un octet dont les bits signifient :
//   bit 0 (0x01) : compression zlib (qCompress/qUncompress) activee.
//
// Le champ est facultatif du point de vue des anciens recepteurs : un
// destinataire plus ancien (sans connaissance de compressionFlags) lira
// senderMachineId puis s'arretera la ; les octets supplementaires sont
// ignores car le payload est encadre par sa taille (frameOf()). Un ancien
// expediteur qui n'emet pas compressionFlags est traite comme 0x00 par
// decodeHeader() (pas de compression).
QByteArray encodeHeader(const QString &fileName, qint64 fileSize, const QString &senderUuid,
                         const QString &recipientUuid, const QString &senderMachineId,
                         quint8 compressionFlags = 0)
{
    QByteArray payload;
    QDataStream stream(&payload, QIODevice::WriteOnly);
    stream.setVersion(QDataStream::Qt_6_0);
    stream << fileName << static_cast<qint64>(fileSize)
           << senderUuid << recipientUuid
           << senderMachineId
           << compressionFlags;
    return payload;
}

bool decodeHeader(const QByteArray &payload, QString *fileName, qint64 *fileSize,
                   QString *senderUuid, QString *recipientUuid, QString *senderMachineId,
                   quint8 *compressionFlags = nullptr)
{
    QDataStream stream(payload);
    stream.setVersion(QDataStream::Qt_6_0);
    stream >> *fileName >> *fileSize >> *senderUuid >> *recipientUuid;
    if (stream.status() != QDataStream::Ok) {
        senderMachineId->clear();
        if (compressionFlags) *compressionFlags = 0;
        return false;
    }
    // senderMachineId : champ optionnel ajoute apres la v1 du protocole.
    stream >> *senderMachineId;
    if (stream.status() != QDataStream::Ok) {
        senderMachineId->clear();
        if (compressionFlags) *compressionFlags = 0;
        return true; // champs obligatoires presents, optionnels absents = OK
    }
    // compressionFlags : champ optionnel ajoute apres senderMachineId.
    if (compressionFlags) {
        stream >> *compressionFlags;
        if (stream.status() != QDataStream::Ok) {
            *compressionFlags = 0;
        }
    }
    return true;
}

// Serialise/deserialise un entier 64 bits (utilise pour la reponse
// resumeOffset envoyee par le destinataire apres l'entete).
QByteArray encodeUint64(quint64 value)
{
    QByteArray payload;
    QDataStream stream(&payload, QIODevice::WriteOnly);
    stream.setVersion(QDataStream::Qt_6_0);
    stream << value;
    return payload;
}

bool decodeUint64(const QByteArray &payload, quint64 *value)
{
    QDataStream stream(payload);
    stream.setVersion(QDataStream::Qt_6_0);
    stream >> *value;
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

// Nettoie un nom de dossier destine au systeme de fichiers (retire les
// caracteres invalides sous Windows : \ / : * ? " < > |, ainsi que les
// espaces de debut/fin) - utilise pour regrouper cote reception les
// fichiers d'un meme correspondant sous un seul sous-dossier de
// receiveDirectory(). Renvoie une chaine vide si le nom d'origine ne
// contient plus rien d'exploitable une fois nettoye.
QString sanitizeFolderName(const QString &name)
{
    QString cleaned = name;
    static const QString kInvalidChars = QStringLiteral("\\/:*?\"<>|");
    for (const QChar &c : kInvalidChars) {
        cleaned.remove(c);
    }
    return cleaned.trimmed();
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
    return kDefaultBlockSize;
}

quint16 TransferService::defaultPort()
{
    return kDefaultPort;
}

void TransferService::setReceiveDirectory(const QString &dir)
{
    m_receiveDirOverride = dir;
}

void TransferService::setLocalMachineId(const QString &machineId)
{
    m_localMachineId = machineId;
}

void TransferService::setCompressionEnabled(bool enabled)
{
    m_compressionEnabled = enabled;
}

void TransferService::setBlockSize(quint32 bytes)
{
    if (bytes == 0) {
        qWarning() << "TransferService::setBlockSize: taille invalide (0) ; conserve" << m_blockSize;
        return;
    }
    m_blockSize = bytes;
}

quint32 TransferService::currentBlockSize() const
{
    return m_blockSize;
}

void TransferService::setPeerFolderNameResolver(
    std::function<QString(const QHostAddress &, const QString &)> resolver)
{
    m_peerFolderNameResolver = std::move(resolver);
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

bool TransferService::sendFile(const QHostAddress &host, quint16 port, const QString &filePath,
                                const QString &senderUuid, const QString &recipientUuid)
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
    state.senderUuid = senderUuid;
    state.recipientUuid = recipientUuid;
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
    // peerMachineId (dernier argument) : vide cote envoi - on connait deja
    // l'identite du destinataire directement via le pair choisi dans
    // DiscoveryService (TransferContext/TransferManager n'ont pas besoin
    // d'un aller-retour reseau pour la resoudre dans ce sens). Seul le
    // sens reception en a besoin (voir onServerSocketReadyRead()).
    emit transferStarted(state.transferKey, info.fileName(), state.fileSize, false, 0,
                          state.senderUuid, state.recipientUuid, socket->peerAddress(), QString());

    const quint8 compressionFlags = m_compressionEnabled ? 0x01 : 0x00;
    const QByteArray header = encodeHeader(info.fileName(), state.fileSize, state.senderUuid,
                                            state.recipientUuid, m_localMachineId,
                                            compressionFlags);
    socket->write(frameOf(header));
    // La reponse (resumeOffset) arrive de facon asynchrone dans
    // onClientSocketReadyRead ; voir state.resumeOffsetReceived.
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
    state.buffer.append(socket->readAll());

    while (true) {
        if (!state.resumeOffsetReceived) {
            // Reponse d'en-tete : trame [quint32 taille][quint64 resumeOffset].
            if (state.pendingFrameSize < 0) {
                if (state.buffer.size() < static_cast<int>(sizeof(quint32))) {
                    break;
                }
                QDataStream sizeStream(state.buffer);
                sizeStream.setVersion(QDataStream::Qt_6_0);
                quint32 len = 0;
                sizeStream >> len;
                state.pendingFrameSize = len;
                state.buffer.remove(0, sizeof(quint32));
            }

            if (state.buffer.size() < state.pendingFrameSize) {
                break;
            }

            const QByteArray payload = state.buffer.left(static_cast<int>(state.pendingFrameSize));
            state.buffer.remove(0, static_cast<int>(state.pendingFrameSize));
            state.pendingFrameSize = -1;

            quint64 resumeOffset = 0;
            if (!decodeUint64(payload, &resumeOffset) || static_cast<qint64>(resumeOffset) > state.fileSize) {
                finishSend(socket, false, QStringLiteral("Reponse de reprise invalide"));
                return;
            }

            state.resumeOffsetReceived = true;
            state.bytesSent = static_cast<qint64>(resumeOffset);
            if (!state.file->seek(state.bytesSent)) {
                finishSend(socket, false, QStringLiteral("Impossible de reprendre le fichier local"));
                return;
            }

            emit transferProgress(state.transferKey, state.bytesSent, state.fileSize);
            sendNextBlock(socket);
            // sendNextBlock() peut avoir termine le transfert (fichier deja
            // entierement envoye, ou erreur de lecture) et appele
            // finishSend(), qui retire l'entree de m_sendStates : "state"
            // serait alors une reference pendante. On arrete ici dans ce cas.
            if (!m_sendStates.contains(socket)) {
                return;
            }
            continue;
        }

        // Accuses de reception des blocs de donnees (un octet chacun).
        if (!state.waitingForAck || state.buffer.isEmpty()) {
            break;
        }

        const char ack = state.buffer.at(0);
        state.buffer.remove(0, 1);

        if (ack != kAckByte) {
            finishSend(socket, false, QStringLiteral("Accuse de reception invalide"));
            return;
        }
        state.waitingForAck = false;
        sendNextBlock(socket);
        // Meme remarque que ci-dessus : le transfert peut s'etre termine
        // (dernier bloc acquitte) et avoir invalide "state".
        if (!m_sendStates.contains(socket)) {
            return;
        }
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

    const QByteArray raw = state.file->read(static_cast<qint64>(m_blockSize));
    if (raw.isEmpty() && state.bytesSent < state.fileSize) {
        finishSend(socket, false, QStringLiteral("Erreur de lecture du fichier"));
        return;
    }

    // Compression optionnelle : compresse le bloc avec zlib avant l'encadrage.
    // Le recepteur sait qu'il faut decompresser grace au champ compressionFlags
    // negocie dans l'en-tete (state.compressionEnabled cote recepteur).
    const QByteArray chunk = m_compressionEnabled ? qCompress(raw) : raw;
    socket->write(frameOf(chunk));
    state.bytesSent += raw.size();   // bytesSent compte les octets non compresses
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
    socket->flush();
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
            QString senderUuid;
            QString recipientUuid;
            QString senderMachineId;
            quint8 compressionFlags = 0;
            if (!decodeHeader(payload, &fileName, &fileSize, &senderUuid, &recipientUuid, &senderMachineId, &compressionFlags)
                || fileSize < 0) {
                finishReceive(socket, false, QStringLiteral("En-tete de transfert invalide"));
                return;
            }

            // N'utiliser que le nom de fichier (pas de chemin) pour eviter
            // toute ecriture en dehors du repertoire de reception.
            state.fileName = QFileInfo(fileName).fileName();
            state.fileSize = fileSize;
            state.senderUuid = senderUuid;
            state.recipientUuid = recipientUuid;
            state.senderMachineId = senderMachineId;
            state.compressionEnabled = (compressionFlags & 0x01) != 0;
            state.headerParsed = true;

            const QString dir = receiveDirectory();
            // Sous-dossier par correspondant : regroupe tous les fichiers
            // recus d'un meme pair (envoi comme reception, l'historique
            // reste associe au meme sender_uuid/recipient_uuid - migration
            // #017) sous "<receiveDirectory>/<nom du pair>/", plutot que
            // dans un unique repertoire plat. m_peerFolderNameResolver
            // (typiquement branche sur DiscoveryService, voir
            // Application::setupTransferPeerFolders()) donne un nom
            // affichable ; a defaut, repli sur l'UUID machine brut du
            // pair (senderMachineId, toujours renseigne en usage reel -
            // voir setLocalMachineId()). Si aucun des deux n'est
            // disponible (ex. TransferService utilise isolement, sans
            // machine id configure, comme dans les tests unitaires), on
            // conserve le repertoire plat d'origine plutot que de grouper
            // par adresse IP, non stable (DHCP, IPv4-mappee en IPv6...).
            QString peerFolderName;
            if (m_peerFolderNameResolver) {
                peerFolderName = sanitizeFolderName(
                    m_peerFolderNameResolver(socket->peerAddress(), senderMachineId));
            }
            if (peerFolderName.isEmpty()) {
                peerFolderName = sanitizeFolderName(senderMachineId);
            }
            const QString destDir = peerFolderName.isEmpty()
                ? dir
                : QDir(dir).filePath(peerFolderName);
            QDir().mkpath(destDir);
            state.destinationPath = QDir(destDir).filePath(state.fileName);
            state.partialPath = state.destinationPath + QStringLiteral(".part");

            // Reprise (issue #54) : si un fichier partiel de meme nom
            // existe deja et n'est pas plus grand que la taille finale
            // attendue, on reprend a partir de sa taille actuelle.
            // Sinon (taille incoherente, ex. fichier different portant
            // le meme nom), on repart de zero en l'ecrasant.
            qint64 resumeOffset = 0;
            const QFileInfo partialInfo(state.partialPath);
            if (partialInfo.exists() && partialInfo.size() > 0 && partialInfo.size() <= state.fileSize) {
                resumeOffset = partialInfo.size();
            }

            state.file = new QFile(state.partialPath);
            const QIODevice::OpenMode mode = resumeOffset > 0
                ? (QIODevice::WriteOnly | QIODevice::Append)
                : (QIODevice::WriteOnly | QIODevice::Truncate);
            if (!state.file->open(mode)) {
                finishReceive(socket, false, QStringLiteral("Impossible de creer le fichier local"));
                return;
            }
            state.bytesReceived = resumeOffset;

            emit transferStarted(state.transferKey, state.fileName, state.fileSize, true, resumeOffset,
                                  state.senderUuid, state.recipientUuid, socket->peerAddress(),
                                  state.senderMachineId);
            if (resumeOffset > 0) {
                emit transferProgress(state.transferKey, state.bytesReceived, state.fileSize);
            }

            state.headerAcked = true;
            socket->write(frameOf(encodeUint64(static_cast<quint64>(resumeOffset))));

            if (state.fileSize == 0 || state.bytesReceived >= state.fileSize) {
                finishReceive(socket, true);
                return;
            }
            continue;
        }

        // Bloc de donnees : decompresse si l'expediteur a active la compression.
        const QByteArray data = state.compressionEnabled ? qUncompress(payload) : payload;
        if (state.compressionEnabled && data.isEmpty()) {
            finishReceive(socket, false, QStringLiteral("Erreur de decompression du bloc"));
            return;
        }
        if (state.file->write(data) != data.size()) {
            finishReceive(socket, false, QStringLiteral("Erreur d'ecriture disque"));
            return;
        }
        state.bytesReceived += data.size();
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
        // Transfert termine : promouvoir le fichier temporaire "<nom>.part"
        // vers son nom final.
        if (!state.partialPath.isEmpty() && state.partialPath != state.destinationPath) {
            QFile::remove(state.destinationPath); // Ecrase un fichier final precedent le cas echeant.
            QFile::rename(state.partialPath, state.destinationPath);
        }
        emit transferCompleted(state.transferKey, state.destinationPath);
    } else {
        // Ne PAS supprimer le fichier partiel : il permet de reprendre le
        // transfert a partir du dernier bloc confirme (issue #54) lors
        // d'un prochain appel a sendFile() pour le meme fichier.
        emit transferFailed(state.transferKey, errorString);
    }

    socket->disconnect(this);
    // Flush avant fermeture : le dernier octet d'accuse de reception
    // (ou la reponse resumeOffset pour un fichier vide) a pu etre remis
    // au socket juste avant cet appel ; sans flush(), close() peut
    // couper la connexion avant son envoi effectif, ce que l'expediteur
    // percoit comme "connexion fermee par l'hote distant" au lieu de
    // recevoir l'accusee final (voir issue #53/#54).
    socket->flush();
    socket->close();
    socket->deleteLater();
}

} // namespace network