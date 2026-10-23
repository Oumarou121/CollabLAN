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
    case DeliveryStatusRole:
        return message.deliveryStatus();
    case UuidRole:
        return message.uuid();
    case EditedRole:
        return message.editedAt().isValid();
    case DeletedRole:
        return message.isDeleted();
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
    roles[DeliveryStatusRole] = "deliveryStatus";
    roles[UuidRole] = "messageUuid";
    roles[EditedRole] = "isEdited";
    roles[DeletedRole] = "isDeleted";
    return roles;
}

QVariantMap MessageModel::get(int row) const
{
    QVariantMap result;
    if (row < 0 || row >= m_messages.size()) {
        return result;
    }

    const QModelIndex idx = index(row, 0);
    const QHash<int, QByteArray> roles = roleNames();
    for (auto it = roles.constBegin(); it != roles.constEnd(); ++it) {
        result.insert(QString::fromUtf8(it.value()), data(idx, it.key()));
    }
    return result;
}

void MessageModel::addMessage(const Message &message)
{
    // Place chronologique, comme a la relecture de la base (heure puis id) :
    // un message mis en attente pendant une absence arrive apres des messages
    // plus recents et ne doit pas s'afficher en bas, a la place du dernier.
    int row = m_messages.size();
    while (row > 0 && message.timestamp().isValid()) {
        const Message &previous = m_messages.at(row - 1);
        if (previous.timestamp() < message.timestamp()
            || (previous.timestamp() == message.timestamp() && previous.id() <= message.id()))
            break;
        --row;
    }
    beginInsertRows(QModelIndex(), row, row);
    m_messages.insert(row, message);
    endInsertRows();
}

void MessageModel::setMessages(const QVector<Message> &messages)
{
    beginResetModel();
    m_messages = messages;
    endResetModel();
}

void MessageModel::setDeliveryStatus(const QString &messageUuid, const QString &status)
{
    for (int row = 0; row < m_messages.size(); ++row) {
        if (m_messages[row].uuid() == messageUuid) {
            m_messages[row].setDeliveryStatus(status);
            const QModelIndex idx = index(row, 0);
            emit dataChanged(idx, idx, {DeliveryStatusRole});
            return;
        }
    }
}

void MessageModel::updateMessage(const Message &message)
{
    for (int row = 0; row < m_messages.size(); ++row) {
        if (m_messages[row].uuid() == message.uuid()) {
            // L'etat "lu" affiche est celui du lecteur (cf. getMessages), garde.
            const bool read = m_messages[row].isRead();
            m_messages[row] = message;
            m_messages[row].setRead(read);
            const QModelIndex idx = index(row, 0);
            emit dataChanged(idx, idx);
            return;
        }
    }
}

void MessageModel::removeMessage(const QString &messageUuid)
{
    for (int row = 0; row < m_messages.size(); ++row) {
        if (m_messages[row].uuid() == messageUuid) {
            beginRemoveRows(QModelIndex(), row, row);
            m_messages.removeAt(row);
            endRemoveRows();
            return;
        }
    }
}

void MessageModel::clear()
{
    beginResetModel();
    m_messages.clear();
    endResetModel();
}

} // namespace models