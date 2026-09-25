#ifndef CORE_TRANSFERCONTEXT_H
#define CORE_TRANSFERCONTEXT_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QHash>
#include <QSet>
#include <QStringList>
#include <QDir>
#include <QDirIterator>

#include "TransferManager.h"
#include "UserManager.h"
#include "Transfer/TransferService.h"
#include "Discovery/PeersModel.h"

namespace core {

/**
 * @brief Wrapper pour exposer le transfert de fichiers a QML (issue #57).
 *
 * Relie network::TransferService (protocole reseau, progression en temps
 * reel) et core::TransferManager (envoi + persistance, issues #53/#54/#55)
 * a FileTransferView.qml : selection d'un fichier a envoyer, choix du
 * destinataire parmi les postes decouverts (network::PeersModel), et
 * suivi de la progression exacte de chaque transfert en cours (envoi et
 * reception), sous forme de liste QML (activeTransfers).
 */
class TransferContext : public QObject
{
    Q_OBJECT
    Q_PROPERTY(core::TransferManager* transferManager READ transferManager WRITE setTransferManager NOTIFY transferManagerChanged)
    Q_PROPERTY(network::TransferService* transferService READ transferService WRITE setTransferService NOTIFY transferServiceChanged)
    Q_PROPERTY(network::PeersModel* peersModel READ peersModel WRITE setPeersModel NOTIFY peersModelChanged)
    Q_PROPERTY(QVariantList activeTransfers READ activeTransfers NOTIFY activeTransfersChanged)

public:
    explicit TransferContext(QObject *parent = nullptr);
    ~TransferContext() override;

    TransferManager* transferManager() const { return m_transferManager; }
    void setTransferManager(TransferManager *manager);

    network::TransferService* transferService() const { return m_transferService; }
    void setTransferService(network::TransferService *service);

    network::PeersModel* peersModel() const { return m_peersModel; }
    void setPeersModel(network::PeersModel *model);

    /// Configure le UserManager (necessaire pour determiner l'expediteur).
    void setUserManager(UserManager *manager);

    /// Transferts en cours ou recemment termines/echoues, le plus recent
    /// en dernier. Chaque element est une QVariantMap prete a l'emploi
    /// comme modele QML : transferKey, fileName, direction ("Envoi" /
    /// "Reception", localise - a ne pas utiliser pour une comparaison
    /// logique cote QML), incoming (bool, equivalent non localise de
    /// direction, a utiliser pour le rendu), statusText, bytesTransferred,
    /// totalBytes, percent (0-100, diviser par 100 cote QML pour une
    /// fraction 0-1), errorString, filePath (chemin local, vide si
    /// inconnu), peerAddress/peerName (correspondant, vide si inconnu -
    /// permet de regrouper par correspondant cote QML, voir
    /// FileTransferView.qml), timestamp (date ISO du transfert, pour
    /// affichage/tri).
    QVariantList activeTransfers() const { return m_activeTransfers; }

    /// Liste des postes decouverts, prete a servir de modele pour un
    /// selecteur de destinataire : chaque element est une map
    /// name/address/port (port = port TCP suppose du TransferService
    /// distant, voir sendFile()).
    Q_INVOKABLE QVariantList availableRecipients() const;

    /**
     * @brief Envoie filePath vers le poste dont l'adresse IP est address.
     *
     * portHint est le port TCP du TransferService distant si connu ;
     * sinon (<=0) network::TransferService::defaultPort() est utilise,
     * car la decouverte reseau (issue #9) n'annonce que le port UDP
     * utilise pour la decouverte elle-meme, pas le port TCP du transfert.
     * @return false immediatement si le fichier est invalide ou si
     * l'envoi n'a pas pu demarrer ; true si le transfert est lance.
     */
    /// peerMachineId (optionnel) : UUID DiscoveryService du destinataire
    /// choisi (voir availableRecipients()), transmis tel quel a
    /// TransferManager::sendFile() pour eviter une re-resolution par
    /// adresse IP a l'arrivee de transferStarted() -- resolution qui peut
    /// echouer sur une machine multi-interfaces et faire atterrir l'envoi
    /// et la reception d'un meme correspondant dans deux dossiers/tuiles
    /// distincts cote UI (voir FileTransferView.qml::buildPeerGroups()).
    Q_INVOKABLE bool sendFile(const QString &filePath, const QString &address, int portHint = -1,
                              const QString &peerMachineId = QString());

    /**
     * @brief Envoie tout le contenu d'un dossier (recursivement) vers le
     * poste dont l'adresse IP est address.
     *
     * Chaque fichier du dossier est envoye individuellement (un appel
     * sendFile() interne par fichier, mis en file cote TransferService
     * comme n'importe quel envoi multi-fichiers), mais avec son
     * sous-chemin d'origine (relatif au dossier choisi, nom du dossier
     * inclus) afin que l'arborescence soit recreee a l'identique cote
     * reception plutot que de deverser tous les fichiers en vrac.
     *
     * @return false immediatement si folderPath n'est pas un dossier
     * lisible, ou si aucun fichier n'a pu etre mis en file (dossier
     * vide ou tous les envois ont echoue immediatement) ; true des
     * qu'au moins un fichier a ete mis en file avec succes.
     */
    Q_INVOKABLE bool sendFolder(const QString &folderPath, const QString &address, int portHint = -1,
                                const QString &peerMachineId = QString());

    /**
     * @brief Relance un envoi precedemment echoue (transferKey issu de
     * activeTransfers), en reutilisant le meme fichier local et le meme
     * destinataire.
     *
     * Ne fait rien de plus qu'appeler sendFile() a nouveau : la reprise a
     * l'octet pres (issue #54) est entierement geree par
     * network::TransferService cote protocole (le destinataire reconnait
     * le fichier ".part" partiel deja present et n'en redemande que la
     * suite) - aucune logique de "curseur" supplementaire n'est necessaire
     * ici, seulement un point d'entree pour la relancer manuellement
     * depuis l'UI (Release 9), la reprise automatique existante ne se
     * declenchant jusqu'ici que si le code appelant refait lui-meme un
     * sendFile() identique.
     *
     * Echoue (transferRejected emis) si le transfert n'est pas un envoi
     * en echec, ou si le fichier local/le destinataire ne sont plus
     * connus (transfert d'un envoi trop ancien, fichier deplace...).
     */
    Q_INVOKABLE bool retryTransfer(const QString &transferKey);

    /**
     * @brief Ouvre l'explorateur de fichiers a l'emplacement de filePath,
     * en selectionnant le fichier si possible (sinon le dossier parent
     * s'il existe encore, sinon le dossier de reception par defaut).
     * @return false si aucun emplacement exploitable n'a ete trouve.
     */
    Q_INVOKABLE bool openFileLocation(const QString &filePath) const;

    /// Ouvre directement le dossier dans lequel LocaLink enregistre les
    /// fichiers recus (par defaut "LocaLink Transfers" dans les documents
    /// de l'utilisateur), independamment de tout transfert particulier.
    Q_INVOKABLE bool openDownloadsFolder() const;

signals:
    void transferManagerChanged();
    void transferServiceChanged();
    void peersModelChanged();
    void activeTransfersChanged();

    /// Emis lorsque sendFile() echoue immediatement (fichier illisible,
    /// connexion impossible...), pour affichage d'un message d'erreur.
    void transferRejected(const QString &reason);

private slots:
    void onTransferStarted(const QString &transferKey, const QString &fileName, qint64 fileSize,
                            bool incoming, qint64 resumeOffset, const QString &senderUuid,
                            const QString &recipientUuid, const QHostAddress &peerAddress,
                            const QString &peerMachineId, bool isFolderTransfer);
    void onTransferProgress(const QString &transferKey, qint64 bytesTransferred, qint64 totalBytes);
    void onTransferCompleted(const QString &transferKey, const QString &filePath);
    void onTransferFailed(const QString &transferKey, const QString &errorString);

private:
    int indexOfTransfer(const QString &transferKey) const;
    static int percentOf(qint64 bytesTransferred, qint64 totalBytes);

    /// Implementation commune de sendFile()/sendFolder() : relativeDirPath
    /// (vide pour un envoi de fichier isole) est transmis tel quel a
    /// TransferManager::sendFile() pour que le destinataire recree
    /// l'arborescence d'origine (voir sendFolder()).
    bool sendFileWithRelativeDir(const QString &filePath, const QString &address, int portHint,
                                  const QString &peerMachineId, const QString &relativeDirPath);

    /// Resout le nom affichable d'un correspondant. Priorite a
    /// peerMachineId (UUID DiscoveryService::localId(), transmis dans
    /// l'en-tete de transfert - voir network::TransferService::encodeHeader()) :
    /// contrairement a l'adresse IP, il reste valide meme si la machine a
    /// plusieurs interfaces reseau. Repli sur peerAddress (comparaison
    /// tolerante aux adresses IPv4-mappees en IPv6) si peerMachineId est
    /// vide, via m_peersModel (poste actuellement decouvert sur le reseau
    /// local). Retourne une chaine vide si non resolu.
    QString resolvePeerName(const QHostAddress &peerAddress, const QString &peerMachineId) const;

    /// Port TCP actuellement annonce par le pair a peerAddress (via
    /// m_peersModel), utilise par retryTransfer() pour reprendre au bon
    /// port meme s'il a change depuis l'echec initial. -1 si le pair
    /// n'est plus decouvert (retryTransfer() retombe alors sur le dernier
    /// port connu pour CE transfert, voir entry "port" / m_pendingSendPorts,
    /// puis seulement sur network::TransferService::defaultPort() si meme
    /// celui-ci est inconnu).
    int resolvePeerPort(const QString &peerAddress) const;

    /// Reconstruit activeTransfers() a partir de l'historique persiste
    /// (core::TransferManager::allTransfers()), pour que l'historique
    /// des transferts envoyes/recus reste visible apres redemarrage de
    /// l'application (au lieu de repartir vide a chaque lancement).
    void loadHistory();

    /// Traduit un enregistrement d'historique persiste vers le format
    /// QVariantMap attendu par FileTransferView.qml.
    QVariantMap entryFromHistory(const models::Transfer &transfer) const;

    TransferManager *m_transferManager = nullptr;
    network::TransferService *m_transferService = nullptr;
    network::PeersModel *m_peersModel = nullptr;
    UserManager *m_userManager = nullptr;

    QVariantList m_activeTransfers;

    /// sendFile() connait le chemin local choisi par l'utilisateur avant
    /// que TransferService::transferStarted() (asynchrone : apres
    /// connexion TCP) ne soit emis ; on le fait patienter ici, indexe par
    /// nom de fichier, pour l'attacher a l'entree activeTransfers a la
    /// reception de transferStarted().
    QHash<QString, QStringList> m_pendingSendFilePaths;

    /// Meme mecanisme que m_pendingSendFilePaths, pour le port TCP
    /// effectivement utilise par ce sendFile() (apres resolution de
    /// portHint) : conserve sur l'entree activeTransfers ("port") afin
    /// que retryTransfer() puisse s'y reprendre si le pair n'est plus
    /// decouvert dans m_peersModel au moment de la relance (voir
    /// retryTransfer()) plutot que de retomber sur un port par defaut
    /// potentiellement different de celui reellement utilise par le pair.
    QHash<QString, QList<int>> m_pendingSendPorts;

    /// Cles (transferKey) des transferts identifies comme folder-sync par
    /// onTransferStarted() (isFolderTransfer == true) : ces transferts ne
    /// doivent pas apparaitre dans activeTransfers() (voir le meme filtre
    /// applique cote persistance par TransferManager::onNetworkTransferStarted()).
    /// transferProgress/transferCompleted/transferFailed ne portent pas ce
    /// flag : on le memorise donc ici pour pouvoir les ignorer eux aussi,
    /// et on le retire a la fin du transfert (Completed/Failed) pour ne
    /// pas laisser grossir cet ensemble indefiniment.
    QSet<QString> m_folderSyncTransferKeys;
};

} // namespace core

#endif // CORE_TRANSFERCONTEXT_H