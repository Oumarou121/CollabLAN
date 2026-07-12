#include "SharedFile.h"

namespace models {

SharedFile::SharedFile()
    : m_lastModified(QDateTime::currentDateTimeUtc())
{
}

SharedFile::SharedFile(int id,
                       int folderId,
                       QString relativePath,
                       QString hash,
                       qint64 size,
                       QDateTime lastModified,
                       int version,
                       bool deleted)
    : m_id(id)
    , m_folderId(folderId)
    , m_relativePath(std::move(relativePath))
    , m_hash(std::move(hash))
    , m_size(size)
    , m_lastModified(std::move(lastModified))
    , m_version(version)
    , m_deleted(deleted)
{
}

int SharedFile::id() const { return m_id; }
void SharedFile::setId(int id) { m_id = id; }

int SharedFile::folderId() const { return m_folderId; }
void SharedFile::setFolderId(int folderId) { m_folderId = folderId; }

QString SharedFile::relativePath() const { return m_relativePath; }
void SharedFile::setRelativePath(const QString &relativePath) { m_relativePath = relativePath; }

QString SharedFile::hash() const { return m_hash; }
void SharedFile::setHash(const QString &hash) { m_hash = hash; }

qint64 SharedFile::size() const { return m_size; }
void SharedFile::setSize(qint64 size) { m_size = size; }

QDateTime SharedFile::lastModified() const { return m_lastModified; }
void SharedFile::setLastModified(const QDateTime &lastModified) { m_lastModified = lastModified; }

int SharedFile::version() const { return m_version; }
void SharedFile::setVersion(int version) { m_version = version; }

bool SharedFile::deleted() const { return m_deleted; }
void SharedFile::setDeleted(bool deleted) { m_deleted = deleted; }

bool SharedFile::isValid() const
{
    return m_id >= 0 && m_folderId >= 0 && !m_relativePath.isEmpty();
}

} // namespace models
