#ifndef NETWORK_MESSAGINGSERVER_H
#define NETWORK_MESSAGINGSERVER_H

#include <QObject>
#include <QString>
#include <QHostAddress>

class QWebSocketServer;
class QWebSocket;

namespace network {

class SecurityService;

/**
 * @brief Serveur WebSocket pour recevoir les messages entrants.
 *
 * Écoute sur un port spécifique et accepte les connexions WebSocket sécurisées (TLS).
 * Émet des signaux lors de la réception de messages pour que MessagingManager
 * puisse les traiter.
 */
class MessagingServer : public QObject
{
    Q_OBJECT

public:
    explicit MessagingServer(SecurityService *securityService, QObject *parent = nullptr);
    ~MessagingServer() override;

    /// Démarre le serveur sur le port spécifié.
    bool start(quint16 port = 12345);

    /// Arrête le serveur.
    void stop();

    /// État du serveur.
    bool isRunning() const;

    /// Envoie un message texte a tous les clients actuellement connectes
    /// (utilise pour la diffusion des messages de groupe : chaque membre
    /// connecte a ce poste recoit le message). Retourne le nombre de
    /// clients auxquels le message a effectivement ete envoye.
    int broadcastMessage(const QString &message);

    /// Port d'écoute.
    quint16 port() const;

signals:
    /// Émis lorsqu'un message texte est reçu d'un client.
    void messageReceived(const QString &message, const QHostAddress &senderAddress);

    /// Émis lorsqu'un client se connecte.
    void clientConnected(const QHostAddress &clientAddress);

    /// Émis lorsqu'un client se déconnecte.
    void clientDisconnected(const QHostAddress &clientAddress);

    /// Émis en cas d'erreur.
    void error(const QString &errorString);

private slots:
    void onNewConnection();
    void onTextMessageReceived(const QString &message);
    void onSocketDisconnected();

private:
    QWebSocketServer *m_server = nullptr;
    SecurityService *m_securityService = nullptr;
    QList<QWebSocket*> m_clients;
};

} // namespace network

#endif // NETWORK_MESSAGINGSERVER_H
