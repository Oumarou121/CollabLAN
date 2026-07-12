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
    // sender_id/recipient_id sont nullables depuis la migration #012 (poste
    // reseau sans compte utilisateur associe) : NULL est restitue comme -1,
    // le sentinel "inconnu" deja utilise partout ailleurs dans le code.
    const QVariant senderId = query.value(QStringLiteral("sender_id"));
    transfer.setSenderId(senderId.isNull() ? -1 : senderId.toInt());
    const QVariant recipientId = query.value(QStringLiteral("recipient_id"));
    transfer.setRecipientId(recipientId.isNull() ? -1 : recipientId.toInt());
    transfer.setFileName(query.value(QStringLiteral("file_name")).toString());
    transfer.setFileSize(query.value(QStringLiteral("file_size")).toLongLong());
    transfer.setFilePath(query.value(QStringLiteral("file_path")).toString());
    transfer.setPeerAddress(query.value(QStringLiteral("peer_address")).toString());
    transfer.setPeerName(query.value(QStringLiteral("peer_name")).toString());
    transfer.setStatus(models::transferStatusFromString(query.value(QStringLiteral("status")).toString()));
    transfer.setCreatedAt(query.value(QStringLiteral("created_at")).toDateTime());
    return transfer;
}

int TransferRepository::create(const models::Transfer &transfer)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO Transfers (sender_id, recipient_id, file_name, file_size, file_path, "
        "peer_address, peer_name, status) "
        "VALUES (:sender_id, :recipient_id, :file_name, :file_size, :file_path, "
        ":peer_address, :peer_name, :status)"));
    // -1 (ou toute valeur <= 0) signifie "inconnu" (voir models::Transfer) :
    // on le stocke en NULL plutot que -1 pour respecter la contrainte de
    // cle etrangere REFERENCES Users(id), qui n'a pas de ligne id = -1.
    if (transfer.senderId() > 0) {
        query.bindValue(QStringLiteral(":sender_id"), transfer.senderId());
    } else {
        query.bindValue(QStringLiteral(":sender_id"), QVariant());
    }
    if (transfer.recipientId() > 0) {
        query.bindValue(QStringLiteral(":recipient_id"), transfer.recipientId());
    } else {
        query.bindValue(QStringLiteral(":recipient_id"), QVariant());
    }
    query.bindValue(QStringLiteral(":file_name"), transfer.fileName());
    query.bindValue(QStringLiteral(":file_size"), transfer.fileSize());
    query.bindValue(QStringLiteral(":file_path"),
                     transfer.filePath().isEmpty() ? QVariant() : QVariant(transfer.filePath()));
    query.bindValue(QStringLiteral(":peer_address"),
                     transfer.peerAddress().isEmpty() ? QVariant() : QVariant(transfer.peerAddress()));
    query.bindValue(QStringLiteral(":peer_name"),
                     transfer.peerName().isEmpty() ? QVariant() : QVariant(transfer.peerName()));
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

std::vector<models::Transfer> TransferRepository::findByUser(int userId) const
{
    std::vector<models::Transfer> transfers;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM Transfers WHERE sender_id = :user_id OR recipient_id = :user_id "
        "ORDER BY created_at DESC"));
    query.bindValue(QStringLiteral(":user_id"), userId);

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
