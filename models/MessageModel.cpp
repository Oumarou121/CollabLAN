#include "MessageModel.h"

namespace models {

MessageModel::MessageModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

void MessageModel::setConversationId(qint64 conversationId)
{
    if (m_conversationId != conversationId) {
        m_conversationId = conversationId;
        emit conversationIdChanged();
    }
}

int MessageModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_messages.size();
}

QVariant MessageModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_messages.size()) {
        return QVariant();
    }

    const Message &message = m_messages.at(index.row());

    switch (role) {
    case IdRole:
        return message.id();
    case ConversationIdRole:
        return message.conversationId();
    case SenderIdRole:
        return message.senderId();
    case ContentRole:
        return message.content();
    case TimestampRole:
        return message.timestamp();
    case IsReadRole:
        return message.isRead();
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> MessageModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "messageId";
    roles[ConversationIdRole] = "conversationId";
    roles[SenderIdRole] = "senderId";
    roles[ContentRole] = "content";
    roles[TimestampRole] = "timestamp";
    roles[IsReadRole] = "isRead";
    return roles;
}

void MessageModel::addMessage(const Message &message)
{
    beginInsertRows(QModelIndex(), m_messages.size(), m_messages.size());
    m_messages.append(message);
    endInsertRows();
}

void MessageModel::setMessages(const QVector<Message> &messages)
{
    beginResetModel();
    m_messages = messages;
    endResetModel();
}

void MessageModel::clear()
{
    beginResetModel();
    m_messages.clear();
    endResetModel();
}

} // namespace models
