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
    file.setId(query.value(QStringLiteral("id")).toLongLong());
    file.setFolderId(query.value(QStringLiteral("folder_id")).toLongLong());
    file.setRelativePath(query.value(QStringLiteral("relative_path")).toString());
    file.setHash(query.value(QStringLiteral("hash")).toString());
    file.setSize(query.value(QStringLiteral("size")).toLongLong());
    file.setLastModified(query.value(QStringLiteral("last_modified")).toDateTime());
    file.setVersion(query.value(QStringLiteral("version")).toInt());
    file.setDeleted(query.value(QStringLiteral("deleted")).toInt() != 0);
    file.setPendingDownload(query.value(QStringLiteral("pending_download")).toInt() != 0);
    file.setSyncedHash(query.value(QStringLiteral("synced_hash")).toString());
    return file;
}

std::optional<models::SharedFile> SharedFileRepository::upsert(const models::SharedFile &file)
{
    const auto existing = findByRelativePath(file.folderId(), file.relativePath());

    QSqlQuery query(m_db);
    if (existing.has_value()) {
        // Le contenu n'a change que si le hash differe : on evite
        // d'incrementer version() a chaque reindexation identique.
        const int nextVersion = (existing->hash() != file.hash())
            ? existing->version() + 1
            : existing->version();

        query.prepare(QStringLiteral(
            "UPDATE SharedFiles SET hash = :hash, size = :size, "
            "last_modified = :last_modified, version = :version, deleted = 0, "
            "pending_download = :pending_download "
            "WHERE id = :id"));
        query.bindValue(QStringLiteral(":hash"), file.hash());
        query.bindValue(QStringLiteral(":size"), file.size());
        query.bindValue(QStringLiteral(":last_modified"), file.lastModified().toUTC().toString(Qt::ISODate));
        query.bindValue(QStringLiteral(":version"), nextVersion);
        query.bindValue(QStringLiteral(":pending_download"), file.pendingDownload() ? 1 : 0);
        query.bindValue(QStringLiteral(":id"), existing->id());

        if (!query.exec()) {
            m_lastError = query.lastError().text();
            return std::nullopt;
        }
        return getById(existing->id());
    }

    query.prepare(QStringLiteral(
        "INSERT INTO SharedFiles (folder_id, relative_path, hash, size, last_modified, version, deleted, pending_download) "
        "VALUES (:folder_id, :relative_path, :hash, :size, :last_modified, :version, 0, :pending_download)"));
    query.bindValue(QStringLiteral(":folder_id"), file.folderId());
    query.bindValue(QStringLiteral(":relative_path"), file.relativePath());
    query.bindValue(QStringLiteral(":hash"), file.hash());
    query.bindValue(QStringLiteral(":size"), file.size());
    query.bindValue(QStringLiteral(":last_modified"), file.lastModified().toUTC().toString(Qt::ISODate));
    query.bindValue(QStringLiteral(":version"), file.version() > 0 ? file.version() : 1);
    query.bindValue(QStringLiteral(":pending_download"), file.pendingDownload() ? 1 : 0);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    return getById(query.lastInsertId().toLongLong());
}

bool SharedFileRepository::remove(qint64 fileId)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM SharedFiles WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), fileId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool SharedFileRepository::markDeleted(qint64 folderId, const QString &relativePath)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE SharedFiles SET deleted = 1 WHERE folder_id = :folder_id AND relative_path = :relative_path"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);
    query.bindValue(QStringLiteral(":relative_path"), relativePath);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool SharedFileRepository::renameFile(qint64 folderId,
                                       const QString &oldPath,
                                       const QString &newPath)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE SharedFiles SET relative_path = :new_path "
        "WHERE folder_id = :folder_id AND relative_path = :old_path"));
    query.bindValue(QStringLiteral(":new_path"),   newPath);
    query.bindValue(QStringLiteral(":folder_id"),  folderId);
    query.bindValue(QStringLiteral(":old_path"),   oldPath);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

std::optional<models::SharedFile> SharedFileRepository::getById(qint64 fileId) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM SharedFiles WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), fileId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return fileFromQuery(query);
}

std::optional<models::SharedFile> SharedFileRepository::findByRelativePath(qint64 folderId, const QString &relativePath) const
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

QVector<models::SharedFile> SharedFileRepository::getByFolderId(qint64 folderId) const
{
    QVector<models::SharedFile> files;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM SharedFiles WHERE folder_id = :folder_id AND deleted = 0 "
        "ORDER BY relative_path ASC"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return files;
    }
    while (query.next()) {
        files.append(fileFromQuery(query));
    }
    return files;
}

int SharedFileRepository::count(qint64 folderId) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT COUNT(*) FROM SharedFiles WHERE folder_id = :folder_id AND deleted = 0"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);

    if (!query.exec() || !query.next()) {
        m_lastError = query.lastError().text();
        return 0;
    }
    return query.value(0).toInt();
}

QString SharedFileRepository::lastError() const
{
    return m_lastError;
}

bool SharedFileRepository::setSyncedHash(qint64 folderId, const QString &relativePath, const QString &hash)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE SharedFiles SET synced_hash = :hash WHERE folder_id = :folder_id AND relative_path = :relative_path"));
    query.bindValue(QStringLiteral(":hash"), hash);
    query.bindValue(QStringLiteral(":folder_id"), folderId);
    query.bindValue(QStringLiteral(":relative_path"), relativePath);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

} // namespace database
