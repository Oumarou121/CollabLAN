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

    /// Adresse du poste distant (valide si isConnected() == true).
    QHostAddress peerAddress() const;
    quint16 peerPort() const;

signals:
    /// Emis lors de la connexion reussie.
    void connected();

    /// Emis lors de la deconnexion.
    void disconnected();

    /// Emis lors de la reception d'un message texte.
    void messageReceived(const QString &message);

    /// Emis en cas d'erreur de connexion.
    void error(const QString &errorString);

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
    bool m_connected = false;
};

} // namespace network

#endif // NETWORK_MESSAGINGSERVICE_H
