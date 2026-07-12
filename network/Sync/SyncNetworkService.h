#ifndef NETWORK_SYNCNETWORKSERVICE_H
#define NETWORK_SYNCNETWORKSERVICE_H

#include <QHash>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QString>

QT_BEGIN_NAMESPACE
class QTcpServer;
class QTcpSocket;
QT_END_NAMESPACE

namespace network {

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
 * Note de securite : ce service echange les messages en clair sur TCP.
 * Le projet dispose deja d'une infrastructure TLS (network::SecurityService
 * + network::TlsHandshakeService + TrustedPeerStore) utilisee par d'autres
 * canaux ; brancher la synchronisation dessus est une amelioration
 * naturelle mais volontairement laissee hors scope ici pour limiter les
 * risques de cette premiere version (voir tache de suivi proposee).
 */
class SyncNetworkService : public QObject {
    Q_OBJECT

public:
    static constexpr quint16 kDefaultPort = 45456;

    explicit SyncNetworkService(QString localMachineId, QString localMachineName, QObject *parent = nullptr);
    ~SyncNetworkService() override;

    bool start(quint16 port = kDefaultPort);
    void stop();
    bool isListening() const;

    // Initie une connexion sortante vers un poste distant (typiquement
    // suite a DiscoveryService::peerDiscovered). Sans effet si une
    // connexion vers ce peerId existe deja.
    void connectToPeer(const QString &peerId, const QHostAddress &address, quint16 port = kDefaultPort);
    void disconnectFromPeer(const QString &peerId);
    QStringList connectedPeers() const;

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
        QTcpSocket *socket = nullptr;
        QString peerId; // vide jusqu'a reception du HELLO (connexions entrantes)
        QByteArray buffer;
    };

    void setupSocket(QTcpSocket *socket, const QString &knownPeerId);
    void handleMessage(QTcpSocket *socket, const QJsonObject &message);
    void sendToPeer(const QString &peerId, const QJsonObject &message);
    void removeConnectionFor(QTcpSocket *socket);
    Connection *connectionForSocket(QTcpSocket *socket);
    Connection *connectionForPeer(const QString &peerId);

    QString m_localMachineId;
    QString m_localMachineName;
    QTcpServer *m_server = nullptr;
    QHash<QTcpSocket *, Connection> m_connections;
};

} // namespace network

#endif // NETWORK_SYNCNETWORKSERVICE_H
