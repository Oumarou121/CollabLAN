#include "SharedFolderRepository.h"

#include <QSqlError>
#include <QSqlQuery>
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
    folder.setId(query.value(QStringLiteral("id")).toInt());
    folder.setName(query.value(QStringLiteral("name")).toString());
    folder.setLocalPath(query.value(QStringLiteral("local_path")).toString());
    folder.setOwnerId(query.value(QStringLiteral("owner_id")).toInt());
    folder.setCreatedAt(query.value(QStringLiteral("created_at")).toDateTime());
    folder.setIsActive(query.value(QStringLiteral("is_active")).toInt() != 0);
    return folder;
}

int SharedFolderRepository::create(const models::SharedFolder &folder)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO SharedFolders (name, local_path, owner_id, is_active) "
        "VALUES (:name, :local_path, :owner_id, :is_active)"));
    query.bindValue(QStringLiteral(":name"), folder.name());
    query.bindValue(QStringLiteral(":local_path"), folder.localPath());
    query.bindValue(QStringLiteral(":owner_id"), folder.ownerId());
    query.bindValue(QStringLiteral(":is_active"), folder.isActive() ? 1 : 0);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return -1;
    }
    return query.lastInsertId().toInt();
}

std::optional<models::SharedFolder> SharedFolderRepository::findById(int id) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM SharedFolders WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return folderFromQuery(query);
}

bool SharedFolderRepository::update(const models::SharedFolder &folder)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE SharedFolders SET name = :name, local_path = :local_path, "
        "owner_id = :owner_id, is_active = :is_active WHERE id = :id"));
    query.bindValue(QStringLiteral(":name"), folder.name());
    query.bindValue(QStringLiteral(":local_path"), folder.localPath());
    query.bindValue(QStringLiteral(":owner_id"), folder.ownerId());
    query.bindValue(QStringLiteral(":is_active"), folder.isActive() ? 1 : 0);
    query.bindValue(QStringLiteral(":id"), folder.id());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool SharedFolderRepository::remove(int id)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM SharedFolders WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

std::vector<models::SharedFolder> SharedFolderRepository::findAll() const
{
    std::vector<models::SharedFolder> folders;
    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT * FROM SharedFolders ORDER BY name COLLATE NOCASE"))) {
        m_lastError = query.lastError().text();
        return folders;
    }
    while (query.next()) {
        folders.push_back(folderFromQuery(query));
    }
    return folders;
}

std::vector<models::SharedFolder> SharedFolderRepository::findActive() const
{
    std::vector<models::SharedFolder> folders;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM SharedFolders WHERE is_active = 1 ORDER BY name COLLATE NOCASE"));
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return folders;
    }
    while (query.next()) {
        folders.push_back(folderFromQuery(query));
    }
    return folders;
}

bool SharedFolderRepository::existsByLocalPath(const QString &localPath) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT COUNT(*) FROM SharedFolders WHERE local_path = :local_path"));
    query.bindValue(QStringLiteral(":local_path"), localPath);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    if (query.next()) {
        return query.value(0).toInt() > 0;
    }
    return false;
}

QString SharedFolderRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
