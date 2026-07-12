#include "SharedFolder.h"

namespace models {

SharedFolder::SharedFolder()
{
}

SharedFolder::SharedFolder(qint64 id, QString name, QString localPath)
    : m_id(id)
    , m_name(std::move(name))
    , m_localPath(std::move(localPath))
{
}

} // namespace models
