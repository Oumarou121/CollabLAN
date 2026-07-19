#include "SharedFolderRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QUuid>
#include <QVariant>

namespace database {

SharedFolderRepository::SharedFolderRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

SharedFolderRepository::~SharedFolderRepository() = default;

models::SharedFolder SharedFolderRepository::folderFromQuery(const QSqlQuery &query) const
{
    models::SharedFolder folder;
    folder.setId(query.value(QStringLiteral("id")).toLongLong());
    folder.setUuid(query.value(QStringLiteral("uuid")).toString());
    folder.setName(query.value(QStringLiteral("name")).toString());
    folder.setLocalPath(query.value(QStringLiteral("local_path")).toString());
    const QVariant ownerId = query.value(QStringLiteral("owner_id"));
    folder.setOwnerId(ownerId.isNull() ? 0 : ownerId.toLongLong());
    folder.setCreatedAt(query.value(QStringLiteral("created_at")).toDateTime());
    folder.setIsActive(query.value(QStringLiteral("is_active")).toInt() != 0);
    folder.setOriginMachineId(query.value(QStringLiteral("origin_machine_id")).toString());
    folder.setExcludePatterns(query.value(QStringLiteral("exclude_patterns")).toString());
    return folder;
}

std::optional<models::SharedFolder> SharedFolderRepository::insert(const models::SharedFolder &folder)
{
    const QString uuid = folder.uuid().isEmpty()
        ? QUuid::createUuid().toString(QUuid::WithoutBraces)
        : folder.uuid();

    QSqlQuery query(m_db);
    if (!query.prepare(QStringLiteral(
        "INSERT INTO SharedFolders (uuid, name, local_path, owner_id, is_active, origin_machine_id, exclude_patterns) "
        "VALUES (:uuid, :name, :local_path, :owner_id, :is_active, :origin_machine_id, :exclude_patterns)"))) {
        // Si prepare() echoue (ex: schema en base desynchronise du code,
        // colonne manquante...), on remonte l'erreur ici plutot que de
        // laisser bindValue()/exec() produire un message trompeur du
        // style "Parameter count mismatch" sur une requete non preparee.
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    query.bindValue(QStringLiteral(":uuid"), uuid);
    query.bindValue(QStringLiteral(":name"), folder.name());
    query.bindValue(QStringLiteral(":local_path"), folder.localPath());
    query.bindValue(QStringLiteral(":owner_id"),
                     folder.ownerId() > 0 ? QVariant(folder.ownerId()) : QVariant());
    query.bindValue(QStringLiteral(":is_active"), folder.isActive() ? 1 : 0);
    query.bindValue(QStringLiteral(":origin_machine_id"),
                     folder.originMachineId().isEmpty() ? QVariant(QVariant::String) : folder.originMachineId());
    query.bindValue(QStringLiteral(":exclude_patterns"),
                     folder.excludePatterns().isEmpty() ? QStringLiteral("") : folder.excludePatterns());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }

    return getById(query.lastInsertId().toLongLong());
}

bool SharedFolderRepository::update(const models::SharedFolder &folder)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE SharedFolders SET name = :name, local_path = :local_path, "
        "is_active = :is_active, exclude_patterns = :exclude_patterns WHERE id = :id"));
    query.bindValue(QStringLiteral(":name"), folder.name());
    query.bindValue(QStringLiteral(":local_path"), folder.localPath());
    query.bindValue(QStringLiteral(":is_active"), folder.isActive() ? 1 : 0);
    query.bindValue(QStringLiteral(":exclude_patterns"),
                     folder.excludePatterns().isEmpty() ? QStringLiteral("") : folder.excludePatterns());
    query.bindValue(QStringLiteral(":id"), folder.id());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool SharedFolderRepository::updateOriginMachineId(qint64 folderId, const QString &originMachineId)
{
    QSqlQuery query(m_db);
    if (!query.prepare(QStringLiteral(
        "UPDATE SharedFolders SET origin_machine_id = :origin_machine_id WHERE id = :id"))) {
        m_lastError = query.lastError().text();
        return false;
    }
    // QString() nulle -> NULL SQL, chaine vide -> '' : les deux se lisent
    // comme isLocalOrigin()==true cote SharedFolder (isEmpty()), donc peu
    // importe lequel est stocke ; on aligne sur insert() (NULL) par coherence.
    query.bindValue(QStringLiteral(":origin_machine_id"),
                     originMachineId.isEmpty() ? QVariant(QVariant::String) : originMachineId);
    query.bindValue(QStringLiteral(":id"), folderId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool SharedFolderRepository::remove(qint64 folderId)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM SharedFolders WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), folderId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

std::optional<models::SharedFolder> SharedFolderRepository::getById(qint64 folderId) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM SharedFolders WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), folderId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return folderFromQuery(query);
}

std::optional<models::SharedFolder> SharedFolderRepository::findByUuid(const QString &uuid) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM SharedFolders WHERE uuid = :uuid"));
    query.bindValue(QStringLiteral(":uuid"), uuid);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return folderFromQuery(query);
}

QVector<models::SharedFolder> SharedFolderRepository::getAll() const
{
    QVector<models::SharedFolder> folders;
    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral(
            "SELECT * FROM SharedFolders WHERE is_active = 1 ORDER BY created_at DESC"))) {
        m_lastError = query.lastError().text();
        return folders;
    }
    while (query.next()) {
        folders.append(folderFromQuery(query));
    }
    return folders;
}

QVector<models::SharedFolder> SharedFolderRepository::getByOwnerId(qint64 ownerId) const
{
    QVector<models::SharedFolder> folders;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM SharedFolders WHERE owner_id = :owner_id AND is_active = 1 "
        "ORDER BY created_at DESC"));
    query.bindValue(QStringLiteral(":owner_id"), ownerId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return folders;
    }
    while (query.next()) {
        folders.append(folderFromQuery(query));
    }
    return folders;
}

QVector<models::SharedFolder> SharedFolderRepository::getByIds(const QVector<qint64> &folderIds) const
{
    QVector<models::SharedFolder> folders;
    if (folderIds.isEmpty()) {
        return folders;
    }

    QStringList placeholders;
    placeholders.reserve(folderIds.size());
    for (int i = 0; i < folderIds.size(); ++i) {
        placeholders << QStringLiteral(":id%1").arg(i);
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM SharedFolders WHERE is_active = 1 AND id IN (%1) ORDER BY created_at DESC")
        .arg(placeholders.join(QStringLiteral(", "))));
    for (int i = 0; i < folderIds.size(); ++i) {
        query.bindValue(placeholders.at(i), folderIds.at(i));
    }

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return folders;
    }
    while (query.next()) {
        folders.append(folderFromQuery(query));
    }
    return folders;
}

QString SharedFolderRepository::lastError() const
{
    return m_lastError;
}

} // namespace database