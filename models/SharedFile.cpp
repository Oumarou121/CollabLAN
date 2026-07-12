#include "SharedFile.h"

namespace models {

SharedFile::SharedFile()
{
}

SharedFile::SharedFile(qint64 id, qint64 folderId, QString relativePath)
    : m_id(id)
    , m_folderId(folderId)
    , m_relativePath(std::move(relativePath))
{
}

} // namespace models
