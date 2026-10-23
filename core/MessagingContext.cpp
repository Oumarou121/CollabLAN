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
    // Le cache des conversations est vide AVANT chaque signal
    // (notifyConversationsChanged, onUsersChanged) et non par une connexion a
    // ces signaux : Qt appelle les gestionnaires QML avant les connexions C++,
    // l'ecran relisait donc l'ancien cache (apercu sur l'avant-dernier message).
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
            connect(m_messagingManager, &MessagingManager::messageQueued,
                    this, [this](qint64 conversationId) {
                        if (conversationId == m_messageModel->conversationId())
                            emit messageQueued();
                    });
            connect(m_messagingManager, &MessagingManager::messageRemoved,
                    this, [this](const models::Message &message) {
                        m_messageModel->removeMessage(message.uuid());
                        notifyConversationsChanged();
                    });
            connect(m_messagingManager, &MessagingManager::actionRefused,
                    this, &MessagingContext::actionFailed);
            connect(m_messagingManager, &MessagingManager::messageUpdated,
                    this, [this](const models::Message &message) {
                        m_messageModel->updateMessage(message);
                        notifyConversationsChanged();
                    });
            connect(m_messagingManager, &MessagingManager::messageDeliveryChanged,
                    this, [this](const QString &messageUuid, const QString &status) {
                        m_messageModel->setDeliveryStatus(messageUuid, status);
                    });
            // Messages ajoutes par synchronisation (retour apres une absence) :
            // ils n'emettent pas messageReceived, la conversation ouverte et la
            // liste des conversations sont rechargees.
            connect(m_messagingManager, &MessagingManager::messagesSynchronized,
                    this, [this]() {
                        if (m_messageModel->conversationId() > 0)
                            setConversation(m_messageModel->conversationId());
                        notifyConversationsChanged();
                    }, Qt::QueuedConnection);
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
            connect(m_groupManager, &GroupManager::groupRenamed, this, [this]() {
                loadUserGroups();
                notifyConversationsChanged();
            });
            connect(m_groupManager, &GroupManager::groupDeleted,
                    this, [this](const QString &, qint64 conversationId) {
                        loadUserGroups();
                        if (conversationId > 0 && conversationId == m_messageModel->conversationId()) {
                            m_messageModel->setConversationId(0);
                            m_messageModel->clear();
                        }
                        emit conversationRemoved(conversationId);
                        notifyConversationsChanged();
                    });
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
                    this, &MessagingContext::onUsersChanged, Qt::QueuedConnection);
            connect(m_userManager, &UserManager::userUpdated,
                    this, &MessagingContext::onUsersChanged, Qt::QueuedConnection);
            connect(m_userManager, &UserManager::userDeleted,
                    this, &MessagingContext::onUsersChanged, Qt::QueuedConnection);
            connect(m_userManager, &UserManager::usersChanged,
                    this, &MessagingContext::onUsersChanged, Qt::QueuedConnection);
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
        // Permet de relier un poste du reseau (PeersModel::UserUuidRole) a
        // son compte, startConversationWith() attendant l'identifiant numerique.
        entry[QStringLiteral("userUuid")] = user.uuid();
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

int MessagingContext::totalUnreadCount()
{
    int total = 0;
    for (const QVariant &entry : conversationsList())
        total += entry.toMap().value(QStringLiteral("unreadCount")).toInt();
    return total;
}

QVariantList MessagingContext::conversationsList()
{
    // Plusieurs ecrans (accueil, barre laterale, discussions) relisent la liste
    // au meme signal : elle n'est reconstruite qu'une fois par changement
    // (cache vide avant chaque conversationsChanged), ou apres
    // 30 s par prudence. Le resume de chaque conversation (dernier message,
    // non-lus : les lectures couteuses) est garde a part et seule la
    // conversation touchee est relue a la reception, a l'envoi ou a la lecture.
    const qint64 currentId = currentUserId();
    if (m_conversationsCacheUser == currentId && m_conversationsCacheAge.isValid()
        && m_conversationsCacheAge.elapsed() < 30000) {
        return m_conversationsCache;
    }
    if (m_conversationsCacheUser != currentId)
        m_conversationSummaries.clear();

    QVariantList list;

    if (!m_messagingManager) {
        return list;
    }

    // Noms lus une seule fois : userName() relisait tous les utilisateurs pour
    // chaque conversation.
    QHash<qint64, QString> names;
    if (m_userManager) {
        for (const auto &user : m_userManager->allUsers())
            names.insert(user.id(), user.name());
    }
    const auto nameOf = [&names](qint64 userId) {
        const auto it = names.constFind(userId);
        return it != names.constEnd() ? it.value() : QStringLiteral("Utilisateur %1").arg(userId);
    };

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
        entry[QStringLiteral("name")] = nameOf(otherId);

        const QVariantMap summary = conversationSummary(conv.id(), currentId);
        if (summary.value(QStringLiteral("hasLast")).toBool()) {
            // Prefixe "Moi :"/"Lui :" pour savoir qui a envoye le dernier
            // message sans avoir a ouvrir la conversation (comme WhatsApp).
            const QString prefix = summary.value(QStringLiteral("senderId")).toLongLong() == currentId
                ? tr("Moi : ") : tr("Lui : ");
            entry[QStringLiteral("lastMessage")] = prefix + summary.value(QStringLiteral("text")).toString();
            entry[QStringLiteral("timestamp")] = summary.value(QStringLiteral("timestamp"));
        } else {
            entry[QStringLiteral("lastMessage")] = QString();
            entry[QStringLiteral("timestamp")] = QVariant();
        }
        entry[QStringLiteral("unreadCount")] = summary.value(QStringLiteral("unreadCount"));

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

            const QVariantMap summary = conversationSummary(group.conversationId(), currentId);
            if (summary.value(QStringLiteral("hasLast")).toBool()) {
                // Pour un groupe, "Lui :" serait ambigu (plusieurs membres
                // possibles) : on utilise le prenom de l'expediteur reel.
                const qint64 senderId = summary.value(QStringLiteral("senderId")).toLongLong();
                const QString prefix = senderId == currentId
                    ? tr("Moi : ") : nameOf(senderId) + QStringLiteral(" : ");
                entry[QStringLiteral("lastMessage")] = prefix + summary.value(QStringLiteral("text")).toString();
                entry[QStringLiteral("timestamp")] = summary.value(QStringLiteral("timestamp"));
            } else {
                entry[QStringLiteral("lastMessage")] = QString();
                entry[QStringLiteral("timestamp")] = QVariant();
            }
            entry[QStringLiteral("unreadCount")] = summary.value(QStringLiteral("unreadCount"));
            list.append(entry);
        }
    }

    m_conversationsCache = list;
    m_conversationsCacheUser = currentId;
    m_conversationsCacheAge.start();
    return list;
}

QVariantMap MessagingContext::conversationSummary(qint64 conversationId, qint64 currentId)
{
    const auto cached = m_conversationSummaries.constFind(conversationId);
    if (cached != m_conversationSummaries.constEnd())
        return cached.value();

    QVariantMap summary;
    // getLastMessage() et non getMessages(id, 1), qui renvoyait le PREMIER
    // message (l'apercu restait fige sur le tout premier echange).
    if (const auto lastMessage = m_messagingManager->getLastMessage(conversationId); lastMessage.has_value()) {
        summary.insert(QStringLiteral("hasLast"), true);
        summary.insert(QStringLiteral("senderId"), lastMessage->senderId());
        summary.insert(QStringLiteral("text"), lastMessage->isDeleted() ? tr("Message supprimé") : lastMessage->content());
        summary.insert(QStringLiteral("timestamp"), lastMessage->timestamp());
    }
    summary.insert(QStringLiteral("unreadCount"), m_messagingManager->getUnreadCount(conversationId, currentId));
    m_conversationSummaries.insert(conversationId, summary);
    return summary;
}

void MessagingContext::invalidateConversations(qint64 conversationId)
{
    // Conversation designee (reception, envoi, lecture) : seul son resume est
    // relu ; sinon (groupes, synchronisation, comptes...) tous.
    if (conversationId > 0)
        m_conversationSummaries.remove(conversationId);
    else
        m_conversationSummaries.clear();
    m_conversationsCacheAge.invalidate();
}

void MessagingContext::notifyConversationsChanged(qint64 conversationId)
{
    invalidateConversations(conversationId);
    emit conversationsChanged();
}

void MessagingContext::onUsersChanged()
{
    invalidateConversations(0);
    emit availableUsersChanged();
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
    notifyConversationsChanged();
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
    notifyConversationsChanged();
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
            notifyConversationsChanged(conversationId);
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
    notifyConversationsChanged(message.conversationId());
}

void MessagingContext::onMessageSent(const models::Message &message)
{
    // Ajouter le message envoyé au modèle
    if (message.conversationId() == m_messageModel->conversationId()) {
        m_messageModel->addMessage(message);
    }
    notifyConversationsChanged(message.conversationId());
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

bool MessagingContext::editMessage(const QString &messageUuid, const QString &content)
{
    if (!m_messagingManager)
        return false;
    if (!m_messagingManager->editMessage(messageUuid, content, currentUserId())) {
        emit actionFailed(m_messagingManager->lastErrorString());
        return false;
    }
    return true;
}

bool MessagingContext::deleteMessage(const QString &messageUuid)
{
    if (!m_messagingManager)
        return false;
    if (!m_messagingManager->deleteMessage(messageUuid, currentUserId())) {
        emit actionFailed(m_messagingManager->lastErrorString());
        return false;
    }
    return true;
}

bool MessagingContext::isGroupOwner(qint64 conversationId) const
{
    if (!m_groupManager || conversationId <= 0)
        return false;
    for (const auto &group : m_groupManager->getUserGroups(currentUserId())) {
        if (group.conversationId() == conversationId)
            return group.ownerId() == currentUserId();
    }
    return false;
}

bool MessagingContext::renameGroup(qint64 conversationId, const QString &name)
{
    if (!m_groupManager)
        return false;
    for (const auto &group : m_groupManager->getUserGroups(currentUserId())) {
        if (group.conversationId() != conversationId)
            continue;
        if (!m_groupManager->renameGroup(group.id(), name, currentUserId())) {
            emit actionFailed(m_groupManager->lastErrorString());
            return false;
        }
        return true;
    }
    return false;
}

bool MessagingContext::deleteGroup(qint64 conversationId)
{
    if (!m_groupManager)
        return false;
    for (const auto &group : m_groupManager->getUserGroups(currentUserId())) {
        if (group.conversationId() != conversationId)
            continue;
        if (!m_groupManager->deleteGroup(group.id(), currentUserId())) {
            emit actionFailed(m_groupManager->lastErrorString());
            return false;
        }
        return true;
    }
    return false;
}

} // namespace core
