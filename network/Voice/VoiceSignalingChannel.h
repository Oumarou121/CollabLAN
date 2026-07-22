#ifndef NETWORK_VOICESIGNALINGCHANNEL_H
#define NETWORK_VOICESIGNALINGCHANNEL_H

#include <QObject>
#include <QHostAddress>
#include <QString>
#include <QSslError>

class QWebSocket;
class QWebSocketServer;

namespace network {

class SecurityService;

/// Types de messages de signalisation echanges entre deux postes pour
/// etablir un appel WebRTC (issue #60).
enum class SignalingMessageType {
    Offer,
    Answer,
    IceCandidate,
    Hangup,
    Unknown
};

/// Contenu d'un message de signalisation parse.
struct SignalingMessage {
    SignalingMessageType type = SignalingMessageType::Unknown;
    QString sdp;            ///< Rempli pour Offer/Answer.
    QString candidate;      ///< Rempli pour IceCandidate (ligne "a=candidate:...").
    QString mid;            ///< Media stream identification, pour IceCandidate.
    QString callId;         ///< Identifiant de session d'appel.
    QString certificateFingerprint; ///< Empreinte SHA-256 annoncee par le pair.
};

/**
 * @brief Transport de signalisation WebRTC (offre/reponse SDP, candidats ICE)
 * entre deux postes du LAN, via WebSocket chiffre (meme mecanisme TLS que
 * MessagingService/MessagingServer, cf. SecurityService).
 *
 * Ce canal est volontairement independant de MessagingService : la
 * signalisation d'appel a un cycle de vie propre (une session par appel)
 * et ne doit pas interferer avec la messagerie texte.
 *
 * Le meme objet peut jouer les deux roles au cours de la vie de
 * l'application :
 *  - listen(port) : accepte les appels entrants (role serveur).
 *  - connectToPeer(address, port) : initie un appel sortant (role client).
 *
 * Aucun serveur STUN/TURN externe n'est necessaire : les deux postes sont
 * sur le meme reseau local, les candidats ICE echanges sont donc des
 * candidats "host" locaux (issue #60, critere LAN uniquement).
 */
class VoiceSignalingChannel : public QObject
{
    Q_OBJECT

public:
    explicit VoiceSignalingChannel(SecurityService *securityService, QObject *parent = nullptr);
    ~VoiceSignalingChannel() override;

    /// Demarre l'ecoute des appels entrants sur le port specifie.
    bool listen(quint16 port);
    void stopListening();
    bool isListening() const;
    quint16 listenPort() const;

    /// Initie une connexion de signalisation sortante vers un poste distant
    /// (a appeler avant d'envoyer une offre).
    bool connectToPeer(const QHostAddress &address, quint16 port);
    void setPermissionManager(QObject *manager);
    void disconnectFromPeer();
    bool isConnected() const;

    /// Envoie les differents types de messages de signalisation au poste
    /// actuellement connecte (sortant) ou au dernier client accepte (entrant).
    bool sendOffer(const QString &sdp, const QString &callId);
    bool sendAnswer(const QString &sdp, const QString &callId);
    bool sendIceCandidate(const QString &candidate, const QString &mid, const QString &callId);
    bool sendHangup(const QString &callId);

signals:
    /// Emis a la reception d'un message de signalisation, quel que soit
    /// le role (client sortant ou serveur entrant).
    void messageReceived(const network::SignalingMessage &message, const QHostAddress &peerAddress);

    /// Emis lorsqu'un poste distant se connecte au canal de signalisation
    /// (appel entrant potentiel).
    void peerConnected(const QHostAddress &peerAddress);
    void peerDisconnected();
    void error(const QString &errorString);

private slots:
    void onServerNewConnection();
    void onClientConnected();
    void onClientDisconnected();
    void onTextMessageReceived(const QString &message);
    void onSslErrors(const QList<QSslError> &errors);

private:
    void configureClientSsl();
    bool sendJson(const QString &type, const QString &sdp, const QString &candidate,
                  const QString &mid, const QString &callId);
    static SignalingMessage parseMessage(const QString &json);

    SecurityService *m_securityService = nullptr;
    QObject *m_permissionManager = nullptr;

    // Role client (appel sortant).
    QWebSocket *m_outgoingSocket = nullptr;
    bool m_outgoingConnected = false;

    // Role serveur (appels entrants).
    QWebSocketServer *m_server = nullptr;
    QWebSocket *m_incomingSocket = nullptr; ///< Un seul appel entrant a la fois.
};

} // namespace network

#endif // NETWORK_VOICESIGNALINGCHANNEL_H
