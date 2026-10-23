#include "SyncOperationRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>
#include <QVariant>

namespace database {

SyncOperationRepository::SyncOperationRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

SyncOperationRepository::~SyncOperationRepository() = default;

models::FileSyncOperation SyncOperationRepository::operationFromQuery(const QSqlQuery &query) const
{
    // Enregistrement lu une fois par ligne : value(nom) le reconstruisait a chaque colonne.
    const QSqlRecord rec = query.record();
    models::FileSyncOperation operation;
    operation.setId(query.value(rec.indexOf(QLatin1String("id"))).toLongLong());
    operation.setType(models::syncChangeTypeFromString(query.value(rec.indexOf(QLatin1String("type"))).toString()));
    operation.setFileId(query.value(rec.indexOf(QLatin1String("file_id"))).toLongLong());
    operation.setOldRelativePath(query.value(rec.indexOf(QLatin1String("old_relative_path"))).toString());
    operation.setVersion(query.value(rec.indexOf(QLatin1String("version"))).toInt());
    operation.setMachineId(query.value(rec.indexOf(QLatin1String("machine_id"))).toString());
    operation.setCreatedAt(query.value(rec.indexOf(QLatin1String("created_at"))).toDateTime());
    operation.setBaseHash(query.value(rec.indexOf(QLatin1String("base_hash"))).toString());
    operation.setAuthorUuid(query.value(rec.indexOf(QLatin1String("author_uuid"))).toString());
    return operation;
}

std::optional<models::FileSyncOperation> SyncOperationRepository::insert(const models::FileSyncOperation &operation)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO SyncOperations (type, file_id, old_relative_path, version, machine_id, base_hash, author_uuid) "
        "VALUES (:type, :file_id, :old_relative_path, :version, :machine_id, :base_hash, :author_uuid)"));
    query.bindValue(QStringLiteral(":type"), models::syncChangeTypeToString(operation.type()));
    query.bindValue(QStringLiteral(":file_id"), operation.fileId());
    if (operation.oldRelativePath().isEmpty()) {
        query.bindValue(QStringLiteral(":old_relative_path"), QVariant(QMetaType(QMetaType::QString)));
    } else {
        query.bindValue(QStringLiteral(":old_relative_path"), operation.oldRelativePath());
    }
    query.bindValue(QStringLiteral(":version"), operation.version());
    query.bindValue(QStringLiteral(":machine_id"), operation.machineId());
    query.bindValue(QStringLiteral(":base_hash"), operation.baseHash());
    query.bindValue(QStringLiteral(":author_uuid"), operation.authorUuid());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }

    QSqlQuery fetch(m_db);
    fetch.prepare(QStringLiteral("SELECT * FROM SyncOperations WHERE id = :id"));
    fetch.bindValue(QStringLiteral(":id"), query.lastInsertId().toLongLong());
    if (!fetch.exec() || !fetch.next()) {
        m_lastError = fetch.lastError().text();
        return std::nullopt;
    }
    return operationFromQuery(fetch);
}

QVector<models::FileSyncOperation> SyncOperationRepository::getByFolderId(qint64 folderId, int limit) const
{
    QVector<models::FileSyncOperation> operations;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT so.*, sf.relative_path AS shared_relative_path FROM SyncOperations so "
        "JOIN SharedFiles sf ON sf.id = so.file_id "
        "WHERE sf.folder_id = :folder_id "
        "ORDER BY so.id DESC LIMIT :limit"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);
    query.bindValue(QStringLiteral(":limit"), limit);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return operations;
    }
    while (query.next()) {
        models::FileSyncOperation operation = operationFromQuery(query);
        operation.setRelativePath(query.value(QStringLiteral("shared_relative_path")).toString());
        operations.append(operation);
    }
    return operations;
}

QVector<models::FileSyncOperation> SyncOperationRepository::getLatestPerFileByFolderId(qint64 folderId, int limit) const
{
    QVector<models::FileSyncOperation> operations;
    QSqlQuery query(m_db);
    // Pour chaque file_id du dossier, ne garder que la ligne dont l'id est
    // le MAX(so2.id) parmi toutes les operations connues pour CE fichier
    // (sous-requete correlee, appuyee par l'index idx_sync_operations_file_id
    // deja present depuis la migration 020/023) -- c'est litteralement l'etat
    // le plus recent de ce fichier, quel que soit le nombre d'evenements
    // intermediaires. Un dossier avec 30 fichiers reedites 500 fois chacun
    // renvoie ici 30 lignes, pas 15000 : c'est la difference structurelle
    // avec getByFolderId(), dont le LIMIT porte sur le nombre d'EVENEMENTS.
    query.prepare(QStringLiteral(
        "SELECT so.*, sf.relative_path AS shared_relative_path FROM SyncOperations so "
        "JOIN SharedFiles sf ON sf.id = so.file_id "
        "WHERE sf.folder_id = :folder_id "
        "AND so.id = (SELECT MAX(so2.id) FROM SyncOperations so2 WHERE so2.file_id = so.file_id) "
        "ORDER BY so.id DESC LIMIT :limit"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);
    query.bindValue(QStringLiteral(":limit"), limit);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return operations;
    }
    while (query.next()) {
        models::FileSyncOperation operation = operationFromQuery(query);
        operation.setRelativePath(query.value(QStringLiteral("shared_relative_path")).toString());
        operations.append(operation);
    }
    return operations;
}

QVector<models::FileSyncOperation> SyncOperationRepository::getSinceId(qint64 sinceId, int limit) const
{
    QVector<models::FileSyncOperation> operations;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM SyncOperations WHERE id > :since_id ORDER BY id ASC LIMIT :limit"));
    query.bindValue(QStringLiteral(":since_id"), sinceId);
    query.bindValue(QStringLiteral(":limit"), limit);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return operations;
    }
    while (query.next()) {
        operations.append(operationFromQuery(query));
    }
    return operations;
}

qint64 SyncOperationRepository::latestId() const
{
    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT MAX(id) FROM SyncOperations")) || !query.next()) {
        m_lastError = query.lastError().text();
        return 0;
    }
    return query.value(0).toLongLong();
}

QString SyncOperationRepository::lastError() const
{
    return m_lastError;
}

} // namespace database