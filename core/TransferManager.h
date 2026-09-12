#ifndef CORE_TRANSFERMANAGER_H
#define CORE_TRANSFERMANAGER_H

#include <QObject>
#include <QHash>
#include <QHostAddress>
#include <QString>
#include <QStringList>
#include <optional>
#include <vector>

#include "models/Transfer.h"
#include "database/Repositories/TransferRepository.h"
#include "database/Repositories/SettingsRepository.h"

namespace database {
class DatabaseManager;
}

namespace network {
class TransferService;
class DiscoveryService;
}

namespace core {

/**
 * @brief Relie network::TransferService (protocole TCP, issues #53/#54) a
 * database::TransferRepository (persistance, issue #55).
 *
 * TransferService ne connait rien de la base de donnees : il se contente
 * d'emettre des signaux avec un identifiant de transfert ephemere
 * (transferKey, un UUID). TransferManager ecoute ces signaux, enregistre
 * chaque transfert (fichier, expediteur, destinataire, statut) dans la
 * table Transfers des qu'il demarre, puis met a jour son statut
 * (en cours -> termine/echoue). Comme la base SQLite est persistee sur
 * disque par database::DatabaseManager, l'historique reste consultable
 * apres redemarrage de l'application (critere d'acceptation de #55).
 */
class TransferManager : public QObject
{
    Q_OBJECT

public:
    explicit TransferManager(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~TransferManager() override;

    /// Configure le service reseau ecoutant/emettant les transferts.
    /// Doit etre appele avant tout envoi/reception effectif.
    void setTransferService(network::TransferService *transferService);

    /// Permet de resoudre peer_name a partir de l'adresse du correspondant
    /// (nom annonce par network::DiscoveryService, s'il est alors visible
    /// sur le reseau). Optionnel : peer_name reste vide sinon (voir
    /// core::CallHistoryManager pour le meme principe).
    void setDiscoveryService(network::DiscoveryService *discoveryService);

    /// Envoie un fichier a un pair et enregistre le transfert (statut
    /// initial "in_progress") en base. Voir network::TransferService::sendFile().
    /// knownPeerMachineId (optionnel) : UUID DiscoveryService du
    /// destinataire choisi par l'appelant (cf. TransferContext::sendFile()),
    /// memorise ici (m_pendingPeerMachineIds) pour etre applique dans
    /// onNetworkTransferStarted() sans repasser par une resolution IP
    /// (network::TransferService ne transmet jamais peerMachineId cote
    /// envoi, voir son commentaire dans onClientSocketConnected()).
    bool sendFile(const QHostAddress &host, quint16 port, const QString &filePath,
                  const QString &senderUuid, const QString &recipientUuid,
                  const QString &knownPeerMachineId = QString(),
                  const QString &relativeDirPath = QString());

    /// Historique complet des transferts (tous utilisateurs), le plus recent en premier.
    std::vector<models::Transfer> allTransfers() const;

    /// Historique des transferts (envoyes ou recus) d'un utilisateur donne.
    std::vector<models::Transfer> userTransfers(const QString &userUuid) const;

    /// Recupere un transfert par son id en base.
    std::optional<models::Transfer> transfer(int id) const;

signals:
    /// Emis des qu'un transfert (entrant ou sortant) est enregistre en
    /// base, avec l'id genere par TransferRepository.
    void transferRecorded(int transferId, const models::Transfer &transfer);

    /// Emis quand le statut d'un transfert enregistre change.
    void transferStatusChanged(int transferId, models::TransferStatus status);

private slots:
    void onNetworkTransferStarted(const QString &transferKey, const QString &fileName, qint64 fileSize,
                                   bool incoming, qint64 resumeOffset, const QString &senderUuid,
                                   const QString &recipientUuid, const QHostAddress &peerAddress,
                                   const QString &peerMachineId, bool isFolderTransfer = false);
    void onNetworkTransferCompleted(const QString &transferKey, const QString &filePath);
    void onNetworkTransferFailed(const QString &transferKey, const QString &errorString);

private:
    /// CORRECTIF (stabilite du regroupement physique/historique) : le nom
    /// retourne par DiscoveryService::peers() pour un peerMachineId donne
    /// est mutable (nom d'utilisateur *actuellement* connecte sur le poste
    /// distant, cf. Application::setupDiscoveryService() -> setLocalName()
    /// sur authenticationChanged) : il peut donc changer d'un transfert a
    /// l'autre pour le meme correspondant (reconnexion sous un autre
    /// compte, pair momentanement absent de la decouverte...). On fige
    /// donc, dans la table Settings locale (cle "peer_folder_name:<uuid>",
    /// meme convention que network::TransferService::setPeerFolderNameResolver()
    /// cote Application.cpp pour que le nom affiche dans l'historique
    /// corresponde toujours au nom du sous-dossier physique), le premier
    /// nom lisible resolu pour ce peerMachineId, et on le reutilise
    /// ensuite systematiquement plutot que de repartir de la valeur
    /// courante de DiscoveryService a chaque appel.
    QString resolvePeerName(const QHostAddress &peerAddress, const QString &peerMachineId) const;
    /// Retrouve l'UUID DiscoveryService::localId() d'un pair par son
    /// adresse (utilise quand peerMachineId n'est pas transmis directement,
    /// ex. cote envoi - voir onNetworkTransferStarted()).
    QString resolvePeerMachineId(const QHostAddress &peerAddress) const;

    database::TransferRepository m_repository;
    /// Utilisee uniquement pour la mise en cache stable de resolvePeerName()
    /// (cle "peer_folder_name:<peerMachineId>", voir sa doc ci-dessus) -
    /// partage la meme connexion QSqlDatabase que m_repository.
    mutable database::SettingsRepository m_settingsRepository;
    network::TransferService *m_transferService = nullptr;
    network::DiscoveryService *m_discoveryService = nullptr;

    /// Associe la cle ephemere d'un transfert reseau en cours a l'id
    /// persistant correspondant dans la table Transfers.
    QHash<QString, int> m_activeTransfers;

    /// sendFile() connait le chemin local immediatement, mais
    /// TransferService::transferStarted() (qui declenche la creation de
    /// l'enregistrement en base) n'est emis qu'une fois la connexion TCP
    /// etablie, de maniere asynchrone : on fait patienter le chemin ici,
    /// indexe par nom de fichier, le temps de le recuperer dans
    /// onNetworkTransferStarted() (voir m_pendingSendFilePaths).
    QHash<QString, QStringList> m_pendingSendFilePaths;

    /// Meme principe que m_pendingSendFilePaths, en parallele strict (meme
    /// ordre d'ajout/retrait par nom de fichier) : memorise le
    /// peerMachineId connu au moment de l'appel a sendFile() (peut etre
    /// une chaine vide si l'appelant ne le connaissait pas), pour
    /// pouvoir l'appliquer dans onNetworkTransferStarted() cote envoi
    /// sans dependre d'une resolution IP fragile (voir sendFile()).
    QHash<QString, QStringList> m_pendingPeerMachineIds;
};

} // namespace core

#endif // CORE_TRANSFERMANAGER_H