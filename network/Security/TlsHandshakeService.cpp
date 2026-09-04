#include "TlsHandshakeService.h"
#include "TrustedPeerStore.h"
#include "SecurityService.h"

#include <QSslSocket>
#include <QSslError>
#include <QTcpServer>
#include <QCryptographicHash>
#include <QLoggingCategory>
#include <QFile>
#include <functional>

namespace network {

namespace {
Q_LOGGING_CATEGORY(lcTls, "localink.network.tls")
} // namespace

// ---------------------------------------------------------------------------
// TlsServer : QTcpServer qui delegue chaque connexion TCP entrante a un
// gestionnaire fourni par TlsHandshakeService, sans effectuer elle-meme la
// poignee de main TLS (elle est demarree explicitement via
// QSslSocket::startServerEncryption() une fois le descripteur recupere).
// ---------------------------------------------------------------------------
class TlsHandshakeService::TlsServer : public QTcpServer
{
public:
    explicit TlsServer(std::function<void(qintptr)> handler, QObject *parent = nullptr)
        : QTcpServer(parent)
        , m_handler(std::move(handler))
    {
    }

protected:
    void incomingConnection(qintptr socketDescriptor) override
    {
        if (m_handler)
            m_handler(socketDescriptor);
    }

private:
    std::function<void(qintptr)> m_handler;
};

TlsHandshakeService::TlsHandshakeService(SecurityService *securityService, QObject *parent)
    : QObject(parent)
    , m_security(securityService)
{
    Q_ASSERT(m_security);

    m_trustedPeers = new TrustedPeerStore(m_security->storageDir());
    m_trustedPeers->load();

    // Charge l'identite locale (cle privee + certificat) generee/geree par
    // SecurityService (issue #11) pour l'utiliser dans les sessions TLS.
    const QList<QSslCertificate> certs = QSslCertificate::fromPath(m_security->certificatePath());
    if (!certs.isEmpty())
        m_localCertificate = certs.first();

    QFile keyFile(m_security->privateKeyPath());
    if (keyFile.open(QIODevice::ReadOnly)) {
        m_localKey = QSslKey(keyFile.readAll(), QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
        keyFile.close();
    }

    if (m_localCertificate.isNull() || m_localKey.isNull()) {
        qCWarning(lcTls) << "TlsHandshakeService: identite locale (cle/certificat) indisponible ou invalide -"
                          << "verifier que SecurityService::initialize() a bien ete appele avant.";
    }
}

TlsHandshakeService::~TlsHandshakeService()
{
    stopListening();
    delete m_trustedPeers;
}

bool TlsHandshakeService::listen(quint16 port)
{
    if (m_server && m_server->isListening())
        return true;

    if (!m_server) {
        m_server = new TlsServer([this](qintptr descriptor) { onIncomingSocketDescriptor(descriptor); }, this);
    }

    if (!m_server->listen(QHostAddress::Any, port)) {
        const QString reason = m_server->errorString();
        qCWarning(lcTls) << "TlsHandshakeService: echec de l'ecoute sur le port" << port << ":" << reason;
        emit listenFailed(reason);
        return false;
    }

    m_listenPort = m_server->serverPort();
    qCInfo(lcTls) << "TlsHandshakeService: ecoute TLS demarree sur le port" << m_listenPort;
    emit listening(m_listenPort);
    return true;
}

void TlsHandshakeService::stopListening()
{
    if (m_server) {
        m_server->close();
        m_server->deleteLater();
        m_server = nullptr;
    }
    m_listenPort = 0;
}

bool TlsHandshakeService::isListening() const
{
    return m_server && m_server->isListening();
}

quint16 TlsHandshakeService::listenPort() const
{
    return m_listenPort;
}

QSslSocket *TlsHandshakeService::connectToPeer(const QHostAddress &host, quint16 port)
{
    auto *socket = new QSslSocket(this);
    configureSocket(socket);
    wireSocket(socket, /*incoming=*/false);

    qCInfo(lcTls) << "TlsHandshakeService: initiation de la poignee de main TLS vers"
                  << host.toString() << ":" << port;
    socket->connectToHostEncrypted(host.toString(), port);
    return socket;
}

void TlsHandshakeService::onIncomingSocketDescriptor(qintptr socketDescriptor)
{
    auto *socket = new QSslSocket(this);
    if (!socket->setSocketDescriptor(socketDescriptor)) {
        qCWarning(lcTls) << "TlsHandshakeService: impossible d'attacher le socket entrant:"
                          << socket->errorString();
        socket->deleteLater();
        return;
    }

    configureSocket(socket);
    wireSocket(socket, /*incoming=*/true);

    qCInfo(lcTls) << "TlsHandshakeService: connexion entrante de" << socket->peerAddress().toString()
                  << "- demarrage de la poignee de main TLS (serveur)";
    socket->startServerEncryption();
}

void TlsHandshakeService::configureSocket(QSslSocket *socket) const
{
    socket->setLocalCertificate(m_localCertificate);
    socket->setPrivateKey(m_localKey);

    // Les certificats sont auto-signes (voir SecurityService) : la chaine de
    // confiance X.509 standard ne peut donc pas etre validee par les CA
    // habituelles. On demande tout de meme le certificat du poste distant
    // (QueryPeer) afin de pouvoir effectuer nous-memes la verification
    // d'autorisation (empreinte SHA-256 vs TrustedPeerStore) une fois la
    // poignee de main terminee, sans jamais faire confiance implicitement.
    socket->setPeerVerifyMode(QSslSocket::QueryPeer);
}

void TlsHandshakeService::wireSocket(QSslSocket *socket, bool incoming)
{
    connect(socket, &QSslSocket::encrypted, this, [this, socket, incoming] {
        onEncrypted(socket, incoming);
    });

    connect(socket, &QSslSocket::sslErrors, this, [this, socket](const QList<QSslError> &errors) {
        onSslErrors(socket, errors);
    });

    connect(socket, &QAbstractSocket::errorOccurred, this,
            [this, socket, incoming](QAbstractSocket::SocketError) {
        Q_UNUSED(incoming);
        qCWarning(lcTls) << "TlsHandshakeService: erreur socket avec"
                          << socket->peerAddress().toString() << ":" << socket->errorString();
    });

    connect(socket, &QAbstractSocket::disconnected, socket, &QObject::deleteLater);
}

void TlsHandshakeService::onSslErrors(QSslSocket *socket, const QList<QSslError> &errors)
{
    // Attendu avec des certificats auto-signes (SelfSignedCertificate,
    // HostNameMismatch...) : on ne rejette pas ici, la decision d'autorisation
    // finale est prise dans onEncrypted() via TrustedPeerStore. On ignore donc
    // ces erreurs pour laisser la poignee de main TLS se terminer.
    for (const QSslError &error : errors)
        qCDebug(lcTls) << "TlsHandshakeService: erreur TLS (ignoree, verification manuelle a suivre):"
                       << error.errorString();

    socket->ignoreSslErrors();
}

void TlsHandshakeService::onEncrypted(QSslSocket *socket, bool incoming)
{
    const QString peerAddress = QStringLiteral("%1:%2")
                                     .arg(socket->peerAddress().toString())
                                     .arg(socket->peerPort());

    const QSslCertificate peerCert = socket->peerCertificate();
    const QString fingerprint = certificateFingerprintSha256(peerCert);

    if (peerCert.isNull() || fingerprint.isEmpty()) {
        qCWarning(lcTls) << "TlsHandshakeService: aucun certificat presente par" << peerAddress
                          << "- session rejetee";
        emit handshakeRejected(peerAddress, QStringLiteral("aucun certificat presente"));
        QMetaObject::invokeMethod(socket, &QAbstractSocket::abort, Qt::QueuedConnection);
        return;
    }

    if (!m_trustedPeers->isTrusted(fingerprint)) {
        qCWarning(lcTls) << "TlsHandshakeService: machine NON autorisee rejetee -" << peerAddress
                          << "fingerprint=" << fingerprint;
        emit handshakeRejected(peerAddress,
                                QStringLiteral("certificat non autorise (fingerprint %1)").arg(fingerprint));
        // Abort differe (connexion en file) : eviter de detruire/reinitialiser
        // le socket de maniere synchrone alors qu'on est encore dans son
        // propre gestionnaire du signal encrypted() (reentrance risquee,
        // en particulier avec le backend Schannel sur Windows).
        QMetaObject::invokeMethod(socket, &QAbstractSocket::abort, Qt::QueuedConnection);
        return;
    }

    qCInfo(lcTls) << "TlsHandshakeService: session TLS etablie avec une machine autorisee -"
                  << peerAddress << "fingerprint=" << fingerprint;
    emit handshakeSucceeded(socket, fingerprint, incoming);
}

void TlsHandshakeService::trustPeer(const QString &fingerprintSha256, const QString &label)
{
    m_trustedPeers->trust(fingerprintSha256, label);
}

void TlsHandshakeService::revokePeer(const QString &fingerprintSha256)
{
    m_trustedPeers->revoke(fingerprintSha256);
}

bool TlsHandshakeService::isPeerTrusted(const QString &fingerprintSha256) const
{
    return m_trustedPeers->isTrusted(fingerprintSha256);
}

QStringList TlsHandshakeService::trustedFingerprints() const
{
    return m_trustedPeers->fingerprints();
}

QString TlsHandshakeService::certificateFingerprintSha256(const QSslCertificate &certificate)
{
    if (certificate.isNull())
        return QString();

    return QString::fromLatin1(certificate.digest(QCryptographicHash::Sha256).toHex());
}

} // namespace network
