#include "TransferService.h"

#include <QTcpServer>
#include <QTcpSocket>
#include <QSslSocket>
#include <QSslConfiguration>
#include <QSslCertificate>
#include <QSslKey>
#include "Security/SecurityService.h"
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

const QByteArray kIdentityFramePrefix = QByteArrayLiteral("CLFT-ID1:");

class TransferTcpServer : public QTcpServer
{
public:
    explicit TransferTcpServer(QObject *parent = nullptr)
        : QTcpServer(parent)
    {
    }

protected:
    void incomingConnection(qintptr socketDescriptor) override
    {
        auto *socket = new QSslSocket(this);
        if (!socket->setSocketDescriptor(socketDescriptor)) {
            socket->deleteLater();
            return;
        }
        addPendingConnection(socket);
    }
};

bool configureTls(QSslSocket *socket, SecurityService *security, bool server)
{
    if (!security || !security->isReady()) return false;
    const auto certificates = QSslCertificate::fromData(security->certificatePem());
    QFile keyFile(security->privateKeyPath());
    if (certificates.isEmpty() || !keyFile.open(QIODevice::ReadOnly)) return false;
    QSslConfiguration configuration = socket->sslConfiguration();
    configuration.setLocalCertificate(certificates.first());
    configuration.setPrivateKey(QSslKey(keyFile.readAll(), QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey));
    configuration.setPeerVerifyMode(QSslSocket::QueryPeer);
    socket->setSslConfiguration(configuration);
    QObject::connect(socket, &QSslSocket::sslErrors, socket,
                     [socket](const QList<QSslError> &) { socket->ignoreSslErrors(); });
    return true;
}

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
                         quint8 compressionFlags = 0, bool isFolderTransfer = false)
{
    QByteArray payload;
    QDataStream stream(&payload, QIODevice::WriteOnly);
    stream.setVersion(QDataStream::Qt_6_0);
    stream << fileName << static_cast<qint64>(fileSize)
           << senderUuid << recipientUuid
           << senderMachineId
           << compressionFlags
           << isFolderTransfer;
    return payload;
}

bool decodeHeader(const QByteArray &payload, QString *fileName, qint64 *fileSize,
                   QString *senderUuid, QString *recipientUuid, QString *senderMachineId,
                   quint8 *compressionFlags = nullptr, bool *isFolderTransfer = nullptr)
{
    QDataStream stream(payload);
    stream.setVersion(QDataStream::Qt_6_0);
    stream >> *fileName >> *fileSize >> *senderUuid >> *recipientUuid;
    if (stream.status() != QDataStream::Ok) {
        senderMachineId->clear();
        if (compressionFlags) *compressionFlags = 0;
        if (isFolderTransfer) *isFolderTransfer = false;
        return false;
    }
    // senderMachineId : champ optionnel ajoute apres la v1 du protocole.
    stream >> *senderMachineId;
    if (stream.status() != QDataStream::Ok) {
        senderMachineId->clear();
        if (compressionFlags) *compressionFlags = 0;
        if (isFolderTransfer) *isFolderTransfer = false;
        return true; // champs obligatoires presents, optionnels absents = OK
    }
    // compressionFlags : champ optionnel ajoute apres senderMachineId.
    if (compressionFlags) {
        stream >> *compressionFlags;
        if (stream.status() != QDataStream::Ok) {
            *compressionFlags = 0;
        }
    }
    // isFolderTransfer : champ optionnel ajoute apres compressionFlags.
    if (isFolderTransfer) {
        stream >> *isFolderTransfer;
        if (stream.status() != QDataStream::Ok) {
            *isFolderTransfer = false;
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

    m_server = new TransferTcpServer(this);
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
    // Les sockets acceptes via m_server->nextPendingConnection() sont
    // parentes au QTcpServer (comportement par defaut de Qt). Si on
    // supprime m_server avant de traiter m_receiveStates, ces sockets
    // sont detruits en cascade et la boucle ci-dessous deviendrait un
    // use-after-free (c'etait la cause des crashs sur les tests qui
    // recoivent reellement un fichier). On detache donc chaque socket
    // du serveur (setParent(nullptr)) et on nettoie son etat AVANT de
    // detruire m_server.
    for (auto it = m_receiveStates.begin(); it != m_receiveStates.end(); ++it) {
        QTcpSocket *socket = it.key();
        if (it.value().file) {
            it.value().file->close();
            delete it.value().file;
        }
        socket->disconnect(this);
        socket->setParent(nullptr);
        socket->close();
        socket->deleteLater();
    }
    m_receiveStates.clear();

    if (m_server) {
        m_server->close();
        delete m_server;
        m_server = nullptr;
    }

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

QString TransferService::destKeyFor(const QHostAddress &host, quint16 port)
{
    return host.toString() + QStringLiteral(":") + QString::number(port);
}

bool TransferService::sendFile(const QHostAddress &host, quint16 port, const QString &filePath,
                                const QString &senderUuid, const QString &recipientUuid,
                                const QString &transferFileName, bool isFolderTransfer)
{
    // Verification rapide et synchrone : un fichier absent/illisible des
    // l'appel doit echouer immediatement (contrat historique de sendFile(),
    // toujours respecte par les appelants existants -- ex. TransferService::
    // sendMissingFileFails() dans les tests). Une fois mis en file, en
    // revanche, un probleme de lecture ne peut plus etre remonte que de
    // facon asynchrone via transferFailed() (voir startSendOnSocket()).
    const QFileInfo info(filePath);
    if (!info.exists() || !info.isReadable()) {
        qWarning() << "TransferService: cannot open file for sending:" << filePath;
        return false;
    }

    // CORRECTIF (pool de connexions reutilisables) : plutot que d'ouvrir
    // systematiquement une nouvelle connexion TCP ici, le fichier est mis
    // en file d'attente pour sa destination (host:port) ; dispatchSendQueue()
    // decide de reutiliser une connexion existante, d'en ouvrir une
    // nouvelle (si le pool n'est pas plein), ou de laisser le fichier
    // patienter (voir doc de classe, section 0).
    const QString destKey = destKeyFor(host, port);
    m_destInfo[destKey] = DestInfo{host, port};
    m_sendQueues[destKey].enqueue(PendingSendJob{filePath, senderUuid, recipientUuid,
                                                 transferFileName, isFolderTransfer});
    dispatchSendQueue(destKey);
    return true;
}

void TransferService::dispatchSendQueue(const QString &destKey)
{
    auto queueIt = m_sendQueues.find(destKey);
    if (queueIt == m_sendQueues.end() || queueIt->isEmpty()) {
        return;
    }
    if (m_activeSendConnections.value(destKey, 0) >= kMaxConnectionsPerPeer) {
        // Plafond atteint pour ce pair : le(s) fichier(s) restant(s)
        // patientent dans la file. Le prochain appel viendra de
        // finishSend() des qu'une des connexions existantes se libere
        // (fichier termine, sans qu'il en reste a lui enchainer).
        return;
    }

    const PendingSendJob job = queueIt->dequeue();
    const DestInfo dest = m_destInfo.value(destKey);

    auto *socket = new QSslSocket(this);
    m_socketDestKey.insert(socket, destKey);
    m_activeSendConnections[destKey] = m_activeSendConnections.value(destKey, 0) + 1;

    SendState state;
    state.pendingJob = job; // consomme par onClientSocketConnected() une fois la connexion etablie
    m_sendStates.insert(socket, state);

    connect(socket, &QSslSocket::encrypted, this, &TransferService::onClientSocketConnected);
    connect(socket, &QTcpSocket::readyRead, this, &TransferService::onClientSocketReadyRead);
    connect(socket, &QTcpSocket::bytesWritten, this, &TransferService::onClientSocketBytesWritten);
    connect(socket, &QTcpSocket::errorOccurred, this, &TransferService::onClientSocketErrorOccurred);

    if (!configureTls(socket, m_securityService, false)) {
        finishSend(socket, false, QStringLiteral("Identité TLS indisponible"));
        return;
    }
    socket->connectToHostEncrypted(dest.host.toString(), dest.port);
}

bool TransferService::startSendOnSocket(QTcpSocket *socket, const PendingSendJob &job)
{
    if (!m_sendStates.contains(socket)) {
        return false;
    }
    SendState &state = m_sendStates[socket];

    // Genere une NOUVELLE cle a chaque fichier (y compris sur une
    // connexion reutilisee) : du point de vue des consommateurs des
    // signaux (TransferManager, NotificationManager...), chaque fichier
    // reste un transfert logique distinct, independamment du socket TCP
    // qui le vehicule.
    state.transferKey = makeTransferKey(socket);
    state.filePath = job.filePath;
    state.senderUuid = job.senderUuid;
    state.recipientUuid = job.recipientUuid;
    state.bytesSent = 0;
    state.resumeOffsetReceived = false;
    state.waitingForAck = false;
    state.buffer.clear();
    state.pendingFrameSize = -1;

    auto *file = new QFile(job.filePath);
    if (!file->open(QIODevice::ReadOnly)) {
        qWarning() << "TransferService: cannot open file for sending:" << job.filePath;
        delete file;
        emit transferFailed(state.transferKey, QStringLiteral("Impossible d'ouvrir le fichier"));
        return false;
    }
    state.file = file;
    state.fileSize = file->size();

    const QFileInfo info(job.filePath);
    const QString announcedFileName = job.transferFileName.isEmpty()
        ? info.fileName()
        : QFileInfo(job.transferFileName).fileName();
    // peerMachineId (dernier argument) : vide cote envoi - on connait deja
    // l'identite du destinataire directement via le pair choisi dans
    // DiscoveryService (TransferContext/TransferManager n'ont pas besoin
    // d'un aller-retour reseau pour la resoudre dans ce sens). Seul le
    // sens reception en a besoin (voir onServerSocketReadyRead()).
    //
    // IMPORTANT : on emet announcedFileName (et non info.fileName()) ici.
    // Pour un transfert folder-sync, announcedFileName est le nom haché
    // unique (job.transferFileName, cf. FolderSyncService::
    // folderTransferFileName()) -- c'est CE nom que FolderSyncService utilise
    // desormais pour batir sa cle de correlation m_pendingOutgoingByKey (voir
    // handleFolderFileRequest()). Avec info.fileName() (nom de fichier local
    // brut), deux fichiers de meme nom dans des sous-dossiers differents
    // (ex. "CV.pdf" present dans plusieurs dossiers partages) collisionnaient
    // sur la meme cle : seul le premier transfert demarre la "consommait",
    // les suivants ne retrouvaient plus leur entree et se retrouvaient traites
    // comme des transferts manuels, avec leur propre notification individuelle
    // au lieu d'etre regroupes -- exactement le spam observe sur les dossiers
    // contenant des sous-dossiers. Pour un envoi manuel (transferFileName
    // vide), announcedFileName == info.fileName() : comportement inchange.
    emit transferStarted(state.transferKey, announcedFileName, state.fileSize, false, 0,
                          state.senderUuid, state.recipientUuid, socket->peerAddress(), QString(),
                          job.isFolderTransfer);

    const quint8 compressionFlags = m_compressionEnabled ? 0x01 : 0x00;
    const QByteArray header = encodeHeader(announcedFileName, state.fileSize, state.senderUuid,
                                            state.recipientUuid, m_localMachineId,
                                            compressionFlags, job.isFolderTransfer);
    socket->write(frameOf(header));
    // La reponse (resumeOffset) arrive de facon asynchrone dans
    // onClientSocketReadyRead ; voir state.resumeOffsetReceived.
    return true;
}

void TransferService::onClientSocketConnected()
{
    auto *socket = qobject_cast<QTcpSocket*>(sender());
    if (!socket || !m_sendStates.contains(socket)) {
        return;
    }

    if (m_permissionManager) {
        auto *sslSocket = qobject_cast<QSslSocket *>(socket);
        const QString fingerprint = sslSocket
            ? SecurityService::certificateFingerprint(sslSocket->peerCertificate()) : QString();
        bool trusted = false;
        QMetaObject::invokeMethod(m_permissionManager, "trustRemoteServerCertificate",
                                  Qt::DirectConnection, Q_RETURN_ARG(bool, trusted),
                                  Q_ARG(QString, fingerprint),
                                  Q_ARG(QString, socket->peerAddress().toString()));
        if (!trusted) {
            finishSend(socket, false, QStringLiteral("Certificat distant non autorisé"));
            return;
        }
        bool authorized = false;
        QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorizedByCertificate",
                                  Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                  Q_ARG(QString, fingerprint));
        if (!authorized) {
            finishSend(socket, false, QStringLiteral("Certificat distant non autorisé"));
            return;
        }
        QMetaObject::invokeMethod(m_permissionManager, "recordMachineSeen",
                                  Qt::DirectConnection, Q_ARG(QString, fingerprint),
                                  Q_ARG(QString, socket->peerAddress().toString()));
    }

    if (m_securityService && m_securityService->isReady()) {
        const QString localFingerprint = m_securityService->identity().fingerprintSha256.toLower().trimmed();
        if (localFingerprint.isEmpty()) {
            finishSend(socket, false, QStringLiteral("Identité locale indisponible"));
            return;
        }
        socket->write(frameOf(kIdentityFramePrefix + localFingerprint.toUtf8()));
    }

    const PendingSendJob job = m_sendStates[socket].pendingJob;
    if (!startSendOnSocket(socket, job)) {
        // Echec synchrone (fichier devenu illisible entre la mise en file
        // et l'etablissement de la connexion) : transferFailed() a deja
        // ete emis par startSendOnSocket(), on referme proprement.
        finishSend(socket, false, QStringLiteral("Fichier introuvable au moment de l'envoi"));
    }
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

    const QString destKey = m_socketDestKey.value(socket);

    // CORRECTIF (pool de connexions -- la reutilisation n'etait jamais
    // effective) : m_activeSendConnections etait incremente dans
    // dispatchSendQueue() mais JAMAIS decremente ici, et cette fonction
    // fermait systematiquement le socket sans jamais consulter
    // m_sendQueues[destKey]. Consequence concrete : au-dela des 3
    // premiers fichiers vers un meme pair, tous les suivants restaient
    // bloques indefiniment dans la file (le compteur restait bloque a
    // kMaxConnectionsPerPeer pour toujours) -- un dossier de plus de 3
    // fichiers ne se synchronisait donc jamais completement.
    //
    // Un fichier termine AVEC SUCCES peut enchainer directement le
    // suivant en attente pour le meme pair sur CETTE MEME connexion deja
    // etablie (c'est le but du pool : eviter un nouveau handshake TCP).
    // Une connexion en ECHEC n'est jamais reutilisee (etat potentiellement
    // corrompu ou connexion morte cote reseau) : on la ferme et on relance
    // dispatchSendQueue() pour que les jobs restants repartent sur une
    // connexion neuve.
    if (success && !destKey.isEmpty()) {
        auto queueIt = m_sendQueues.find(destKey);
        while (queueIt != m_sendQueues.end() && !queueIt->isEmpty()) {
            const PendingSendJob job = queueIt->dequeue();
            m_sendStates.insert(socket, SendState{});
            if (startSendOnSocket(socket, job)) {
                return; // Connexion reutilisee : ne pas fermer le socket.
            }
            // Echec synchrone (fichier devenu illisible entre la mise en
            // file et son tour) : startSendOnSocket() a deja emis
            // transferFailed() pour CE job. La connexion reseau, elle,
            // reste saine -- on retente le job suivant sur ce meme socket
            // plutot que de la fermer pour un probleme purement local.
            m_sendStates.remove(socket);
        }
    }

    // Plus rien a enchainer sur cette connexion : on la ferme et on
    // libere sa place dans le pool pour ce pair.
    if (!destKey.isEmpty()) {
        const int remaining = m_activeSendConnections.value(destKey, 1) - 1;
        if (remaining <= 0) {
            m_activeSendConnections.remove(destKey);
        } else {
            m_activeSendConnections[destKey] = remaining;
        }
        m_socketDestKey.remove(socket);
    }

    socket->disconnect(this);
    socket->flush();
    socket->close();
    socket->deleteLater();

    // Des fichiers ont pu rester en file pour ce pair (pool plein au
    // moment ou ils ont ete mis en attente, ou connexion qui vient
    // d'echouer alors qu'il en restait) : une place vient de se liberer,
    // tente d'ouvrir une nouvelle connexion pour les reprendre.
    if (!destKey.isEmpty()) {
        dispatchSendQueue(destKey);
    }
}

// ---------------------------------------------------------------------
// Cote destinataire
// ---------------------------------------------------------------------

void TransferService::onNewConnection()
{
    while (m_server->hasPendingConnections()) {
        auto *socket = qobject_cast<QSslSocket *>(m_server->nextPendingConnection());
        if (!socket) {
            continue;
        }

        socket->setParent(this);
        if (!configureTls(socket, m_securityService, true)) {
            socket->disconnectFromHost();
            socket->deleteLater();
            continue;
        }

        ReceiveState state;
        state.transferKey = makeTransferKey(socket);
        m_receiveStates.insert(socket, state);

        connect(socket, &QTcpSocket::readyRead, this, &TransferService::onServerSocketReadyRead);
        connect(socket, &QTcpSocket::disconnected, this, &TransferService::onServerSocketDisconnected);
        socket->startServerEncryption();
    }
}

void TransferService::setSecurityService(SecurityService *service)
{
    m_securityService = service;
}

void TransferService::setPermissionManager(QObject *manager)
{
    m_permissionManager = manager;
}

void TransferService::onServerSocketReadyRead()
{
    auto *socket = qobject_cast<QTcpSocket*>(sender());
    if (!socket || !m_receiveStates.contains(socket)) {
        return;
    }

    const auto *sslSocket = qobject_cast<QSslSocket *>(socket);
    if (sslSocket && !sslSocket->isEncrypted()) {
        return;
    }

    ReceiveState &state = m_receiveStates[socket];

    // Une révocation doit aussi interrompre une connexion déjà ouverte.
    if (m_permissionManager) {
        const QString fingerprint = sslSocket
            ? SecurityService::certificateFingerprint(sslSocket->peerCertificate()) : QString();
        if (!fingerprint.isEmpty()) {
            bool authorized = false;
            QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorizedByCertificate",
                                      Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                      Q_ARG(QString, fingerprint));
            if (!authorized) {
                qWarning() << "TransferService: active transfer interrupted for unauthorized machine"
                           << socket->peerAddress() << fingerprint;
                socket->disconnectFromHost();
                return;
            }
            state.identityVerified = true;
            state.peerCertificateFingerprint = fingerprint;
        }
    }

    state.connectionIdle = false; // des octets arrivent : soit la suite d'un fichier en cours, soit l'en-tete du suivant sur une connexion reutilisee.
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

        if (payload.startsWith(kIdentityFramePrefix)) {
            const QString announcedFingerprint = QString::fromUtf8(
                payload.mid(kIdentityFramePrefix.size())).toLower().trimmed();
            bool authorized = !m_permissionManager;
            if (m_permissionManager && !announcedFingerprint.isEmpty()) {
                QMetaObject::invokeMethod(m_permissionManager, "isMachineAuthorizedByCertificate",
                                          Qt::DirectConnection, Q_RETURN_ARG(bool, authorized),
                                          Q_ARG(QString, announcedFingerprint));
            }
            if (!authorized) {
                qWarning() << "TransferService: transfer refused for unauthorized certificate"
                           << announcedFingerprint << socket->peerAddress();
                if (m_permissionManager && !announcedFingerprint.isEmpty()) {
                    QMetaObject::invokeMethod(m_permissionManager, "registerPendingMachineByCertificate",
                                              Qt::DirectConnection,
                                              Q_ARG(QString, announcedFingerprint),
                                              Q_ARG(QString, socket->peerAddress().toString()),
                                              Q_ARG(QString, QString()));
                }
                finishReceive(socket, false, QStringLiteral("Certificat distant non autorisé"));
                return;
            }
            state.identityVerified = true;
            state.peerCertificateFingerprint = announcedFingerprint;
            if (m_permissionManager) {
                QMetaObject::invokeMethod(m_permissionManager, "recordMachineSeen",
                                          Qt::DirectConnection,
                                          Q_ARG(QString, announcedFingerprint),
                                          Q_ARG(QString, socket->peerAddress().toString()));
            }
            continue;
        }

        if (!state.identityVerified) {
            if (!m_permissionManager) {
                state.identityVerified = true;
            } else {
                qWarning() << "TransferService: transfer refused, missing identity frame from"
                           << socket->peerAddress();
                finishReceive(socket, false, QStringLiteral("Identité de transfert absente"));
                return;
            }
        }

        if (!state.headerParsed) {
            QString fileName;
            qint64 fileSize = 0;
            QString senderUuid;
            QString recipientUuid;
            QString senderMachineId;
            quint8 compressionFlags = 0;
            bool isFolderTransfer = false;
            if (!decodeHeader(payload, &fileName, &fileSize, &senderUuid, &recipientUuid, &senderMachineId, &compressionFlags, &isFolderTransfer)
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
            state.isFolderTransfer = isFolderTransfer;
            state.compressionEnabled = (compressionFlags & 0x01) != 0;
            state.headerParsed = true;
            // CORRECTIF (pool de connexions -- cote reception) : une
            // connexion reutilisee vehicule plusieurs fichiers a la suite ;
            // chaque fichier doit avoir sa propre transferKey (regeneree
            // ici, comme le fait deja l'expediteur dans startSendOnSocket())
            // pour que TransferManager/FolderSyncService les correlent
            // individuellement au lieu de les confondre sous la cle unique
            // attribuee a la connexion lors de onNewConnection().
            state.transferKey = makeTransferKey(socket);

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
                                  state.senderMachineId, state.isFolderTransfer);
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
        // CORRECTIF (pool de connexions -- cote reception) : sur une
        // connexion reutilisee, entre deux fichiers, headerParsed est
        // remis a false (voir finishReceive()) alors qu'aucun transfert
        // n'est reellement en cours -- sans connectionIdle, cet etat
        // "propre" etait a tort signale comme une interruption
        // (transferFailed emis pour un transfert qui n'existait pas).
        const bool incomplete = !state.connectionIdle
            && (!state.headerParsed || state.bytesReceived < state.fileSize);
        if (incomplete) {
            finishReceive(socket, false, QStringLiteral("Connexion interrompue"));
            return;
        }
    }

    m_receiveStates.remove(socket);
    socket->deleteLater();
}

void TransferService::finishReceive(QTcpSocket *socket, bool success, const QString &errorString)
{
    if (!m_receiveStates.contains(socket)) {
        socket->deleteLater();
        return;
    }

    if (success) {
        // CORRECTIF (pool de connexions -- cote reception, la moitie qui
        // manquait) : cote emission, un fichier termine avec succes peut
        // enchainer le suivant sur la MEME connexion (voir finishSend()).
        // Mais cette fonction refermait jusqu'ici systematiquement le
        // socket a la fin de CHAQUE fichier -- l'expediteur se retrouvait
        // alors a ecrire l'en-tete du fichier suivant sur une connexion
        // deja fermee cote destinataire, ce qui annulait tout le gain du
        // pool (et provoquait un echec reseau evitable). On ne ferme donc
        // plus la connexion ici : on finalise le fichier courant et on
        // reinitialise seulement les champs propres a CE fichier, en
        // gardant le socket et son entree dans m_receiveStates pour
        // recevoir eventuellement un autre en-tete a la suite. Le buffer
        // n'est PAS vide : il peut deja contenir le debut de l'en-tete
        // suivant (arrive dans la meme trame TCP) ; onServerSocketReadyRead()
        // le traitera naturellement des le prochain tour de sa boucle.
        ReceiveState &state = m_receiveStates[socket];

        if (state.file) {
            state.file->close();
            delete state.file;
            state.file = nullptr;
        }

        // Transfert termine : promouvoir le fichier temporaire "<nom>.part"
        // vers son nom final.
        if (!state.partialPath.isEmpty() && state.partialPath != state.destinationPath) {
            QFile::remove(state.destinationPath); // Ecrase un fichier final precedent le cas echeant.
            QFile::rename(state.partialPath, state.destinationPath);
        }
        emit transferCompleted(state.transferKey, state.destinationPath);

        state.headerParsed = false;
        state.headerAcked = false;
        state.fileName.clear();
        state.fileSize = 0;
        state.bytesReceived = 0;
        state.senderUuid.clear();
        state.recipientUuid.clear();
        state.senderMachineId.clear();
        state.compressionEnabled = false;
        state.destinationPath.clear();
        state.partialPath.clear();
        state.pendingBlockSize = -1;
        state.connectionIdle = true;
        // state.buffer et state.transferKey volontairement laisses tels
        // quels : buffer peut contenir le prochain en-tete deja arrive ;
        // transferKey sera regenere a la reception de ce prochain en-tete
        // (voir onServerSocketReadyRead()).
        return;
    }

    // Echec : fermeture definitive de la connexion, comme avant.
    ReceiveState state = m_receiveStates.take(socket);

    if (state.file) {
        state.file->close();
        delete state.file;
    }

    // Ne PAS supprimer le fichier partiel : il permet de reprendre le
    // transfert a partir du dernier bloc confirme (issue #54) lors
    // d'un prochain appel a sendFile() pour le meme fichier.
    emit transferFailed(state.transferKey, errorString);

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
