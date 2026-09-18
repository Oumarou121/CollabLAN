#include "MessagingContext.h"

#include <QDateTime>
#include <QDebug>
#include <QHash>
#include <QVariantMap>

#include "Discovery/PeersModel.h"

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
            connect(m_messagingManager, &MessagingManager::messageSendFailed,
                    this, &MessagingContext::onMessageSendFailed);
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
    qDebug() << "MessagingContext::setUserManager called, manager =" << manager;
    if (m_userManager != manager) {
        // Disconnect old manager
        if (m_userManager) {
            disconnect(m_userManager, nullptr, this, nullptr);
        }

        m_userManager = manager;

        // Connect new manager to notify when users change
        // Utiliser Qt::QueuedConnection pour éviter les crashs de thread
        if (m_userManager) {
            qDebug() << "MessagingContext::setUserManager: connecting to UserManager signals";
            connect(m_userManager, &UserManager::userCreated,
                    this, &MessagingContext::availableUsersChanged, Qt::QueuedConnection);
            connect(m_userManager, &UserManager::userUpdated,
                    this, &MessagingContext::availableUsersChanged, Qt::QueuedConnection);
            connect(m_userManager, &UserManager::userDeleted,
                    this, &MessagingContext::availableUsersChanged, Qt::QueuedConnection);
            connect(m_userManager, &UserManager::usersChanged,
                    this, &MessagingContext::availableUsersChanged, Qt::QueuedConnection);
        }

        // NE PAS émettre le signal lors de l'initialisation pour éviter les crashs de thread
        // Le signal sera émis automatiquement quand l'UI sera prête via Component.onCompleted
        qDebug() << "MessagingContext::setUserManager: skipping initial emit to avoid thread crash";
    }
}

void MessagingContext::setPeersModel(network::PeersModel *model)
{
    if (m_peersModel == model)
        return;
    if (m_peersModel)
        disconnect(m_peersModel, nullptr, this, nullptr);

    m_peersModel = model;
    if (!m_peersModel)
        return;

    // Chaque annonce, changement d'identite ou perte de pair reevalue
    // immediatement l'indicateur de presence dans les conversations.
    connect(m_peersModel, &QAbstractItemModel::dataChanged,
            this, &MessagingContext::presenceChanged);
    connect(m_peersModel, &QAbstractItemModel::rowsInserted,
            this, &MessagingContext::presenceChanged);
    connect(m_peersModel, &QAbstractItemModel::rowsRemoved,
            this, &MessagingContext::presenceChanged);
    connect(m_peersModel, &QAbstractItemModel::modelReset,
            this, &MessagingContext::presenceChanged);
}

QVariantList MessagingContext::availableUsers() const
{
    QVariantList list;

    if (!m_userManager) {
        qWarning() << "MessagingContext::availableUsers: m_userManager is null";
        return list;
    }

    const qint64 currentId = currentUserId();
    qDebug() << "MessagingContext::availableUsers: currentUserId =" << currentId;

    const auto users = m_userManager->allUsers();
    qDebug() << "MessagingContext::availableUsers: total users in DB =" << users.size();

    for (const auto &user : users) {
        qDebug() << "  User:" << user.id() << user.name();
        if (user.id() == currentId) {
            qDebug() << "    Skipping current user";
            continue;  // On ne se propose pas soi-meme comme membre.
        }
        QVariantMap entry;
        entry[QStringLiteral("userId")] = user.id();
        entry[QStringLiteral("username")] = user.name();
        list.append(entry);
    }

    qDebug() << "MessagingContext::availableUsers: returning" << list.size() << "users";
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

qint64 MessagingContext::otherParticipantId(qint64 conversationId) const
{
    if (conversationId <= 0 || !m_messagingManager) {
        return 0;
    }

    const qint64 currentId = currentUserId();
    const auto conversations = m_messagingManager->getUserConversations(currentId);
    for (const auto &conv : conversations) {
        if (conv.id() == conversationId) {
            return conv.participant1Id() == currentId ? conv.participant2Id() : conv.participant1Id();
        }
    }
    return 0;
}

QString MessagingContext::userStatus(qint64 userId) const
{
    if (!m_userManager || !m_peersModel)
        return QStringLiteral("offline");

    QString userUuid;
    for (const auto &user : m_userManager->allUsers()) {
        if (user.id() == userId) {
            userUuid = user.uuid();
            break;
        }
    }
    if (userUuid.isEmpty())
        return QStringLiteral("offline");

    for (int row = 0; row < m_peersModel->rowCount(); ++row) {
        const QModelIndex index = m_peersModel->index(row, 0);
        if (m_peersModel->data(index, network::PeersModel::UserUuidRole).toString() != userUuid)
            continue;
        const QString status = m_peersModel->data(index, network::PeersModel::StatusRole)
                                   .toString().toLower();
        return status == QStringLiteral("away") ? status : QStringLiteral("online");
    }
    return QStringLiteral("offline");
}

qint64 MessagingContext::currentUserId() const
{
    if (m_userManager) {
        const auto id = m_userManager->currentUserId();
        return id.value_or(0);
    }
    return 0;
}

QVariantList MessagingContext::conversationsList()
{
    QVariantList list;

    if (!m_messagingManager) {
        return list;
    }

    const qint64 currentId = currentUserId();

    // Conversations individuelles.
    const auto conversations = m_messagingManager->getUserConversations(currentId);
    // Les anciennes versions pouvaient deja avoir cree plusieurs UUID pour
    // la meme paire. On n'affiche qu'une carte par correspondant, en gardant
    // celle qui porte le message le plus recent. Les conversations de groupe
    // ne passent pas par ce filtre.
    QHash<qint64, int> individualEntryByOtherUser;
    for (const auto &conv : conversations) {
        QVariantMap entry;
        entry[QStringLiteral("conversationId")] = conv.id();
        const qint64 otherId = conv.participant1Id() == currentId ? conv.participant2Id() : conv.participant1Id();
        entry[QStringLiteral("name")] = userName(otherId);

        // Bug rapporte : getMessages(id, 1) retourne le PREMIER message
        // (ORDER BY id ASC), pas le dernier -> l'apercu restait fige sur
        // le tout premier message echange, comme si rien de plus recent
        // n'avait jamais ete envoye. getLastMessage() corrige cela.
        const auto lastMessage = m_messagingManager->getLastMessage(conv.id());
        if (lastMessage.has_value()) {
            // Prefixe "Moi :"/"Lui :" pour savoir qui a envoye le dernier
            // message sans avoir a ouvrir la conversation (comme WhatsApp).
            const QString prefix = lastMessage->senderId() == currentId
                ? tr("Moi : ") : tr("Lui : ");
            entry[QStringLiteral("lastMessage")] = prefix + lastMessage->content();
            entry[QStringLiteral("timestamp")] = lastMessage->timestamp();
        } else {
            entry[QStringLiteral("lastMessage")] = QString();
            entry[QStringLiteral("timestamp")] = QVariant();
        }
        entry[QStringLiteral("unreadCount")] = m_messagingManager->getUnreadCount(conv.id(), currentId);

        const auto existingIt = individualEntryByOtherUser.constFind(otherId);
        if (existingIt == individualEntryByOtherUser.constEnd()) {
            individualEntryByOtherUser.insert(otherId, list.size());
            list.append(entry);
            continue;
        }

        const int existingIndex = existingIt.value();
        const QVariantMap existing = list.at(existingIndex).toMap();
        const QDateTime existingTimestamp = existing.value(QStringLiteral("timestamp")).toDateTime();
        const QDateTime candidateTimestamp = entry.value(QStringLiteral("timestamp")).toDateTime();
        if (!existingTimestamp.isValid()
            || (candidateTimestamp.isValid() && candidateTimestamp >= existingTimestamp)) {
            list[existingIndex] = entry;
        }
    }

    // Conversations de groupe (chaque groupe est lie a une Conversation,
    // voir GroupManager::createGroup()).
    if (m_groupManager) {
        const auto groups = m_groupManager->getUserGroups(currentId);
        for (const auto &group : groups) {
            if (group.conversationId() <= 0) {
                continue;  // Groupe cree avant la migration 004, sans conversation liee.
            }
            QVariantMap entry;
            entry[QStringLiteral("conversationId")] = group.conversationId();
            entry[QStringLiteral("name")] = group.name();

            const auto lastMessage = m_messagingManager->getLastMessage(group.conversationId());
            if (lastMessage.has_value()) {
                // Pour un groupe, "Lui :" serait ambigu (plusieurs membres
                // possibles) : on utilise le prenom de l'expediteur reel.
                const QString prefix = lastMessage->senderId() == currentId
                    ? tr("Moi : ") : userName(lastMessage->senderId()) + QStringLiteral(" : ");
                entry[QStringLiteral("lastMessage")] = prefix + lastMessage->content();
                entry[QStringLiteral("timestamp")] = lastMessage->timestamp();
            } else {
                entry[QStringLiteral("lastMessage")] = QString();
                entry[QStringLiteral("timestamp")] = QVariant();
            }
            entry[QStringLiteral("unreadCount")] = m_messagingManager->getUnreadCount(group.conversationId(), currentId);
            list.append(entry);
        }
    }

    return list;
}

qint64 MessagingContext::startConversationWith(qint64 otherUserId)
{
    if (!m_messagingManager || otherUserId <= 0) {
        return 0;
    }

    const qint64 currentId = currentUserId();
    if (currentId <= 0 || currentId == otherUserId) {
        return 0;
    }

    const auto conversation = m_messagingManager->getOrCreateConversation(currentId, otherUserId);
    if (!conversation.has_value()) {
        qWarning() << "MessagingContext::startConversationWith: echec de la creation/recuperation"
                   << "de la conversation avec l'utilisateur" << otherUserId;
        return 0;
    }

    setConversation(conversation->id());
    emit conversationsChanged();
    return conversation->id();
}

void MessagingContext::loadUserGroups()
{
    if (m_groupManager) {
        const QVector<models::Group> groups = m_groupManager->getUserGroups(currentUserId());
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

    const qint64 currentId = currentUserId();
    const auto group = m_groupManager->createGroup(name, currentId, members);
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
    emit conversationsChanged();
}

void MessagingContext::setConversation(qint64 conversationId)
{
    m_messageModel->setConversationId(conversationId);

    if (m_messagingManager && conversationId > 0) {
        const QVector<models::Message> messages = m_messagingManager->getMessages(conversationId);
        m_messageModel->setMessages(messages);

        // Marquer les messages reçus comme lus : jusqu'ici is_read n'était
        // jamais mis à jour nulle part dans le code applicatif (seulement
        // testé), donc le badge de messages non lus restait figé même
        // après ouverture de la conversation.
        const qint64 currentId = currentUserId();
        if (currentId > 0 && m_messagingManager->markConversationAsRead(conversationId, currentId)) {
            emit conversationsChanged();
        }
    } else {
        m_messageModel->clear();
    }
}

QString MessagingContext::conversationDisplayName(qint64 conversationId) const
{
    if (conversationId <= 0) {
        return QString();
    }

    // Conversation de groupe : le nom vient de Groups, pas de Conversations
    // (voir GroupManager::createGroup, qui lie group.conversationId()).
    if (m_groupManager) {
        const auto groups = m_groupManager->getUserGroups(currentUserId());
        for (const auto &group : groups) {
            if (group.conversationId() == conversationId) {
                return group.name();
            }
        }
    }

    // Conversation individuelle : le nom affiché est celui de l'AUTRE
    // participant (jamais le nôtre).
    if (m_messagingManager) {
        const qint64 currentId = currentUserId();
        const auto conversations = m_messagingManager->getUserConversations(currentId);
        for (const auto &conv : conversations) {
            if (conv.id() == conversationId) {
                const qint64 otherId = conv.participant1Id() == currentId
                    ? conv.participant2Id() : conv.participant1Id();
                return userName(otherId);
            }
        }
    }

    return QString();
}

bool MessagingContext::isGroupConversation(qint64 conversationId) const
{
    if (conversationId <= 0) {
        return false;
    }

    // Vérifie si la conversation correspond à un groupe
    if (m_groupManager) {
        const auto groups = m_groupManager->getUserGroups(currentUserId());
        for (const auto &group : groups) {
            if (group.conversationId() == conversationId) {
                return true;
            }
        }
    }

    return false;
}

void MessagingContext::sendMessage(const QString &content)
{
    if (!m_messagingManager) {
        qWarning() << "Cannot send message: MessagingManager not set";
        emit messageSendFailed(tr("Impossible d'envoyer le message : service de messagerie indisponible"));
        return;
    }
    if (content.trimmed().isEmpty()) {
        return;
    }

    const qint64 conversationId = m_messageModel->conversationId();
    if (conversationId <= 0) {
        qWarning() << "Cannot send message: no active conversation";
        emit messageSendFailed(tr("Impossible d'envoyer le message : aucune conversation active"));
        return;
    }

    m_messagingManager->sendMessage(conversationId, currentUserId(), content);
}

void MessagingContext::onMessageReceived(const models::Message &message)
{
    // Ajouter le message au modèle s'il appartient à la conversation active
    if (message.conversationId() == m_messageModel->conversationId()) {
        m_messageModel->addMessage(message);

        // Bug rapporté : un message recu pendant que la conversation est
        // DEJA ouverte restait marque non-lu tant qu'on ne quittait pas
        // l'ecran puis n'y revenait pas (seul setConversation(), appele a
        // l'ouverture, appelait markConversationAsRead()). Ici on est déjà
        // en train de lire cette conversation, donc ce nouveau message doit
        // être marqué lu immédiatement, sans attendre une réouverture.
        const qint64 currentId = currentUserId();
        if (currentId > 0 && m_messagingManager) {
            m_messagingManager->markConversationAsRead(message.conversationId(), currentId);
        }
    }
    // Meme si la conversation n'est pas celle actuellement ouverte, son
    // apercu (dernier message/horodatage) dans ConversationsView doit se
    // mettre a jour sans que l'utilisateur ait besoin de quitter puis
    // revenir sur l'ecran.
    emit conversationsChanged();
}

void MessagingContext::onMessageSent(const models::Message &message)
{
    // Ajouter le message envoyé au modèle
    if (message.conversationId() == m_messageModel->conversationId()) {
        m_messageModel->addMessage(message);
    }
    emit conversationsChanged();
}

void MessagingContext::onMessageSendFailed(qint64 conversationId, const QString &error)
{
    // Ne remonter a l'UI que les echecs concernant la conversation
    // actuellement ouverte : un echec sur une autre conversation (ex. un
    // retry d'arriere-plan) n'a pas a interrompre l'utilisateur ici.
    if (conversationId != m_messageModel->conversationId()) {
        return;
    }
    emit messageSendFailed(error);
}

} // namespace core
