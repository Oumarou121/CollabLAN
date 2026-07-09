#ifndef NETWORK_DISCOVERYSERVICE_H
#define NETWORK_DISCOVERYSERVICE_H

#include <QObject>
#include <QHostAddress>
#include <QString>
#include <QHash>
#include <QList>
#include <QMetaType>

class QUdpSocket;
class QTimer;

namespace network {

/**
 * @brief Informations sur un poste decouvert sur le reseau local.
 */
struct DiscoveredPeer {
    QString id;             ///< Identifiant unique du poste (genere au demarrage de DiscoveryService)
    QString name;           ///< Nom lisible du poste (hostname par defaut)
    QString status;         ///< Statut declare ("online", "away", "busy"...)
    QHostAddress address;   ///< Adresse IP source de la derniere annonce recue
    quint16 port = 0;       ///< Port UDP utilise par le poste distant
    qint64 lastSeenMs = 0;  ///< QDateTime::currentMSecsSinceEpoch() de la derniere annonce recue
};

/**
 * @brief Decouverte automatique des machines du reseau local via UDP broadcast.
 *
 * Principe :
 *  - Chaque instance diffuse (broadcast UDP) un paquet d'annonce JSON toutes
 *    les announceIntervalMs() millisecondes, contenant son identifiant, son
 *    nom et son statut.
 *  - Chaque instance ecoute en parallele sur le meme port UDP les annonces
 *    des autres postes et met a jour sa liste de postes detectes (peers())
 *    en consequence.
 *  - Un poste qui n'a plus donne signe de vie depuis peerTimeoutMs() est
 *    considere comme perdu (signal peerLost, avec ses dernieres infos connues).
 *
 * Avec les valeurs par defaut (annonce toutes les 2s), deux instances sur le
 * meme reseau se detectent en quelques secondes, conformement au critere
 * d'acceptation de l'issue #9.
 */
class DiscoveryService : public QObject
{
    Q_OBJECT

public:
    explicit DiscoveryService(QObject *parent = nullptr);
    ~DiscoveryService() override;

    /// Demarre l'ecoute + l'annonce periodique. Ne fait rien si deja demarre.
    bool start();

    /// Arrete l'ecoute et l'annonce periodique.
    void stop();

    bool isRunning() const;

    /// Identifiant local unique (genere aleatoirement au premier demarrage).
    QString localId() const;

    /// Nom annonce aux autres postes (hostname de la machine par defaut).
    QString localName() const;
    void setLocalName(const QString &name);

    /// Statut annonce aux autres postes ("online" par defaut).
    QString localStatus() const;
    void setLocalStatus(const QString &status);

    /// Port UDP utilise pour l'annonce/l'ecoute (45454 par defaut).
    quint16 port() const;
    void setPort(quint16 port);

    /// Intervalle entre deux annonces, en ms (2000 par defaut).
    int announceIntervalMs() const;
    void setAnnounceIntervalMs(int ms);

    /// Delai au-dela duquel un poste sans nouvelle annonce est considere perdu (8000 ms par defaut).
    int peerTimeoutMs() const;
    void setPeerTimeoutMs(int ms);

    /// Liste courante des postes detectes (hors soi-meme).
    QList<DiscoveredPeer> peers() const;

signals:
    void started();
    void stopped();

    /// Emis lorsqu'un nouveau poste est detecte pour la premiere fois.
    void peerDiscovered(const network::DiscoveredPeer &peer);

    /// Emis lorsqu'un poste deja connu renvoie des informations mises a jour (IP/nom/statut).
    void peerUpdated(const network::DiscoveredPeer &peer);

    /// Emis lorsqu'un poste n'a plus donne signe de vie depuis peerTimeoutMs().
    /// Transporte les dernieres informations connues du poste perdu (nom, IP,
    /// port, dernier statut...), necessaires pour formuler une notification
    /// de deconnexion exploitable par l'UI (ex. "MachineB est deconnectee").
    void peerLost(const network::DiscoveredPeer &peer);

private slots:
    void sendAnnounce();
    void readPendingDatagrams();
    void checkStalePeers();

private:
    void handleAnnouncePacket(const QByteArray &data, const QHostAddress &senderAddress);

    QUdpSocket *m_socket = nullptr;
    QTimer *m_announceTimer = nullptr;
    QTimer *m_cleanupTimer = nullptr;

    QString m_localId;
    QString m_localName;
    QString m_localStatus = QStringLiteral("online");

    quint16 m_port = 45454;
    int m_announceIntervalMs = 2000;
    int m_peerTimeoutMs = 8000;

    bool m_running = false;

    QHash<QString, DiscoveredPeer> m_peers; // cle = id du poste distant
};

} // namespace network

Q_DECLARE_METATYPE(network::DiscoveredPeer)

#endif // NETWORK_DISCOVERYSERVICE_H
