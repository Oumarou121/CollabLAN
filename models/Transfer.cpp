#include "Transfer.h"

namespace models {

QString transferStatusToString(TransferStatus status)
{
    switch (status) {
    case TransferStatus::Pending:    return QStringLiteral("pending");
    case TransferStatus::InProgress: return QStringLiteral("in_progress");
    case TransferStatus::Completed:  return QStringLiteral("completed");
    case TransferStatus::Failed:     return QStringLiteral("failed");
    case TransferStatus::Cancelled:  return QStringLiteral("cancelled");
    }
    return QStringLiteral("pending");
}

TransferStatus transferStatusFromString(const QString &value)
{
    if (value == QStringLiteral("in_progress")) return TransferStatus::InProgress;
    if (value == QStringLiteral("completed"))    return TransferStatus::Completed;
    if (value == QStringLiteral("failed"))       return TransferStatus::Failed;
    if (value == QStringLiteral("cancelled"))    return TransferStatus::Cancelled;
    return TransferStatus::Pending;
}

Transfer::Transfer() = default;

Transfer::Transfer(int id,
                    int senderId,
                    int recipientId,
                    QString fileName,
                    qint64 fileSize,
                    TransferStatus status,
                    QDateTime createdAt)
    : m_id(id)
    , m_senderId(senderId)
    , m_recipientId(recipientId)
    , m_fileName(std::move(fileName))
    , m_fileSize(fileSize)
    , m_status(status)
    , m_createdAt(std::move(createdAt))
{
}

Transfer::~Transfer() = default;

int Transfer::id() const { return m_id; }
void Transfer::setId(int id) { m_id = id; }

int Transfer::senderId() const { return m_senderId; }
void Transfer::setSenderId(int senderId) { m_senderId = senderId; }

int Transfer::recipientId() const { return m_recipientId; }
void Transfer::setRecipientId(int recipientId) { m_recipientId = recipientId; }

QString Transfer::fileName() const { return m_fileName; }
void Transfer::setFileName(const QString &fileName) { m_fileName = fileName; }

qint64 Transfer::fileSize() const { return m_fileSize; }
void Transfer::setFileSize(qint64 fileSize) { m_fileSize = fileSize; }

TransferStatus Transfer::status() const { return m_status; }
void Transfer::setStatus(TransferStatus status) { m_status = status; }

QDateTime Transfer::createdAt() const { return m_createdAt; }
void Transfer::setCreatedAt(const QDateTime &createdAt) { m_createdAt = createdAt; }

bool Transfer::isValid() const
{
    return m_senderId > 0 && m_recipientId > 0 && !m_fileName.isEmpty() && m_fileSize >= 0;
}

} // namespace models
