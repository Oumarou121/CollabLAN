#include "SyncOperation.h"

namespace models {

QString syncOperationTypeToString(SyncOperationType type)
{
    switch (type) {
    case SyncOperationType::Create:
        return QStringLiteral("create");
    case SyncOperationType::Update:
        return QStringLiteral("update");
    case SyncOperationType::Delete:
        return QStringLiteral("delete");
    case SyncOperationType::Rename:
        return QStringLiteral("rename");
    }
    return QStringLiteral("update");
}

SyncOperationType syncOperationTypeFromString(const QString &value)
{
    const QString v = value.toLower();
    if (v == QStringLiteral("create"))
        return SyncOperationType::Create;
    if (v == QStringLiteral("delete"))
        return SyncOperationType::Delete;
    if (v == QStringLiteral("rename"))
        return SyncOperationType::Rename;
    return SyncOperationType::Update;
}

SyncOperation::SyncOperation()
    : m_date(QDateTime::currentDateTimeUtc())
{
}

SyncOperation::SyncOperation(int id,
                             SyncOperationType type,
                             int fileId,
                             int version,
                             QString machineId,
                             QDateTime date)
    : m_id(id)
    , m_type(type)
    , m_fileId(fileId)
    , m_version(version)
    , m_machineId(std::move(machineId))
    , m_date(std::move(date))
{
}

int SyncOperation::id() const { return m_id; }
void SyncOperation::setId(int id) { m_id = id; }

SyncOperationType SyncOperation::type() const { return m_type; }
void SyncOperation::setType(SyncOperationType type) { m_type = type; }

int SyncOperation::fileId() const { return m_fileId; }
void SyncOperation::setFileId(int fileId) { m_fileId = fileId; }

int SyncOperation::version() const { return m_version; }
void SyncOperation::setVersion(int version) { m_version = version; }

QString SyncOperation::machineId() const { return m_machineId; }
void SyncOperation::setMachineId(const QString &machineId) { m_machineId = machineId; }

QDateTime SyncOperation::date() const { return m_date; }
void SyncOperation::setDate(const QDateTime &date) { m_date = date; }

bool SyncOperation::isValid() const
{
    return m_id >= 0 && m_fileId >= 0 && !m_machineId.isEmpty();
}

} // namespace models
