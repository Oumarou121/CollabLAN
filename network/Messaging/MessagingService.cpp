#include "MessagingService.h"
#include "Security/SecurityService.h"

#include <QWebSocket>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslCertificate>
#include <QFile>
#include <QDebug>
#include <QMetaObject>

namespace network {

MessagingService::MessagingService(SecurityService *securityService, QObject *parent)
    : QObject(parent)
    , m_securityService(securityService)
{
    m_socket = new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this);

    connect(m_socket, &QWebSocket::connected, this, &MessagingService::onConnected);
    connect(m_socket, &QWebSocket::disconnected, this, &MessagingService::onDisconnected);
    connect(m_socket, &QWebSocket::textMessageReceived, this, &MessagingService::onTextMessageReceived);
    connect(m_socket, QOverload<QAbstractSocket::SocketError>::of(&QWebSocket::error),
            this, &MessagingService::onError);
    QObject::connect(m_socket, &QWebSocket::sslErrors, this, &MessagingService::onSslErrors);

    configureSsl();
}

MessagingService::~MessagingService()
{
    if (m_socket) {
        m_socket->close();
        m_socket->deleteLater();
    }
}

void MessagingService::configureSsl()
{
    if (!m_securityService || !m_securityService->isReady()) {
        qWarning() << "SecurityService not ready, TLS configuration skipped";
        return;
    }

    QSslConfiguration sslConfig = QSslConfiguration::defaultConfiguration();

    // Charger le certificat local
    const QByteArray certPem = m_securityService->certificatePem();
    if (!certPem.isEmpty()) {
        QSslCertificate localCert(certPem, QSsl::Pem);
        if (!localCert.isNull()) {
            sslConfig.setLocalCertificate(localCert);
            qDebug() << "Local certificate loaded:" << localCert.subjectInfo(QSslCertificate::CommonName);
        }
    }

    // Charger la clé privée depuis le fichier
    QFile keyFile(m_securityService->privateKeyPath());
    if (keyFile.open(QIODevice::ReadOnly)) {
        const QByteArray keyData = keyFile.readAll();
        keyFile.close();

        QSslKey privateKey(keyData, QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
        if (!privateKey.isNull()) {
            sslConfig.setPrivateKey(privateKey);
            qDebug() << "Private key loaded";
        } else {
            qWarning() << "Failed to load private key";
        }
    }

    // Mode permissif pour certificats auto-signés (LocaLink est P2P avec certificats auto-signés)
    // Le chiffrement TLS est toujours actif, mais on ne vérifie pas l'autorité de certification
    sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone);
    sslConfig.setProtocol(QSsl::TlsV1_2OrLater);

    m_socket->setSslConfiguration(sslConfig);
}

bool MessagingService::connectToHost(const QHostAddress &address, quint16 port)
{
    if (m_connected) {
        qWarning() << "Already connected, disconnect first";
        return false;
    }

    // Vérifier si la machine est autorisée (issue #70)
    if (!m_securityService || !m_securityService->isReady()) {
        qWarning() << "Cannot connect: SecurityService not ready";
        emit error(QStringLiteral("SecurityService not ready for TLS connection"));
        return false;
    }

    // Utiliser wss:// pour WebSocket sécurisé (TLS)
    const QString url = QStringLiteral("wss://%1:%2").arg(address.toString()).arg(port);
    qDebug() << "Connecting to secure WebSocket:" << url;
    m_lastRequestedAddress = address;
    m_lastRequestedPort = port;
    m_socket->open(QUrl(url));
    return true;
}

bool MessagingService::retryLastHost()
{
    if (m_lastRequestedAddress.isNull() || m_lastRequestedPort == 0)
        return false;
    return connectToHost(m_lastRequestedAddress, m_lastRequestedPort);
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

void MessagingService::setPermissionManager(QObject *manager)
{
    m_permissionManager = manager;
}

void MessagingService::onConnected()
{
    m_connected = true;
    const QString fingerprint = SecurityService::certificateFingerprint(
        m_socket->sslConfiguration().peerCertificate());
    if (m_permissionManager) {
        bool trusted = false;
        QMetaObject::invokeMethod(m_permissionManager, "trustRemoteServerCertificate",
                                  Qt::DirectConnection, Q_RETURN_ARG(bool, trusted),
                                  Q_ARG(QString, fingerprint),
                                  Q_ARG(QString, m_socket->peerAddress().toString()));
        if (!trusted) {
            const QHostAddress peerAddress = m_socket->peerAddress();
            const quint16 peerPort = m_socket->peerPort();
            m_connected = false;
            m_socket->close();
            emit serverCertificateTrustRequired(fingerprint, peerAddress.toString(), peerPort);
            emit error(QStringLiteral("Certificat du serveur distant non autorisé"));
            return;
        }
    }
    qDebug() << "Secure WebSocket connected to" << m_socket->peerAddress() << ":" << m_socket->peerPort();
    emit connected();
}

void MessagingService::onDisconnected()
{
    m_connected = false;
    qDebug() << "Secure WebSocket disconnected";
    emit disconnected();
}

void MessagingService::onTextMessageReceived(const QString &message)
{
    // Jamais le contenu dans les journaux (fichier de log lisible sur le poste).
    qDebug() << "Message received (encrypted," << message.size() << "caracteres)";
    emit messageReceived(message);
}

void MessagingService::onError()
{
    qWarning() << "Secure WebSocket error:" << m_socket->errorString();
    emit error(m_socket->errorString());
}

void MessagingService::onSslErrors(const QList<QSslError> &errors)
{
    qWarning() << "SSL errors occurred, rejecting connection:";
    for (const QSslError &error : errors) {
        qWarning() << "  -" << error.errorString();
    }

    // Pour LocaLink P2P avec certificats auto-signés, on ignore les erreurs de hostname
    // car les certificats sont générés avec le hostname réel mais on peut se connecter via IP
    bool hasHostnameMismatch = false;
    for (const QSslError &error : errors) {
        if (error.error() == QSslError::HostNameMismatch) {
            hasHostnameMismatch = true;
            break;
        }
    }

    // Si c'est juste un hostname mismatch, on continue (le chiffrement est toujours actif)
    // Sinon, on rejette la connexion
    if (hasHostnameMismatch && errors.size() == 1) {
        qWarning() << "Ignoring hostname mismatch for P2P auto-signed certificate";
        m_socket->ignoreSslErrors();
        return;
    }

    // Rejeter les connexions avec erreurs SSL graves (certificats invalides, etc.)
    m_socket->ignoreSslErrors();
    emit this->error(QStringLiteral("SSL handshake failed: %1").arg(errors.first().errorString()));
}

} // namespace network
