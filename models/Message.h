#ifndef MODELS_MESSAGE_H
#define MODELS_MESSAGE_H

#include <QString>
#include <QDateTime>

namespace models {

/**
 * @brief Represente un message (individuel ou de groupe).
 */
class Message {
public:
    Message();
    Message(qint64 id, qint64 conversationId, qint64 senderId, const QString &content);

    qint64 id() const { return m_id; }
    void setId(qint64 id) { m_id = id; }

    qint64 conversationId() const { return m_conversationId; }
    void setConversationId(qint64 id) { m_conversationId = id; }

    qint64 senderId() const { return m_senderId; }
    void setSenderId(qint64 id) { m_senderId = id; }

    QString content() const { return m_content; }
    void setContent(const QString &content) { m_content = content; }

    QDateTime timestamp() const { return m_timestamp; }
    void setTimestamp(const QDateTime &timestamp) { m_timestamp = timestamp; }

    bool isRead() const { return m_isRead; }
    void setRead(bool read) { m_isRead = read; }

private:
    qint64 m_id = 0;
    qint64 m_conversationId = 0;
    qint64 m_senderId = 0;
    QString m_content;
    QDateTime m_timestamp;
    bool m_isRead = false;
};

} // namespace models

#endif // MODELS_MESSAGE_H
