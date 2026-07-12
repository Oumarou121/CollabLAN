#ifndef NETWORK_TLSHANDSHAKESERVICE_H
#define NETWORK_TLSHANDSHAKESERVICE_H

#include <QObject>
#include <QSslCertificate>
#include <QSslKey>
#include <QHostAddress>
#include <QList>

QT_BEGIN_NAMESPACE
class QSslSocket;
class QSslError;
QT_END_NAMESPACE

namespace network {

class SecurityService;
class TrustedPeerStore;

/**
 * @brief Etablit et verifie des sessions TLS entre postes du reseau local.
 *
 * Principe (voir issue #12) :
 *  - Le certificat/cle locaux fournis par SecurityService (issue #11) sont
 *    utilises pour l'authentification TLS, cote serveur (listen()) comme
 *    cote client (connectToPeer()).
 *  - Une fois la poignee de main TLS terminee (socket "encrypted"), le
 *    certificat presente par le poste distant est verifie : son empreinte
 *    SHA-256 doit figurer dans la liste des machines autorisees
 *    (TrustedPeerStore). Aucun contenu applicatif ne doit etre echange
 *    avant cette verification.
 *  - Si le poste distant est autorise, handshakeSucceeded() est emis avec
 *    le socket TLS pret a l'emploi.
 *  - Si le poste distant n'est pas autorise (ou en cas d'erreur), la
 *    connexion est immediatement fermee, l'evenement est journalise et
 *    handshakeRejected() est emis.
 *
 * Les certificats generes par SecurityService etant auto-signes, la
 * verification de chaine de confiance X.509 standard n'est pas utilisee ;
 * c'est l'appartenance a la liste blanche (TrustedPeerStore) qui fait foi.
 */
class TlsHandshakeService : public QObject
{
    Q_OBJECT

public:
    /// securityService doit rester valide pendant toute la duree de vie de ce service
    /// (son identite locale -- cle privee + certificat -- est utilisee pour le TLS).
    explicit TlsHandshakeService(SecurityService *securityService, QObject *parent = nullptr);
    ~TlsHandshakeService() override;

    /// Demarre l'ecoute TLS entrante sur le port donne (45455 par defaut).
    bool listen(quint16 port = 45455);
    void stopListening();
    bool isListening() const;
    quint16 listenPort() const;

    /// Initie une connexion TLS sortante vers un poste distant. Le socket retourne
    /// (proprietaire = ce service) emettra handshakeSucceeded()/handshakeRejected()
    /// via ce service une fois la poignee de main terminee.
    QSslSocket *connectToPeer(const QHostAddress &host, quint16 port);

    // --- Gestion des machines autorisees -----------------------------------
    void trustPeer(const QString &fingerprintSha256, const QString &label = QString());
    void revokePeer(const QString &fingerprintSha256);
    bool isPeerTrusted(const QString &fingerprintSha256) const;
    QStringList trustedFingerprints() const;

    /// Empreinte SHA-256 (hex, minuscule) d'un certificat X.509, meme format
    /// que LocalIdentity::fingerprintSha256 (SecurityService).
    static QString certificateFingerprintSha256(const QSslCertificate &certificate);

signals:
    void listening(quint16 port);
    void listenFailed(const QString &reason);

    /// Emis lorsqu'une session TLS valide est etablie avec un poste autorise.
    /// incoming = true si la connexion a ete initiee par le poste distant.
    void handshakeSucceeded(QSslSocket *socket, const QString &peerFingerprint, bool incoming);

    /// Emis lorsque la session TLS est refusee (poste non autorise ou erreur).
    void handshakeRejected(const QString &peerAddress, const QString &reason);

private:
    class TlsServer;

    void configureSocket(QSslSocket *socket) const;
    void wireSocket(QSslSocket *socket, bool incoming);
    void onIncomingSocketDescriptor(qintptr socketDescriptor);
    void onEncrypted(QSslSocket *socket, bool incoming);
    void onSslErrors(QSslSocket *socket, const QList<QSslError> &errors);

    SecurityService *m_security = nullptr;
    TrustedPeerStore *m_trustedPeers = nullptr;

    QSslCertificate m_localCertificate;
    QSslKey m_localKey;

    TlsServer *m_server = nullptr;
    quint16 m_listenPort = 0;
};

} // namespace network

#endif // NETWORK_TLSHANDSHAKESERVICE_H
