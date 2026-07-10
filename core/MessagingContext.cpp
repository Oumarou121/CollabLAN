#include "MessagingContext.h"

#include <QDebug>
#include <QVariantMap>

namespace core {

MessagingContext::MessagingContext(QObject *parent)
    : QObject(parent)
    , m_messageModel(new models::MessageModel(this))
    , m_groupModel(new models::GroupModel(this))
{
}

MessagingContext::~MessagingContext()
{
}

void MessagingContext::setMessagingManager(MessagingManager *manager)
{
    if (m_messagingManager != manager) {
        // Disconnect old manager
        if (m_messagingManager) {
            disconnect(m_messagingManager, nullptr, this, nullptr);
        }

        m_messagingManager = manager;

        // Connect new manager
        if (m_messagingManager) {
            connect(m_messagingManager, &MessagingManager::messageReceived,
                    this, &MessagingContext::onMessageReceived);
            connect(m_messagingManager, &MessagingManager::messageSent,
                    this, &MessagingContext::onMessageSent);
        }

        emit messagingManagerChanged();
    }
}

void MessagingContext::setGroupManager(GroupManager *manager)
{
    if (m_groupManager != manager) {
        // Disconnect old manager
        if (m_groupManager) {
            disconnect(m_groupManager, nullptr, this, nullptr);
        }

        m_groupManager = manager;

        // Connect new manager
        if (m_groupManager) {
            connect(m_groupManager, &GroupManager::groupCreated,
                    this, &MessagingContext::onGroupCreated);
        }

        emit groupManagerChanged();
    }
}

void MessagingContext::setUserManager(UserManager *manager)
{
    m_userManager = manager;
}

QVariantList MessagingContext::availableUsers() const
{
    QVariantList list;

    if (!m_userManager) {
        return list;
    }

    for (const auto &user : m_userManager->allUsers()) {
        if (user.id() == m_currentUserId) {
            continue;  // On ne se propose pas soi-meme comme membre.
        }
        QVariantMap entry;
        entry[QStringLiteral("userId")] = user.id();
        entry[QStringLiteral("username")] = user.name();
        list.append(entry);
    }

    return list;
}

QString MessagingContext::userName(qint64 userId) const
{
    if (m_userManager) {
        for (const auto &user : m_userManager->allUsers()) {
            if (user.id() == userId) {
                return user.name();
            }
        }
    }
    return QStringLiteral("Utilisateur %1").arg(userId);
}

QVariantList MessagingContext::conversationsList()
{
    QVariantList list;

    if (!m_messagingManager) {
        return list;
    }

    // Conversations individuelles.
    const auto conversations = m_messagingManager->getUserConversations(m_currentUserId);
    for (const auto &conv : conversations) {
        QVariantMap entry;
        entry[QStringLiteral("conversationId")] = conv.id();
        const qint64 otherId = conv.participant1Id() == m_currentUserId ? conv.participant2Id() : conv.participant1Id();
        entry[QStringLiteral("name")] = userName(otherId);

        const auto messages = m_messagingManager->getMessages(conv.id(), 1);
        entry[QStringLiteral("lastMessage")] = messages.isEmpty() ? QString() : messages.last().content();
        entry[QStringLiteral("timestamp")] = messages.isEmpty() ? QVariant() : messages.last().timestamp();
        list.append(entry);
    }

    // Conversations de groupe (chaque groupe est lie a une Conversation,
    // voir GroupManager::createGroup()).
    if (m_groupManager) {
        const auto groups = m_groupManager->getUserGroups(m_currentUserId);
        for (const auto &group : groups) {
            if (group.conversationId() <= 0) {
                continue;  // Groupe cree avant la migration 004, sans conversation liee.
            }
            QVariantMap entry;
            entry[QStringLiteral("conversationId")] = group.conversationId();
            entry[QStringLiteral("name")] = group.name();

            const auto messages = m_messagingManager->getMessages(group.conversationId(), 1);
            entry[QStringLiteral("lastMessage")] = messages.isEmpty() ? QString() : messages.last().content();
            entry[QStringLiteral("timestamp")] = messages.isEmpty() ? QVariant() : messages.last().timestamp();
            list.append(entry);
        }
    }

    return list;
}

void MessagingContext::loadUserGroups()
{
    if (m_groupManager) {
        const QVector<models::Group> groups = m_groupManager->getUserGroups(m_currentUserId);
        m_groupModel->setGroups(groups);
    }
}

qint64 MessagingContext::createGroup(const QString &name, const QVariantList &memberIds)
{
    if (!m_groupManager || name.trimmed().isEmpty()) {
        return 0;
    }

    QVector<qint64> members;
    for (const QVariant &var : memberIds) {
        members.append(var.toLongLong());
    }

    const auto group = m_groupManager->createGroup(name, m_currentUserId, members);
    if (!group.has_value()) {
        return 0;
    }

    if (group->conversationId() > 0) {
        setConversation(group->conversationId());
    }

    return group->id();
}

void MessagingContext::onGroupCreated(const models::Group &group)
{
    m_groupModel->addGroup(group);
}

void MessagingContext::setConversation(qint64 conversationId)
{
    m_messageModel->setConversationId(conversationId);

    if (m_messagingManager && conversationId > 0) {
        const QVector<models::Message> messages = m_messagingManager->getMessages(conversationId);
        m_messageModel->setMessages(messages);
    } else {
        m_messageModel->clear();
    }
}

void MessagingContext::sendMessage(const QString &content)
{
    if (!m_messagingManager || content.trimmed().isEmpty()) {
        return;
    }

    const qint64 conversationId = m_messageModel->conversationId();
    if (conversationId <= 0) {
        qWarning() << "Cannot send message: no active conversation";
        return;
    }

    m_messagingManager->sendMessage(conversationId, m_currentUserId, content);
}

void MessagingContext::onMessageReceived(const models::Message &message)
{
    // Ajouter le message au modèle s'il appartient à la conversation active
    if (message.conversationId() == m_messageModel->conversationId()) {
        m_messageModel->addMessage(message);
    }
}

void MessagingContext::onMessageSent(const models::Message &message)
{
    // Ajouter le message envoyé au modèle
    if (message.conversationId() == m_messageModel->conversationId()) {
        m_messageModel->addMessage(message);
    }
}

} // namespace core
