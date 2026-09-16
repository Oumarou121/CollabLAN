#ifndef NETWORK_MESSAGINGSERVER_H
#define NETWORK_MESSAGINGSERVER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QHostAddress>
#include <QHash>

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
    ///
    /// @param excludeAddress Si non-null, le client dont l'adresse pair
    ///        correspond a excludeAddress ne recoit PAS le message. Utilise
    ///        par les relais de FolderSyncService (ex: folder_resync_request)
    ///        pour eviter de renvoyer l'echo au client qui vient d'emettre
    ///        le message d'origine (cf. debrief "relais resync_request").
    int broadcastMessage(const QString &message,
                          const QHostAddress &excludeAddress = QHostAddress());

    /// Envoie un message texte uniquement aux clients dont l'UUID
    /// utilisateur identifie (cf. handshake "identify" gere en interne)
    /// figure dans @p uuids. Contrairement a broadcastMessage(), les
    /// clients non concernes par la conversation/le groupe ne recoivent
    /// (et ne persistent) jamais le message (issue #2 : diffusion non
    /// ciblee). Retourne le nombre de clients effectivement atteints.
    /// Un client pas encore identifie (aucun message "identify" recu)
    /// ne peut pas etre cible par uuid.
    int sendToUuids(const QString &message, const QStringList &uuids);

    /// Port d'écoute.
    quint16 port() const;

    /// Définit le PermissionManager pour vérifier les machines autorisées (issue #70).
    void setPermissionManager(QObject *manager);

signals:
    /// Émis lorsqu'un message texte est reçu d'un client.
    void messageReceived(const QString &message, const QHostAddress &senderAddress);

    /// Émis lorsqu'un client se connecte.
    void clientConnected(const QHostAddress &clientAddress);

    /// Émis lorsqu'un client se déconnecte.
    void clientDisconnected(const QHostAddress &clientAddress);

    /// Émis en cas d'erreur.
    void error(const QString &errorString);

    /// Émis lorsqu'une connexion est refusée (machine non autorisée, issue #70).
    void connectionRefused(const QHostAddress &clientAddress, const QString &reason);

    /// Émis juste après qu'un client a envoyé son handshake "identify" et a
    /// été associé à un userUuid (cf. onTextMessageReceived). Point
    /// d'accroche pour le rattrapage ciblé (ex: users_catchup_batch,
    /// cf. Application::sendUsersCatchupTo) : contrairement à
    /// clientConnected(), on connaît ici le userUuid pour cibler via
    /// sendToUuids() plutôt que de diffuser à tous.
    void clientIdentified(const QString &userUuid, bool authorized);

private slots:
    void onNewConnection();
    void onTextMessageReceived(const QString &message);
    void onSocketDisconnected();

private:
    QWebSocketServer *m_server = nullptr;
    SecurityService *m_securityService = nullptr;
    QObject *m_permissionManager = nullptr;
    QList<QWebSocket*> m_clients;

    /// UUID utilisateur declare par chaque client via le message
    /// "identify" envoye juste apres connexion (cf. MessagingService /
    /// Application::sendIdentifyIfReady). Alimente sendToUuids() pour
    /// ne relayer un message qu'aux destinataires reels (issue #2).
    QHash<QWebSocket*, QString> m_clientUuids;
    QHash<QWebSocket*, QString> m_clientFingerprints;
    QHash<QWebSocket*, bool> m_clientAuthorized;
};

} // namespace network

#endif // NETWORK_MESSAGINGSERVER_H
