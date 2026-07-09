#ifndef MODELS_CONVERSATION_H
#define MODELS_CONVERSATION_H

#include <QString>

namespace models {

enum class ConversationType {
    Individual,
    Group
};

/**
 * @brief Represente une conversation individuelle ou de groupe.
 */
class Conversation {
public:
    Conversation();
    Conversation(qint64 id, ConversationType type, const QString &name);

    qint64 id() const { return m_id; }
    void setId(qint64 id) { m_id = id; }

    ConversationType type() const { return m_type; }
    void setType(ConversationType type) { m_type = type; }

    QString name() const { return m_name; }
    void setName(const QString &name) { m_name = name; }

    qint64 participant1Id() const { return m_participant1Id; }
    void setParticipant1Id(qint64 id) { m_participant1Id = id; }

    qint64 participant2Id() const { return m_participant2Id; }
    void setParticipant2Id(qint64 id) { m_participant2Id = id; }

private:
    qint64 m_id = 0;
    ConversationType m_type = ConversationType::Individual;
    QString m_name;
    qint64 m_participant1Id = 0;  // Pour conversations individuelles
    qint64 m_participant2Id = 0;  // Pour conversations individuelles
};

} // namespace models

#endif // MODELS_CONVERSATION_H
