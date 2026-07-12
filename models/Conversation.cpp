#include "Conversation.h"

namespace models {

Conversation::Conversation()
{
}

Conversation::Conversation(qint64 id, ConversationType type, const QString &name)
    : m_id(id)
    , m_type(type)
    , m_name(name)
{
}

} // namespace models
