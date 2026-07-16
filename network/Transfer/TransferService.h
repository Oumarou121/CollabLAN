#ifndef NETWORK_TRANSFERSERVICE_H
#define NETWORK_TRANSFERSERVICE_H

#include <QObject>
#include <QHostAddress>
#include <QString>
#include <QByteArray>
#include <QHash>
#include <QQueue>
#include <functional>

class QTcpServer;
class QTcpSocket;
class QFile;

namespace network {

/**
 * @brief Transfert de fichiers via TCP, par blocs, avec accuses de reception
 * et reprise apres interruption.
 *
 * Protocole applicatif (au-dessus de TCP) :
 *  0. Pool de connexions par destination (host:port) : au lieu d'ouvrir
 *     une connexion TCP par fichier, sendFile() met le fichier en file
 *     d'attente pour sa destination et reutilise une connexion existante
 *     des que l'un des fichiers en cours se termine, dans la limite de
 *     kMaxConnectionsPerPeer connexions simultanees par pair. Ceci evite
 *     de repayer un handshake TCP + echange d'en-tete pour chaque fichier
 *     lors d'un partage de dossier avec de nombreux petits fichiers (une
 *     connexion peut ainsi enchainer plusieurs fichiers a la suite avant
 *     de se fermer, cf. dispatchSendQueue()/startSendOnSocket() cote
 *     expediteur et la reinitialisation de ReceiveState dans
 *     finishReceive() cote destinataire). Le reste du protocole
 *     ci-dessous (en-tete, reprise, blocs, accuses) reste inchange et
 *     s'applique a CHAQUE fichier individuellement au sein d'une
 *     connexion partagee.
 *  1. L'expediteur ouvre une connexion TCP vers le port d'ecoute du
 *     destinataire et envoie un en-tete : nom du fichier (UTF-8) et
 *     taille totale en octets (voir encodeHeader()/decodeHeader()).
 *  2. Le destinataire ecrit chaque fichier recu dans un fichier temporaire
 *     "<nom>.part". Si un "<nom>.part" de meme taille finale existe deja
 *     (transfert precedent interrompu), il repond avec le nombre d'octets
 *     deja recus (resumeOffset) au lieu de recommencer a zero ; sinon
 *     resumeOffset vaut 0. L'expediteur se positionne (seek) a cet
 *     octet dans le fichier local avant de commencer l'envoi (issue #54).
 *  3. Le fichier est ensuite envoye sequentiellement, a partir de
 *     resumeOffset, par blocs de kBlockSize octets maximum, chaque bloc
 *     etant prefixe par sa taille. Apres ecriture d'un bloc sur disque,
 *     le destinataire renvoie un octet d'accuse de reception (kAckByte)
 *     avant que l'expediteur n'envoie le bloc suivant (aller-retour
 *     "stop-and-wait"), ce qui garantit qu'aucun bloc n'est perdu et que
 *     le fichier reconstruit est identique a l'original (issue #53).
 *  4. Si la connexion est perdue en cours de route, le fichier ".part"
 *     du destinataire n'est PAS supprime : rappeler sendFile() avec le
 *     meme fichier local reprend automatiquement a partir du dernier
 *     bloc confirme (issue #54). Une fois le transfert termine avec
 *     succes, "<nom>.part" est renomme vers son nom final.
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
    bool start(quint16 port = kDefaultPort);

    /// Arrete l'ecoute et annule les transferts en cours.
    void stop();

    bool isRunning() const;

    /// Port d'ecoute effectif (0 si non demarre).
    quint16 port() const;

    /// Taille maximale d'un bloc, en octets (voir kBlockSize).
    static qint64 blockSize();

    /// Port TCP par defaut utilise par start() lorsqu'aucun port n'est
    /// precise. Utile pour les couches superieures (UI...) qui ont besoin
    /// de deviner le port d'un pair distant sans le connaitre explicitement.
    static quint16 defaultPort();

    /**
     * @brief Envoie le fichier local filePath vers host:port, pour le
     * compte de l'utilisateur senderUuid a destination de recipientUuid.
     *
     * senderUuid/recipientUuid sont transmis dans l'en-tete du protocole et
     * restitues par transferStarted() cote destinataire : ils permettent
     * a core::TransferManager d'enregistrer l'historique du transfert en
     * base (issue #55) sans que TransferService n'ait besoin de connaitre
     * la couche base de donnees.
     *
     * Asynchrone : le resultat est communique via les signaux
     * transferStarted/transferProgress/transferCompleted/transferFailed.
     * Reprise automatique (issue #54) : si un transfert precedent du
     * meme fichier (meme nom, meme taille) vers ce destinataire a ete
     * interrompu avant la fin, l'envoi reprend a partir du dernier bloc
     * confirme par le destinataire au lieu de repartir de zero.
     *
     * Mis en file d'attente pour sa destination (host:port) : peut donc
     * demarrer immediatement (nouvelle connexion ou connexion existante
     * libre) ou attendre qu'une des kMaxConnectionsPerPeer connexions du
     * pool pour ce pair se libere -- voir la section 0 de la doc de
     * classe ci-dessus.
     *
     * @return false immediatement seulement si filePath est illisible des
     * l'appel (fichier absent, permissions...) ; dans ce cas rien n'est mis
     * en file et aucun signal n'est emis. Si le fichier redevient illisible
     * plus tard (juste avant l'envoi effectif, une fois son tour venu dans
     * la file), l'echec est signale de façon asynchrone via transferFailed()
     * a la place -- le true retourne ici ne garantit donc que la mise en
     * file, pas le succes du transfert.
     */
    bool sendFile(const QHostAddress &host, quint16 port, const QString &filePath,
                  const QString &senderUuid, const QString &recipientUuid,
                  const QString &transferFileName = QString(), bool isFolderTransfer = false);

signals:
    /// Emis quand un transfert (entrant ou sortant) demarre. resumeOffset
    /// est > 0 lorsque le transfert reprend un transfert interrompu
    /// precedemment (0 pour un transfert qui commence de zero). senderUuid
    /// et recipientUuid sont ceux fournis a sendFile() par l'expediteur.
    /// peerAddress est l'adresse IP de l'autre poste de l'echange (celle
    /// fournie a sendFile() pour un envoi, celle du socket entrant pour
    /// une reception) : permet a l'historique de regrouper les transferts
    /// par correspondant independamment de tout compte utilisateur local.
    /// peerMachineId est l'UUID DiscoveryService::localId() de l'expediteur
    /// pour une reception (vide pour un envoi, voir encodeHeader()) :
    /// resolution de peer_name par identifiant plutot que par adresse IP,
    /// necessaire sur une machine multi-interfaces ou l'annonce UDP de
    /// decouverte et la connexion TCP du transfert peuvent emprunter des
    /// interfaces (donc des adresses) differentes.
    void transferStarted(const QString &transferKey, const QString &fileName, qint64 fileSize,
                          bool incoming, qint64 resumeOffset, const QString &senderUuid,
                          const QString &recipientUuid, const QHostAddress &peerAddress,
                          const QString &peerMachineId, bool isFolderTransfer = false);

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
    /// Taille de bloc par defaut : 256 Ko, adaptee aux debits LAN (100 Mbps–1 Gbps).
    /// Valeur modifiable via setBlockSize() pour les environnements a faible debit ou
    /// pour les tests unitaires (petites valeurs pour exercer plusieurs blocs rapidement).
    static constexpr quint32 kDefaultBlockSize = 256 * 1024;
    static constexpr quint16 kDefaultPort = 12346;        ///< Port TCP par defaut (voir defaultPort()).
    static constexpr char kAckByte = 0x01;                ///< Octet d'accuse de reception.
    static const QByteArray kMagic;                       ///< Signature d'en-tete du protocole.

    /// Etat de reception associe a un socket cote serveur.
    struct ReceiveState {
        QString transferKey;
        QByteArray buffer;          ///< Octets recus non encore consommes.
        bool headerParsed = false;
        bool headerAcked = false;   ///< true une fois la reponse resumeOffset envoyee.
        QString fileName;
        qint64 fileSize = 0;
        qint64 bytesReceived = 0;
        QString senderUuid;
        QString recipientUuid;
        QString senderMachineId;    ///< UUID DiscoveryService::localId() de l'expediteur (voir encodeHeader()).
        bool compressionEnabled = false; ///< true si l'expediteur a active la compression zlib (compressionFlags & 0x01).
        bool isFolderTransfer = false; ///< true si le transfert provient de FolderSyncService (ne doit pas etre enregistre dans la table Transfers).
        QFile *file = nullptr;
        QString destinationPath;    ///< Chemin final (une fois le transfert termine).
        QString partialPath;        ///< Fichier temporaire "<nom>.part" pendant le transfert.
        qint64 pendingBlockSize = -1; ///< Taille du bloc en cours d'attente (-1 = attend l'entete de bloc).
        bool connectionIdle = false; ///< true entre deux fichiers sur une connexion reutilisee (voir finishReceive()) -- distingue une deconnexion normale (pair qui n'a plus rien a envoyer) d'un transfert reellement interrompu (onServerSocketDisconnected()).
    };

    /// Fichier en attente d'envoi vers une destination donnee (voir
    /// m_sendQueues) : mis de cote par sendFile() tant que le pool de
    /// connexions pour cette destination est plein, puis consomme par
    /// dispatchSendQueue()/startSendOnSocket() des qu'une connexion se
    /// libere.
    struct PendingSendJob {
        QString filePath;
        QString senderUuid;
        QString recipientUuid;
        QString transferFileName; ///< Nom annonce au destinataire (vide = basename de filePath).
        bool isFolderTransfer = false; ///< true si le transfert provient de FolderSyncService.
    };

    /// Adresse/port d'une destination, retrouvee par sa cle (voir
    /// destKeyFor()) au moment d'ouvrir une NOUVELLE connexion pour elle
    /// (une connexion reutilisee n'en a pas besoin, elle est deja
    /// connectee).
    struct DestInfo {
        QHostAddress host;
        quint16 port = 0;
    };

    /// Etat d'envoi associe a un socket cote client. Persiste au-dela d'un
    /// seul fichier : reutilise en place (voir startSendOnSocket()) tant
    /// que la connexion sert plusieurs fichiers consecutifs pour le meme
    /// pair (pool de connexions, voir doc de classe).
    struct SendState {
        QString transferKey;
        QFile *file = nullptr;
        QString filePath;
        qint64 fileSize = 0;
        qint64 bytesSent = 0;
        QString senderUuid;
        QString recipientUuid;
        bool resumeOffsetReceived = false; ///< true une fois la reponse du destinataire recue.
        bool waitingForAck = false;
        QByteArray buffer;          ///< Octets recus non encore consommes (reponse d'en-tete puis accuses).
        qint64 pendingFrameSize = -1; ///< Taille de la trame de reponse d'en-tete en attente.
        PendingSendJob pendingJob;  ///< Fichier a demarrer des que le socket est pret (connexion initiale ou reutilisation) -- voir startSendOnSocket().
    };

    /// Nombre maximal de connexions TCP simultanees ouvertes vers un meme
    /// pair (host:port) pour l'envoi de fichiers. Au-dela, les fichiers
    /// suivants patientent dans m_sendQueues et sont repris des qu'une des
    /// connexions existantes termine son fichier en cours (voir
    /// finishSend()). Une valeur > 1 permet de paralleliser un peu le
    /// transfert d'un dossier avec de nombreux fichiers sans pour autant
    /// ouvrir une connexion par fichier (cout de handshake TCP repete).
    static constexpr int kMaxConnectionsPerPeer = 3;

    void sendNextBlock(QTcpSocket *socket);
    void finishReceive(QTcpSocket *socket, bool success, const QString &errorString = QString());
    void finishSend(QTcpSocket *socket, bool success, const QString &errorString = QString());
    static QString makeTransferKey(QTcpSocket *socket);

    /// Cle identifiant une destination pour le regroupement des files
    /// d'attente/pool de connexions (m_sendQueues, m_destInfo,
    /// m_activeSendConnections) : simplement "host:port".
    static QString destKeyFor(const QHostAddress &host, quint16 port);

    /// Tente de demarrer le prochain fichier en attente pour destKey :
    /// ouvre une NOUVELLE connexion si le pool n'est pas plein et qu'il
    /// n'y a rien a reutiliser immediatement. Ne fait rien si la file est
    /// vide ou si le pool est deja au plafond (kMaxConnectionsPerPeer) --
    /// dans ce cas, le prochain appel viendra de finishSend() des qu'une
    /// connexion existante se libere.
    void dispatchSendQueue(const QString &destKey);

    /// Demarre (ou redemarre, pour une connexion reutilisee) l'envoi du
    /// fichier decrit par job sur socket, deja connecte. Reinitialise les
    /// champs de SendState propres a UN fichier (transferKey, filePath,
    /// bytesSent, etc.) en conservant le socket. Retourne false si le
    /// fichier n'a pas pu etre ouvert (dans ce cas, transferFailed() a
    /// deja ete emis et l'appelant doit considerer la connexion comme
    /// devant se fermer normalement, cf. finishSend()/onClientSocketConnected()).
    bool startSendOnSocket(QTcpSocket *socket, const PendingSendJob &job);

    QTcpServer *m_server = nullptr;
    QHash<QTcpSocket*, ReceiveState> m_receiveStates;
    QHash<QTcpSocket*, SendState> m_sendStates;
    QHash<QString, QQueue<PendingSendJob>> m_sendQueues;   ///< destKey -> fichiers en attente d'envoi vers cette destination.
    QHash<QString, DestInfo> m_destInfo;                    ///< destKey -> host/port, pour ouvrir de nouvelles connexions.
    QHash<QString, int> m_activeSendConnections;            ///< destKey -> nombre de connexions TCP actuellement ouvertes vers ce pair.
    QHash<QTcpSocket*, QString> m_socketDestKey;            ///< socket d'envoi -> destKey (pour retrouver sa file/son compteur a la fin d'un fichier).
    QString m_receiveDirOverride;
    QString m_localMachineId;        ///< UUID DiscoveryService::localId() local, transmis dans l'en-tete (voir encodeHeader()).
    bool m_compressionEnabled = false; ///< Voir setCompressionEnabled().
    quint32 m_blockSize = kDefaultBlockSize; ///< Voir setBlockSize().
    std::function<QString(const QHostAddress &, const QString &)> m_peerFolderNameResolver;

public:
    /// Permet de surcharger le repertoire de reception (tests). Vide =
    /// repertoire "CollabLAN Transfers" dans les documents de l'utilisateur.
    void setReceiveDirectory(const QString &dir);

    /// Identifiant machine (DiscoveryService::localId()) embarque dans
    /// l'en-tete de chaque envoi, pour permettre au destinataire de
    /// resoudre peer_name par UUID plutot que par adresse IP (voir
    /// transferStarted()). A appeler avant tout sendFile().
    void setLocalMachineId(const QString &machineId);

    /**
     * @brief Active ou desactive la compression zlib (via qCompress/qUncompress)
     * sur les blocs de donnees envoyes.
     *
     * Quand active, chaque bloc est compresse avant d'etre encadre et transmis ;
     * le destinataire decompresse automatiquement (l'information est negociee
     * dans l'en-tete du protocole via le champ compressionFlags).  Actif par
     * defaut a false : les fichiers texte sur un LAN rapide bénéficient
     * rarement de la compression (le LAN est plus rapide que le CPU de
     * compression/decompression).  Utile pour les connexions a faible debit ou
     * les fichiers fortement compressibles.
     */
    void setCompressionEnabled(bool enabled);

    /**
     * @brief Modifie la taille des blocs envoyes (en octets).  Doit etre
     * appele avant sendFile().
     *
     * La taille par defaut est kDefaultBlockSize (256 Ko), adaptee aux LAN
     * 100 Mbps–1 Gbps.  Reduire la taille (ex. 16 Ko) diminue la latence
     * de chaque acquittement et peut ameliorer la reactivite sur des liens
     * a faible debit ou pour les tests.
     */
    void setBlockSize(quint32 bytes);

    /// Taille de bloc actuellement configuree (voir setBlockSize()).
    quint32 currentBlockSize() const;

    /// Fonction de resolution du nom de dossier utilise pour regrouper,
    /// cote reception, tous les fichiers recus d'un meme correspondant
    /// dans un seul sous-dossier de receiveDirectory() (ex.
    /// "CollabLAN Transfers/laptop-marie/", au lieu d'un unique
    /// repertoire plat) - reçoit l'adresse IP et l'UUID machine
    /// (senderMachineId, voir encodeHeader()) du pair, doit renvoyer un
    /// nom de dossier deja nettoye des caracteres invalides sous Windows
    /// (voir Application::setupTransferPeerFolders() pour l'implementation
    /// par defaut, basee sur DiscoveryService). Si non definie ou si
    /// l'appel renvoie une chaine vide, repli sur l'UUID machine brut
    /// (senderMachineId, voir encodeHeader()) ; si celui-ci est egalement
    /// vide, aucun sous-dossier n'est cree (repertoire plat d'origine).
    void setPeerFolderNameResolver(std::function<QString(const QHostAddress &, const QString &)> resolver);

    /// Repertoire ou sont ecrits les fichiers recus (apres application de
    /// setReceiveDirectory() si utilise). Expose publiquement pour que
    /// l'UI (core::TransferContext) puisse proposer d'ouvrir ce dossier
    /// directement, independamment de tout transfert particulier.
    QString receiveDirectory() const;
};

} // namespace network

#endif // NETWORK_TRANSFERSERVICE_H
