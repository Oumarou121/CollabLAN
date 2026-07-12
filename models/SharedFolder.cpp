#include "SharedFolder.h"

namespace models {

SharedFolder::SharedFolder()
    : m_createdAt(QDateTime::currentDateTimeUtc())
{
}

SharedFolder::SharedFolder(int id,
                           QString name,
                           QString localPath,
                           int ownerId,
                           bool isActive,
                           QDateTime createdAt)
    : m_id(id)
    , m_name(std::move(name))
    , m_localPath(std::move(localPath))
    , m_ownerId(ownerId)
    , m_isActive(isActive)
    , m_createdAt(std::move(createdAt))
{
}

int SharedFolder::id() const { return m_id; }
void SharedFolder::setId(int id) { m_id = id; }

QString SharedFolder::name() const { return m_name; }
void SharedFolder::setName(const QString &name) { m_name = name; }

QString SharedFolder::localPath() const { return m_localPath; }
void SharedFolder::setLocalPath(const QString &localPath) { m_localPath = localPath; }

int SharedFolder::ownerId() const { return m_ownerId; }
void SharedFolder::setOwnerId(int ownerId) { m_ownerId = ownerId; }

QDateTime SharedFolder::createdAt() const { return m_createdAt; }
void SharedFolder::setCreatedAt(const QDateTime &createdAt) { m_createdAt = createdAt; }

bool SharedFolder::isActive() const { return m_isActive; }
void SharedFolder::setIsActive(bool isActive) { m_isActive = isActive; }

bool SharedFolder::isValid() const
{
    return m_id >= 0 && !m_name.isEmpty() && !m_localPath.isEmpty();
}

} // namespace models
