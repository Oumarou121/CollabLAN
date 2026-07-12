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
    return folder;
}

std::optional<models::SharedFolder> SharedFolderRepository::insert(const models::SharedFolder &folder)
{
    const QString uuid = folder.uuid().isEmpty()
        ? QUuid::createUuid().toString(QUuid::WithoutBraces)
        : folder.uuid();

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO SharedFolders (uuid, name, local_path, owner_id, is_active) "
        "VALUES (:uuid, :name, :local_path, :owner_id, :is_active)"));
    query.bindValue(QStringLiteral(":uuid"), uuid);
    query.bindValue(QStringLiteral(":name"), folder.name());
    query.bindValue(QStringLiteral(":local_path"), folder.localPath());
    query.bindValue(QStringLiteral(":owner_id"),
                     folder.ownerId() > 0 ? QVariant(folder.ownerId()) : QVariant());
    query.bindValue(QStringLiteral(":is_active"), folder.isActive() ? 1 : 0);

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
        "is_active = :is_active WHERE id = :id"));
    query.bindValue(QStringLiteral(":name"), folder.name());
    query.bindValue(QStringLiteral(":local_path"), folder.localPath());
    query.bindValue(QStringLiteral(":is_active"), folder.isActive() ? 1 : 0);
    query.bindValue(QStringLiteral(":id"), folder.id());

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

QString SharedFolderRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
