#include "SyncOperationRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>

namespace database {

SyncOperationRepository::SyncOperationRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

SyncOperationRepository::~SyncOperationRepository() = default;

models::SyncOperation SyncOperationRepository::operationFromQuery(const QSqlQuery &query) const
{
    models::SyncOperation operation;
    operation.setId(query.value(QStringLiteral("id")).toInt());
    operation.setType(models::syncOperationTypeFromString(query.value(QStringLiteral("type")).toString()));
    operation.setFileId(query.value(QStringLiteral("file_id")).toInt());
    operation.setVersion(query.value(QStringLiteral("version")).toInt());
    operation.setMachineId(query.value(QStringLiteral("machine_id")).toString());
    operation.setDate(query.value(QStringLiteral("created_at")).toDateTime());
    return operation;
}

int SyncOperationRepository::create(const models::SyncOperation &operation)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO SyncOperations (type, file_id, version, machine_id) "
        "VALUES (:type, :file_id, :version, :machine_id)"));
    query.bindValue(QStringLiteral(":type"), models::syncOperationTypeToString(operation.type()));
    query.bindValue(QStringLiteral(":file_id"), operation.fileId());
    query.bindValue(QStringLiteral(":version"), operation.version());
    query.bindValue(QStringLiteral(":machine_id"), operation.machineId());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return -1;
    }
    return query.lastInsertId().toInt();
}

std::vector<models::SyncOperation> SyncOperationRepository::findByFile(int fileId) const
{
    std::vector<models::SyncOperation> operations;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM SyncOperations WHERE file_id = :file_id ORDER BY created_at ASC"));
    query.bindValue(QStringLiteral(":file_id"), fileId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return operations;
    }
    while (query.next()) {
        operations.push_back(operationFromQuery(query));
    }
    return operations;
}

std::vector<models::SyncOperation> SyncOperationRepository::findSince(const QDateTime &since) const
{
    std::vector<models::SyncOperation> operations;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM SyncOperations WHERE created_at > :since ORDER BY created_at ASC"));
    query.bindValue(QStringLiteral(":since"), since.toUTC());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return operations;
    }
    while (query.next()) {
        operations.push_back(operationFromQuery(query));
    }
    return operations;
}

std::vector<models::SyncOperation> SyncOperationRepository::findRecentByFolder(int folderId, int limit) const
{
    std::vector<models::SyncOperation> operations;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT SyncOperations.* FROM SyncOperations "
        "JOIN SharedFiles ON SharedFiles.id = SyncOperations.file_id "
        "WHERE SharedFiles.folder_id = :folder_id "
        "ORDER BY SyncOperations.created_at DESC LIMIT :limit"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);
    query.bindValue(QStringLiteral(":limit"), limit);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return operations;
    }
    while (query.next()) {
        operations.push_back(operationFromQuery(query));
    }
    return operations;
}

QString SyncOperationRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
