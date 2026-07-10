#ifndef CORE_TRANSFERMANAGER_H
#define CORE_TRANSFERMANAGER_H

#include <QObject>
#include <QHash>
#include <QHostAddress>
#include <QString>
#include <optional>
#include <vector>

#include "models/Transfer.h"
#include "database/Repositories/TransferRepository.h"

namespace database {
class DatabaseManager;
}

namespace network {
class TransferService;
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

    /// Envoie un fichier a un pair et enregistre le transfert (statut
    /// initial "in_progress") en base. Voir network::TransferService::sendFile().
    bool sendFile(const QHostAddress &host, quint16 port, const QString &filePath,
                  int senderId, int recipientId);

    /// Historique complet des transferts (tous utilisateurs), le plus recent en premier.
    std::vector<models::Transfer> allTransfers() const;

    /// Historique des transferts (envoyes ou recus) d'un utilisateur donne.
    std::vector<models::Transfer> userTransfers(int userId) const;

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
                                   bool incoming, qint64 resumeOffset, int senderId, int recipientId);
    void onNetworkTransferCompleted(const QString &transferKey, const QString &filePath);
    void onNetworkTransferFailed(const QString &transferKey, const QString &errorString);

private:
    database::TransferRepository m_repository;
    network::TransferService *m_transferService = nullptr;

    /// Associe la cle ephemere d'un transfert reseau en cours a l'id
    /// persistant correspondant dans la table Transfers.
    QHash<QString, int> m_activeTransfers;
};

} // namespace core

#endif // CORE_TRANSFERMANAGER_H
