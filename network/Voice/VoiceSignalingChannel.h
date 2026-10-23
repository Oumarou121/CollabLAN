#ifndef NETWORK_VOICESIGNALINGCHANNEL_H
#define NETWORK_VOICESIGNALINGCHANNEL_H

#include <QObject>
#include <QHash>
#include <QHostAddress>
#include <QList>
#include <QString>
#include <QSslError>

class QWebSocket;
class QWebSocketServer;

namespace network {

class SecurityService;

/// Types de messages de signalisation echanges entre deux postes pour
/// etablir un appel WebRTC (issue #60), a deux ou en groupe.
enum class SignalingMessageType {
    Offer,
    Answer,
    IceCandidate,
    Hangup,
    Roster,      ///< Participants deja dans l'appel, a relier (appel de groupe).
    State,       ///< Etat d'un participant (micro coupe).
    Unknown
};

/// Participant d'un appel de groupe, tel qu'annonce par un autre poste.
struct SignalingRosterEntry {
    QString address;
    quint16 port = 0;
};

/// Contenu d'un message de signalisation parse.
struct SignalingMessage {
    SignalingMessageType type = SignalingMessageType::Unknown;
    QString sdp;            ///< Rempli pour Offer/Answer.
    QString candidate;      ///< Rempli pour IceCandidate (ligne "a=candidate:...").
    QString mid;            ///< Media stream identification, pour IceCandidate.
    QString callId;         ///< Identifiant de l'appel (commun a tout le groupe).
    QString reason;         ///< Raison d'un Hangup ("busy", "declined", "left", "full"...).
    QString certificateFingerprint; ///< Empreinte SHA-256 annoncee par le pair.
    quint16 signalingPort = 0;      ///< Port d'ecoute de l'emetteur (Offer) : 0 = ancien poste.
    bool group = false;             ///< Offer : appel de groupe.
    bool mesh = false;              ///< Offer : liaison entre membres d'un appel deja accepte.
    bool muted = false;             ///< State : micro coupe.
    bool presenting = false;        ///< State : partage son ecran.
    qint64 presentingSince = 0;     ///< State : debut de la presentation (ms, UTC).
    quint32 presentToken = 0;       ///< State : departage deux debuts simultanes.
    QString screenTitle;            ///< State : ce qui est presente (« Écran 1 »...).
    QList<SignalingRosterEntry> roster; ///< Offer (deja dans l'appel) et Roster.
};

/**
 * @brief Transport de signalisation WebRTC (offre/reponse SDP, candidats ICE)
 * entre postes du LAN, via WebSocket chiffre (meme mecanisme TLS que
 * MessagingService/MessagingServer, cf. SecurityService).
 *
 * Ce canal est volontairement independant de MessagingService : la
 * signalisation d'appel a un cycle de vie propre et ne doit pas interferer
 * avec la messagerie texte.
 *
 * Un appel de groupe relie chaque participant a chacun des autres : le canal
 * tient donc plusieurs liaisons a la fois, chacune identifiee par un numero
 * (jamais reutilise) :
 *  - connectToPeer(address, port) ouvre une liaison sortante ;
 *  - chaque connexion entrante acceptee par listen(port) en cree une.
 * VoiceService decide seul de l'accueil d'une offre (occupe, meme appel...).
 *
 * Aucun serveur STUN/TURN externe n'est necessaire : les postes sont sur le
 * meme reseau local, les candidats ICE echanges sont des candidats "host".
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

    void setPermissionManager(QObject *manager);

    /// Ouvre une liaison sortante vers un poste distant. Retourne son numero
    /// (> 0), ou 0 si elle ne peut pas etre tentee. peerConnected() suit une
    /// fois la connexion TLS etablie et le poste reconnu.
    int connectToPeer(const QHostAddress &address, quint16 port);

    /// Ferme une liaison (sans effet si elle n'existe plus).
    void closeLink(int linkId);
    void closeAllLinks();
    bool isLinkOpen(int linkId) const;
    int linkCount() const { return static_cast<int>(m_links.size()); }

    bool send(int linkId, const SignalingMessage &message);

signals:
    /// Liaison prete a echanger des messages : sortante connectee et poste
    /// reconnu, ou entrante acceptee (certificat d'une machine autorisee).
    void peerConnected(int linkId, const QHostAddress &peerAddress);
    void peerDisconnected(int linkId);
    void messageReceived(int linkId, const network::SignalingMessage &message,
                         const QHostAddress &peerAddress);
    void error(const QString &errorString);

private slots:
    void onServerNewConnection();

private:
    struct Link {
        QWebSocket *socket = nullptr;
        bool outgoing = false;
        bool ready = false;
    };

    void configureClientSsl(QWebSocket *socket) const;
    void onOutgoingConnected(int linkId);
    void onSocketClosed(int linkId);
    void onTextMessage(int linkId, const QString &message);
    int linkOf(const QWebSocket *socket) const;
    static QString serialize(const SignalingMessage &message, const QString &localFingerprint);
    static SignalingMessage parseMessage(const QString &json);

    SecurityService *m_securityService = nullptr;
    QObject *m_permissionManager = nullptr;
    QWebSocketServer *m_server = nullptr;
    QHash<int, Link> m_links;
    int m_nextLinkId = 1;
};

} // namespace network

#endif // NETWORK_VOICESIGNALINGCHANNEL_H
