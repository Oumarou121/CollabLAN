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
              int senderId,
              int recipientId,
              QString fileName,
              qint64 fileSize,
              TransferStatus status,
              QDateTime createdAt = QDateTime::currentDateTimeUtc());
    ~Transfer();

    int id() const;
    void setId(int id);

    int senderId() const;
    void setSenderId(int senderId);

    int recipientId() const;
    void setRecipientId(int recipientId);

    QString fileName() const;
    void setFileName(const QString &fileName);

    qint64 fileSize() const;
    void setFileSize(qint64 fileSize);

    TransferStatus status() const;
    void setStatus(TransferStatus status);

    QDateTime createdAt() const;
    void setCreatedAt(const QDateTime &createdAt);

    bool isValid() const;

private:
    int m_id = -1;
    int m_senderId = -1;
    int m_recipientId = -1;
    QString m_fileName = QStringLiteral("");
    qint64 m_fileSize = 0;
    TransferStatus m_status = TransferStatus::Pending;
    QDateTime m_createdAt;
};

} // namespace models

Q_DECLARE_METATYPE(models::TransferStatus)
Q_DECLARE_METATYPE(models::Transfer)

#endif // MODELS_TRANSFER_H
