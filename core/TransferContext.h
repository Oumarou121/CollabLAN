#ifndef CORE_TRANSFERCONTEXT_H
#define CORE_TRANSFERCONTEXT_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QHash>
#include <QStringList>

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
    /// "Reception"), statusText, bytesTransferred, totalBytes, percent
    /// (0-100), errorString, filePath (chemin local, vide si inconnu),
    /// peerAddress/peerName (correspondant, vide si inconnu - permet de
    /// regrouper par correspondant cote QML, voir FileTransferView.qml),
    /// timestamp (date ISO du transfert, pour affichage/tri).
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
    Q_INVOKABLE bool sendFile(const QString &filePath, const QString &address, int portHint = -1);

    /**
     * @brief Ouvre l'explorateur de fichiers a l'emplacement de filePath,
     * en selectionnant le fichier si possible (sinon le dossier parent
     * s'il existe encore, sinon le dossier de reception par defaut).
     * @return false si aucun emplacement exploitable n'a ete trouve.
     */
    Q_INVOKABLE bool openFileLocation(const QString &filePath) const;

    /// Ouvre directement le dossier dans lequel CollabLAN enregistre les
    /// fichiers recus (par defaut "CollabLAN Transfers" dans les documents
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
                            bool incoming, qint64 resumeOffset, int senderId, int recipientId,
                            const QHostAddress &peerAddress);
    void onTransferProgress(const QString &transferKey, qint64 bytesTransferred, qint64 totalBytes);
    void onTransferCompleted(const QString &transferKey, const QString &filePath);
    void onTransferFailed(const QString &transferKey, const QString &errorString);

private:
    int indexOfTransfer(const QString &transferKey) const;
    static int percentOf(qint64 bytesTransferred, qint64 totalBytes);

    /// Resout le nom affichable d'un correspondant a partir de son
    /// adresse IP, via m_peersModel (poste actuellement decouvert sur le
    /// reseau local). Retourne une chaine vide si non resolu.
    QString resolvePeerName(const QHostAddress &peerAddress) const;

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
};

} // namespace core

#endif // CORE_TRANSFERCONTEXT_H
