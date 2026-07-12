#ifndef NETWORK_SYNCNETWORKSERVICE_H
#define NETWORK_SYNCNETWORKSERVICE_H

#include <QHash>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QString>

QT_BEGIN_NAMESPACE
class QSslSocket;
QT_END_NAMESPACE

namespace network {

class SecurityService;
class TlsHandshakeService;

/**
 * @brief Transport reseau du protocole de synchronisation des dossiers
 * partages (Phases 6 et 7 de "Shared Folder") : etablit les connexions
 * TCP avec les autres postes et echange les messages SyncProtocol.
 *
 * Une connexion par poste distant est maintenue en continu (etablie des
 * que le poste est decouvert via DiscoveryService) : les messages
 * FILE_INFO/DELETE_FILE/RENAME_FILE sont diffuses en temps reel a chaque
 * modification locale (Phase 7), et SYNC_REQUEST/SYNC_RESPONSE
 * permettent a un poste qui revient en ligne de rattraper l'etat complet
 * d'un dossier (Phase 6).
 *
 * Securite : les connexions passent par network::TlsHandshakeService (issue
 * #12), qui chiffre le canal avec l'identite locale fournie par
 * network::SecurityService (issue #11) et n'accepte de session que si le
 * poste distant presente un certificat dont l'empreinte figure dans
 * TrustedPeerStore. Les messages applicatifs (HELLO, FILE_INFO, ...) ne
 * circulent qu'une fois cette poignee de main validee. Ce service possede
 * sa propre instance de TlsHandshakeService (identite partagee via
 * SecurityService, mais liste de confiance persistee sur disque et donc
 * partagee entre instances). trustPeer()/revokePeer() delegue directement
 * a cette instance ; voir ui/Admin pour la gestion des postes en attente.
 */
class SyncNetworkService : public QObject {
    Q_OBJECT

public:
    static constexpr quint16 kDefaultPort = 45456;

    // securityService doit rester valide pendant toute la duree de vie de
    // ce service (fournit l'identite locale utilisee pour le TLS).
    explicit SyncNetworkService(QString localMachineId, QString localMachineName, SecurityService *securityService, QObject *parent = nullptr);
    ~SyncNetworkService() override;

    bool start(quint16 port = kDefaultPort);
    void stop();
    Q_INVOKABLE bool isListening() const;

    // Initie une connexion sortante vers un poste distant (typiquement
    // suite a DiscoveryService::peerDiscovered). Sans effet si une
    // connexion vers ce peerId existe deja. La session applicative ne
    // debute qu'une fois la poignee de main TLS validee (poste autorise).
    void connectToPeer(const QString &peerId, const QHostAddress &address, quint16 port = kDefaultPort);
    void disconnectFromPeer(const QString &peerId);
    Q_INVOKABLE QStringList connectedPeers() const;

    // --- Gestion des machines autorisees (delegue a TlsHandshakeService),
    // exposees a ui/Admin/AdminView.qml -------------------------------------
    Q_INVOKABLE void trustPeer(const QString &fingerprintSha256, const QString &label = QString());
    Q_INVOKABLE void revokePeer(const QString &fingerprintSha256);
    Q_INVOKABLE bool isPeerTrusted(const QString &fingerprintSha256) const;
    Q_INVOKABLE QStringList trustedFingerprints() const;

    // --- Emission de messages -------------------------------------------
    void broadcastFileInfo(const QString &folder, const QString &path, const QString &hash, qint64 size, int version);
    void broadcastDeleteFile(const QString &folder, const QString &path, int version);
    void broadcastRenameFile(const QString &folder, const QString &oldPath, const QString &newPath, int version);

    void sendSyncRequest(const QString &peerId, const QString &folder);
    void sendSyncResponse(const QString &peerId, const QString &folder, const QJsonArray &files);
    void sendFileRequest(const QString &peerId, const QString &folder, const QString &path, qint64 offset = 0);
    void sendFileChunk(const QString &peerId, const QString &folder, const QString &path, qint64 offset, const QByteArray &data, bool isLast);
    void sendSyncFinished(const QString &peerId, const QString &folder);

signals:
    void peerConnected(const QString &peerId);
    void peerDisconnected(const QString &peerId);

    // Emis quand un poste presente un certificat valide mais non autorise
    // (absent de TrustedPeerStore) : la connexion a ete refusee. Permet a
    // l'UI (ui/Admin) de proposer l'ajout de ce poste a la liste de
    // confiance.
    void unknownPeerRejected(const QString &fingerprint, const QString &peerAddress);

    void syncRequestReceived(const QString &peerId, const QString &folder);
    void syncResponseReceived(const QString &peerId, const QString &folder, const QJsonArray &files);
    void fileInfoReceived(const QString &peerId, const QString &folder, const QString &path, const QString &hash, qint64 size, int version);
    void fileRequestReceived(const QString &peerId, const QString &folder, const QString &path, qint64 offset);
    void fileChunkReceived(const QString &peerId, const QString &folder, const QString &path, qint64 offset, const QByteArray &data, bool isLast);
    void deleteFileReceived(const QString &peerId, const QString &folder, const QString &path, int version);
    void renameFileReceived(const QString &peerId, const QString &folder, const QString &oldPath, const QString &newPath, int version);
    void syncFinishedReceived(const QString &peerId, const QString &folder);

private:
    struct Connection {
        QSslSocket *socket = nullptr;
        QString peerId; // vide jusqu'a reception du HELLO (connexions entrantes)
        QByteArray buffer;
    };

    void setupSocket(QSslSocket *socket, const QString &knownPeerId);
    void handleMessage(QSslSocket *socket, const QJsonObject &message);
    void sendToPeer(const QString &peerId, const QJsonObject &message);
    void removeConnectionFor(QSslSocket *socket);
    Connection *connectionForSocket(QSslSocket *socket);
    Connection *connectionForPeer(const QString &peerId);

    QString m_localMachineId;
    QString m_localMachineName;
    TlsHandshakeService *m_tls = nullptr; // parente = this (QObject)
    QHash<QSslSocket *, Connection> m_connections;
    QHash<QSslSocket *, QString> m_pendingOutgoingPeerIds; // en attente de poignee de main TLS
};

} // namespace network

#endif // NETWORK_SYNCNETWORKSERVICE_H
