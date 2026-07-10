#ifndef NETWORK_TRANSFERSERVICE_H
#define NETWORK_TRANSFERSERVICE_H

#include <QObject>
#include <QHostAddress>
#include <QString>
#include <QByteArray>
#include <QHash>

class QTcpServer;
class QTcpSocket;
class QFile;

namespace network {

/**
 * @brief Transfert de fichiers via TCP, par blocs, avec accuses de reception.
 *
 * Protocole applicatif (au-dessus de TCP, un socket par transfert) :
 *  1. L'expediteur ouvre une connexion TCP vers le port d'ecoute du
 *     destinataire et envoie un en-tete : nom du fichier (UTF-8) et
 *     taille totale en octets (voir writeHeader()/readHeader()).
 *  2. Le fichier est ensuite envoye sequentiellement par blocs de
 *     kBlockSize octets maximum, chaque bloc etant prefixe par sa
 *     taille. Apres ecriture d'un bloc sur disque, le destinataire
 *     renvoie un octet d'accuse de reception (kAckByte) avant que
 *     l'expediteur n'envoie le bloc suivant (aller-retour "stop-and-wait"),
 *     ce qui garantit qu'aucun bloc n'est perdu et que le fichier
 *     reconstruit est identique a l'original (issue #53).
 *  3. La connexion est fermee par l'expediteur une fois le dernier
 *     accuse recu.
 *
 * Utilise directement QTcpServer/QTcpSocket (pas de WebSocket) : le
 * transfert de fichiers n'a pas besoin du framing WebSocket utilise par
 * la messagerie (network::MessagingService/MessagingServer).
 */
class TransferService : public QObject
{
    Q_OBJECT

public:
    explicit TransferService(QObject *parent = nullptr);
    ~TransferService() override;

    /// Demarre l'ecoute des transferts entrants sur le port specifie.
    bool start(quint16 port = 12346);

    /// Arrete l'ecoute et annule les transferts en cours.
    void stop();

    bool isRunning() const;

    /// Port d'ecoute effectif (0 si non demarre).
    quint16 port() const;

    /// Taille maximale d'un bloc, en octets (voir kBlockSize).
    static qint64 blockSize();

    /**
     * @brief Envoie le fichier local filePath vers host:port.
     *
     * Asynchrone : le resultat est communique via les signaux
     * transferStarted/transferProgress/transferCompleted/transferFailed.
     * @return false immediatement si le fichier ne peut pas etre ouvert
     * ou si la connexion ne peut pas etre initiee ; true sinon (le
     * transfert est en cours).
     */
    bool sendFile(const QHostAddress &host, quint16 port, const QString &filePath);

signals:
    /// Emis quand un transfert (entrant ou sortant) demarre.
    void transferStarted(const QString &transferKey, const QString &fileName, qint64 fileSize, bool incoming);

    /// Emis a intervalles reguliers pendant le transfert.
    void transferProgress(const QString &transferKey, qint64 bytesTransferred, qint64 totalBytes);

    /// Emis quand le transfert est termine avec succes.
    void transferCompleted(const QString &transferKey, const QString &filePath);

    /// Emis en cas d'echec (connexion perdue, erreur disque...).
    void transferFailed(const QString &transferKey, const QString &errorString);

private slots:
    // Cote serveur (reception).
    void onNewConnection();
    void onServerSocketReadyRead();
    void onServerSocketDisconnected();

    // Cote client (envoi).
    void onClientSocketConnected();
    void onClientSocketReadyRead();
    void onClientSocketBytesWritten(qint64 bytes);
    void onClientSocketErrorOccurred();

private:
    static constexpr quint32 kBlockSize = 64 * 1024;      ///< Taille max d'un bloc (64 Ko).
    static constexpr char kAckByte = 0x01;                ///< Octet d'accuse de reception.
    static const QByteArray kMagic;                       ///< Signature d'en-tete du protocole.

    /// Etat de reception associe a un socket cote serveur.
    struct ReceiveState {
        QString transferKey;
        QByteArray buffer;          ///< Octets recus non encore consommes.
        bool headerParsed = false;
        QString fileName;
        qint64 fileSize = 0;
        qint64 bytesReceived = 0;
        QFile *file = nullptr;
        QString destinationPath;
        qint64 pendingBlockSize = -1; ///< Taille du bloc en cours d'attente (-1 = attend l'entete de bloc).
    };

    /// Etat d'envoi associe a un socket cote client.
    struct SendState {
        QString transferKey;
        QFile *file = nullptr;
        QString filePath;
        qint64 fileSize = 0;
        qint64 bytesSent = 0;
        bool headerSent = false;
        bool waitingForAck = false;
    };

    void sendNextBlock(QTcpSocket *socket);
    void finishReceive(QTcpSocket *socket, bool success, const QString &errorString = QString());
    void finishSend(QTcpSocket *socket, bool success, const QString &errorString = QString());
    QString receiveDirectory() const;
    static QString makeTransferKey(QTcpSocket *socket);

    QTcpServer *m_server = nullptr;
    QHash<QTcpSocket*, ReceiveState> m_receiveStates;
    QHash<QTcpSocket*, SendState> m_sendStates;
    QString m_receiveDirOverride;

public:
    /// Permet de surcharger le repertoire de reception (tests). Vide =
    /// repertoire "CollabLAN Transfers" dans les documents de l'utilisateur.
    void setReceiveDirectory(const QString &dir);
};

} // namespace network

#endif // NETWORK_TRANSFERSERVICE_H
