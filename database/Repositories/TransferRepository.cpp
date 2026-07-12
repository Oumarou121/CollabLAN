#include "TransferRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>

namespace database {

TransferRepository::TransferRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

TransferRepository::~TransferRepository() = default;

models::Transfer TransferRepository::transferFromQuery(const QSqlQuery &query) const
{
    models::Transfer transfer;
    transfer.setId(query.value(QStringLiteral("id")).toInt());
    // sender_uuid/recipient_uuid (migration #017, colonnes sender_id/
    // recipient_id supprimees) : chaine vide si NULL, un poste reseau
    // sans compte utilisateur associe n'a pas d'UUID a restituer.
    transfer.setSenderUuid(query.value(QStringLiteral("sender_uuid")).toString());
    transfer.setRecipientUuid(query.value(QStringLiteral("recipient_uuid")).toString());
    transfer.setFileName(query.value(QStringLiteral("file_name")).toString());
    transfer.setFileSize(query.value(QStringLiteral("file_size")).toLongLong());
    transfer.setFilePath(query.value(QStringLiteral("file_path")).toString());
    transfer.setPeerAddress(query.value(QStringLiteral("peer_address")).toString());
    transfer.setPeerName(query.value(QStringLiteral("peer_name")).toString());
    // peer_machine_id (migration #016) : identifiant le plus fiable du
    // correspondant, present pour la quasi-totalite des transferts LAN via
    // decouverte contrairement a sender_id/recipient_id.
    transfer.setPeerMachineId(query.value(QStringLiteral("peer_machine_id")).toString());
    transfer.setStatus(models::transferStatusFromString(query.value(QStringLiteral("status")).toString()));
    transfer.setCreatedAt(query.value(QStringLiteral("created_at")).toDateTime());
    return transfer;
}

int TransferRepository::create(const models::Transfer &transfer)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO Transfers (sender_uuid, recipient_uuid, file_name, file_size, file_path, "
        "peer_address, peer_name, peer_machine_id, status) "
        "VALUES (:sender_uuid, :recipient_uuid, :file_name, :file_size, :file_path, "
        ":peer_address, :peer_name, :peer_machine_id, :status)"));
    // Chaine vide signifie "inconnu" (voir models::Transfer) : on le
    // stocke en NULL, aucune contrainte de cle etrangere sur ces colonnes
    // (meme logique que peer_address/peer_name, migration #017).
    query.bindValue(QStringLiteral(":sender_uuid"),
                     transfer.senderUuid().isEmpty() ? QVariant() : QVariant(transfer.senderUuid()));
    query.bindValue(QStringLiteral(":recipient_uuid"),
                     transfer.recipientUuid().isEmpty() ? QVariant() : QVariant(transfer.recipientUuid()));
    query.bindValue(QStringLiteral(":file_name"), transfer.fileName());
    query.bindValue(QStringLiteral(":file_size"), transfer.fileSize());
    query.bindValue(QStringLiteral(":file_path"),
                     transfer.filePath().isEmpty() ? QVariant() : QVariant(transfer.filePath()));
    query.bindValue(QStringLiteral(":peer_address"),
                     transfer.peerAddress().isEmpty() ? QVariant() : QVariant(transfer.peerAddress()));
    query.bindValue(QStringLiteral(":peer_name"),
                     transfer.peerName().isEmpty() ? QVariant() : QVariant(transfer.peerName()));
    query.bindValue(QStringLiteral(":peer_machine_id"),
                     transfer.peerMachineId().isEmpty() ? QVariant() : QVariant(transfer.peerMachineId()));
    query.bindValue(QStringLiteral(":status"), models::transferStatusToString(transfer.status()));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return -1;
    }
    return query.lastInsertId().toInt();
}

std::optional<models::Transfer> TransferRepository::findById(int id) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM Transfers WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return transferFromQuery(query);
}

std::vector<models::Transfer> TransferRepository::findAll() const
{
    std::vector<models::Transfer> transfers;
    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT * FROM Transfers ORDER BY created_at DESC"))) {
        m_lastError = query.lastError().text();
        return transfers;
    }
    while (query.next()) {
        transfers.push_back(transferFromQuery(query));
    }
    return transfers;
}

std::vector<models::Transfer> TransferRepository::findByUser(const QString &userUuid) const
{
    std::vector<models::Transfer> transfers;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM Transfers WHERE sender_uuid = :user_uuid OR recipient_uuid = :user_uuid "
        "ORDER BY created_at DESC"));
    query.bindValue(QStringLiteral(":user_uuid"), userUuid);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return transfers;
    }
    while (query.next()) {
        transfers.push_back(transferFromQuery(query));
    }
    return transfers;
}

bool TransferRepository::updateStatus(int id, models::TransferStatus status)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("UPDATE Transfers SET status = :status WHERE id = :id"));
    query.bindValue(QStringLiteral(":status"), models::transferStatusToString(status));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool TransferRepository::updateFilePath(int id, const QString &filePath)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("UPDATE Transfers SET file_path = :file_path WHERE id = :id"));
    query.bindValue(QStringLiteral(":file_path"), filePath.isEmpty() ? QVariant() : QVariant(filePath));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool TransferRepository::remove(int id)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM Transfers WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

QString TransferRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
