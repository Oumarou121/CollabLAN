#ifndef NETWORK_MESSAGINGSERVICE_H
#define NETWORK_MESSAGINGSERVICE_H

#include <QObject>
#include <QString>
#include <QHostAddress>
#include <QSslError>

class QWebSocket;

namespace network {

class SecurityService;

/**
 * @brief Transport des messages en temps reel via WebSocket chiffré.
 *
 * Gere la connexion WebSocket sécurisée (TLS) entre deux postes pour l'echange de messages.
 * Utilise SecurityService pour fournir les certificats/chés privés TLS.
 * Emet des signaux lors de la reception de messages pour que MessagingManager
 * puisse les diffuser aux abonnes (UI, base de donnees...).
 */
class MessagingService : public QObject
{
    Q_OBJECT

public:
    explicit MessagingService(SecurityService *securityService, QObject *parent = nullptr);
    ~MessagingService() override;

    /// Connecte au poste distant specifie. Retourne true si la connexion reussit.
    bool connectToHost(const QHostAddress &address, quint16 port);

    /// Deconnecte du poste distant.
    void disconnectFromHost();

    /// Envoie un message texte au poste distant.
    bool sendMessage(const QString &message);

    /// Etat de la connexion.
    bool isConnected() const;
    /// Connexion en cours d'etablissement (TCP/TLS pas encore abouti).
    bool isConnecting() const;

    /// Adresse du poste distant (valide si isConnected() == true).
    QHostAddress peerAddress() const;
    quint16 peerPort() const;
    /// Empreinte du certificat du serveur connecte (vide si non connecte).
    QString peerFingerprint() const { return m_connected ? m_peerFingerprint : QString(); }

    /// Définit le PermissionManager pour vérifier les machines autorisées (issue #68).
    void setPermissionManager(QObject *manager);

    /// Rejoue la derniere tentative de connexion. Utilise apres validation
    /// locale du certificat depuis l'ecran pre-login.
    bool retryLastHost();

signals:
    /// Emis lors de la connexion reussie.
    void connected();

    /// Emis lors de la deconnexion.
    void disconnected();

    /// Emis lors de la reception d'un message texte.
    void messageReceived(const QString &message);

    /// Emis en cas d'erreur de connexion.
    void error(const QString &errorString);

    /// Le handshake TLS a fourni un certificat, mais ce poste ne l'a pas
    /// encore approuve localement. Aucune donnee metier n'a ete echangee.
    void serverCertificateTrustRequired(const QString &fingerprint,
                                        const QString &address,
                                        quint16 port);

private slots:
    void onConnected();
    void onDisconnected();
    void onTextMessageReceived(const QString &message);
    void onError();
    void onSslErrors(const QList<QSslError> &errors);

private:
    void configureSsl();

    QWebSocket *m_socket = nullptr;
    SecurityService *m_securityService = nullptr;
    QObject *m_permissionManager = nullptr;
    bool m_connected = false;
    QHostAddress m_lastRequestedAddress;
    quint16 m_lastRequestedPort = 0;
    QString m_peerFingerprint;
};

} // namespace network

#endif // NETWORK_MESSAGINGSERVICE_H
