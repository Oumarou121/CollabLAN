#ifndef MODELS_TRANSFER_H
#define MODELS_TRANSFER_H

#include <QString>
#include <QDateTime>

namespace models {

/**
 * @brief Statut d'un transfert de fichier.
 */
enum class TransferStatus {
    Pending,
    InProgress,
    Completed,
    Failed,
    Cancelled
};

QString transferStatusToString(TransferStatus status);
TransferStatus transferStatusFromString(const QString &value);

/**
 * @brief Represente un transfert de fichier en cours ou termine.
 *
 * Correspond a une ligne de la table `Transfers`. Ce modele est une
 * structure de donnees pure (aucune logique reseau) : la couche
 * network::TransferService s'occupe de l'envoi/reception effectifs des
 * blocs, database::TransferRepository de la persistance.
 */
class Transfer {
public:
    Transfer();
    Transfer(int id,
              QString senderUuid,
              QString recipientUuid,
              QString fileName,
              qint64 fileSize,
              TransferStatus status,
              QDateTime createdAt = QDateTime::currentDateTimeUtc());
    ~Transfer();

    int id() const;
    void setId(int id);

    /// UUID (Users.uuid, migration #017) de l'expediteur, vide si inconnu
    /// (poste LAN sans compte utilisateur associe). Remplace l'ancien
    /// senderId entier (colonne sender_id, supprimee).
    QString senderUuid() const;
    void setSenderUuid(const QString &senderUuid);

    /// UUID (Users.uuid, migration #017) du destinataire, vide si inconnu.
    /// Remplace l'ancien recipientId entier (colonne recipient_id,
    /// supprimee) : voir peerMachineId() pour identifier fiablement un
    /// correspondant LAN sans compte utilisateur.
    QString recipientUuid() const;
    void setRecipientUuid(const QString &recipientUuid);

    QString fileName() const;
    void setFileName(const QString &fileName);

    qint64 fileSize() const;
    void setFileSize(qint64 fileSize);

    /// Chemin complet sur le disque local : fichier source pour un envoi,
    /// fichier ecrit dans le dossier de reception pour une reception.
    /// Vide si inconnu (ex. transfert enregistre avant la migration #012).
    QString filePath() const;
    void setFilePath(const QString &filePath);

    /// Adresse IP du correspondant (l'autre poste de l'echange), vide si
    /// inconnue (transfert enregistre avant la migration #015). Permet de
    /// regrouper l'historique par correspondant independamment de tout
    /// compte utilisateur local associe (senderUuid/recipientUuid restent vides
    /// pour un poste LAN sans compte, voir migrations #012 et #017).
    QString peerAddress() const;
    void setPeerAddress(const QString &peerAddress);

    /// Nom affichable du correspondant au moment du transfert (snapshot
    /// resolu via network::DiscoveryService si le poste etait alors
    /// decouvert), fige a cet instant. Vide si non resolu.
    QString peerName() const;
    void setPeerName(const QString &peerName);

    /// UUID stable du pair (DiscoveryService::localId(), migration #016),
    /// vide si inconnu. Contrairement a senderUuid()/recipientUuid() (comptes
    /// Users locaux, souvent -1 en P2P LAN) et a peerAddress() (IP non
    /// stable), c'est l'identifiant le plus fiable du correspondant.
    QString peerMachineId() const;
    void setPeerMachineId(const QString &peerMachineId);

    TransferStatus status() const;
    void setStatus(TransferStatus status);

    QDateTime createdAt() const;
    void setCreatedAt(const QDateTime &createdAt);

    bool isValid() const;

private:
    int m_id = -1;
    QString m_senderUuid = QStringLiteral("");
    QString m_recipientUuid = QStringLiteral("");
    QString m_fileName = QStringLiteral("");
    qint64 m_fileSize = 0;
    QString m_filePath = QStringLiteral("");
    QString m_peerAddress = QStringLiteral("");
    QString m_peerName = QStringLiteral("");
    QString m_peerMachineId = QStringLiteral("");
    TransferStatus m_status = TransferStatus::Pending;
    QDateTime m_createdAt;
};

} // namespace models

Q_DECLARE_METATYPE(models::TransferStatus)
Q_DECLARE_METATYPE(models::Transfer)

#endif // MODELS_TRANSFER_H
