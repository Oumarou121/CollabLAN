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
    transfer.setSenderId(query.value(QStringLiteral("sender_id")).toInt());
    transfer.setRecipientId(query.value(QStringLiteral("recipient_id")).toInt());
    transfer.setFileName(query.value(QStringLiteral("file_name")).toString());
    transfer.setFileSize(query.value(QStringLiteral("file_size")).toLongLong());
    transfer.setStatus(models::transferStatusFromString(query.value(QStringLiteral("status")).toString()));
    transfer.setCreatedAt(query.value(QStringLiteral("created_at")).toDateTime());
    return transfer;
}

int TransferRepository::create(const models::Transfer &transfer)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO Transfers (sender_id, recipient_id, file_name, file_size, status) "
        "VALUES (:sender_id, :recipient_id, :file_name, :file_size, :status)"));
    query.bindValue(QStringLiteral(":sender_id"), transfer.senderId());
    query.bindValue(QStringLiteral(":recipient_id"), transfer.recipientId());
    query.bindValue(QStringLiteral(":file_name"), transfer.fileName());
    query.bindValue(QStringLiteral(":file_size"), transfer.fileSize());
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
