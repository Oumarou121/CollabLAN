#include "Message.h"

namespace models {

Message::Message()
    : m_timestamp(QDateTime::currentDateTime())
{
}

Message::Message(qint64 id, qint64 conversationId, qint64 senderId, const QString &content)
    : m_id(id)
    , m_conversationId(conversationId)
    , m_senderId(senderId)
    , m_content(content)
    , m_timestamp(QDateTime::currentDateTime())
{
}

} // namespace models
