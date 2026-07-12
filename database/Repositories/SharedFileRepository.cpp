#include "SharedFileRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>

namespace database {

SharedFileRepository::SharedFileRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

SharedFileRepository::~SharedFileRepository() = default;

models::SharedFile SharedFileRepository::fileFromQuery(const QSqlQuery &query) const
{
    models::SharedFile file;
    file.setId(query.value(QStringLiteral("id")).toInt());
    file.setFolderId(query.value(QStringLiteral("folder_id")).toInt());
    file.setRelativePath(query.value(QStringLiteral("relative_path")).toString());
    file.setHash(query.value(QStringLiteral("hash")).toString());
    file.setSize(query.value(QStringLiteral("size")).toLongLong());
    file.setLastModified(query.value(QStringLiteral("last_modified")).toDateTime());
    file.setVersion(query.value(QStringLiteral("version")).toInt());
    file.setDeleted(query.value(QStringLiteral("deleted")).toInt() != 0);
    return file;
}

int SharedFileRepository::create(const models::SharedFile &file)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO SharedFiles (folder_id, relative_path, hash, size, last_modified, version, deleted) "
        "VALUES (:folder_id, :relative_path, :hash, :size, :last_modified, :version, :deleted)"));
    query.bindValue(QStringLiteral(":folder_id"), file.folderId());
    query.bindValue(QStringLiteral(":relative_path"), file.relativePath());
    query.bindValue(QStringLiteral(":hash"), file.hash().isNull() ? QStringLiteral("") : file.hash());
    query.bindValue(QStringLiteral(":size"), file.size());
    query.bindValue(QStringLiteral(":last_modified"), file.lastModified().toUTC());
    query.bindValue(QStringLiteral(":version"), file.version());
    query.bindValue(QStringLiteral(":deleted"), file.deleted() ? 1 : 0);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return -1;
    }
    return query.lastInsertId().toInt();
}

std::optional<models::SharedFile> SharedFileRepository::findById(int id) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM SharedFiles WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return fileFromQuery(query);
}

bool SharedFileRepository::update(const models::SharedFile &file)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE SharedFiles SET folder_id = :folder_id, relative_path = :relative_path, "
        "hash = :hash, size = :size, last_modified = :last_modified, version = :version, "
        "deleted = :deleted WHERE id = :id"));
    query.bindValue(QStringLiteral(":folder_id"), file.folderId());
    query.bindValue(QStringLiteral(":relative_path"), file.relativePath());
    query.bindValue(QStringLiteral(":hash"), file.hash().isNull() ? QStringLiteral("") : file.hash());
    query.bindValue(QStringLiteral(":size"), file.size());
    query.bindValue(QStringLiteral(":last_modified"), file.lastModified().toUTC());
    query.bindValue(QStringLiteral(":version"), file.version());
    query.bindValue(QStringLiteral(":deleted"), file.deleted() ? 1 : 0);
    query.bindValue(QStringLiteral(":id"), file.id());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool SharedFileRepository::remove(int id)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM SharedFiles WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

std::optional<models::SharedFile> SharedFileRepository::findByFolderAndPath(int folderId, const QString &relativePath) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM SharedFiles WHERE folder_id = :folder_id AND relative_path = :relative_path"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);
    query.bindValue(QStringLiteral(":relative_path"), relativePath);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return fileFromQuery(query);
}

std::vector<models::SharedFile> SharedFileRepository::findByFolder(int folderId, bool includeDeleted) const
{
    std::vector<models::SharedFile> files;
    QSqlQuery query(m_db);
    const QString sql = includeDeleted
        ? QStringLiteral("SELECT * FROM SharedFiles WHERE folder_id = :folder_id ORDER BY relative_path COLLATE NOCASE")
        : QStringLiteral("SELECT * FROM SharedFiles WHERE folder_id = :folder_id AND deleted = 0 ORDER BY relative_path COLLATE NOCASE");
    query.prepare(sql);
    query.bindValue(QStringLiteral(":folder_id"), folderId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return files;
    }
    while (query.next()) {
        files.push_back(fileFromQuery(query));
    }
    return files;
}

int SharedFileRepository::countActiveByFolder(int folderId) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT COUNT(*) FROM SharedFiles WHERE folder_id = :folder_id AND deleted = 0"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return 0;
    }
    if (query.next()) {
        return query.value(0).toInt();
    }
    return 0;
}

QString SharedFileRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
