#ifndef NETWORK_TRANSFERSERVICE_H
#define NETWORK_TRANSFERSERVICE_H

#include <QObject>
#include <QString>
#include <functional>

namespace network {

/**
 * @brief Transfert de fichiers par blocs (chunks), avec reprise
 * (Phase 8 de "Shared Folder").
 *
 * Utilitaire pur d'entrees/sorties : ne connait rien du reseau. Cote
 * emission, on lit le fichier local morceau par morceau et on delegue
 * l'envoi effectif a un callback (fourni par SyncNetworkService, qui
 * encode chaque morceau en message FILE_CHUNK). Cote reception, on
 * ecrit chaque morceau recu a l'offset indique, ce qui permet de
 * reprendre un transfert interrompu sans tout retelecharger : il suffit
 * de connaitre la taille deja ecrite (fileSize()) et de reprendre a cet
 * offset.
 */
class TransferService : public QObject {
    Q_OBJECT

public:
    static constexpr qint64 kDefaultChunkSize = 262144; // 256 KiB

    // Callback appele pour chaque morceau lu : renvoie false pour
    // interrompre l'envoi (ex. connexion perdue).
    using ChunkSender = std::function<bool(const QByteArray &data, qint64 offset, bool isLast)>;

    explicit TransferService(QObject *parent = nullptr);
    ~TransferService() override;

    // Lit filePath par blocs de chunkSize octets a partir de startOffset
    // (reprise) et appelle chunkSender() pour chacun. Retourne false si
    // le fichier est illisible ou si chunkSender() a interrompu l'envoi.
    bool sendFileInChunks(const QString &filePath,
                           const ChunkSender &chunkSender,
                           qint64 startOffset = 0,
                           qint64 chunkSize = kDefaultChunkSize);

    // Ecrit data a l'offset donne dans destFilePath (cree le fichier et
    // ses dossiers parents si necessaire). Utilise cote reception, un
    // appel par message FILE_CHUNK recu.
    bool receiveChunk(const QString &destFilePath, qint64 offset, const QByteArray &data);

    // Taille actuelle du fichier destination, utile pour reprendre un
    // transfert interrompu (offset = fileSize()).
    static qint64 fileSize(const QString &filePath);

    QString lastError() const;

signals:
    void progressChanged(const QString &filePath, qint64 bytesTransferred, qint64 totalBytes);

private:
    QString m_lastError;
};

} // namespace network

#endif // NETWORK_TRANSFERSERVICE_H
