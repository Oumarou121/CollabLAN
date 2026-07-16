#ifndef CORE_MESSAGINGMANAGER_H
#define CORE_MESSAGINGMANAGER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVector>
#include <optional>

#include "database/Repositories/MessageRepository.h"
#include "models/Message.h"
#include "models/Conversation.h"

namespace database {
class DatabaseManager;
}

namespace network {
class MessagingService;
class MessagingServer;
}

namespace core {

class NotificationManager;
class UserManager;

enum class MessagingManagerError {
    None,
    InvalidUser,
    InvalidContent,
    DatabaseError,
    NetworkError
};

/**
 * @brief Logique metier de la messagerie individuelle et de groupe.
 *
 * Gere les conversations individuelles entre utilisateurs, l'envoi de messages,
 * et notifie les abonnes (UI) lors de la reception de nouveaux messages.
 */
class MessagingManager : public QObject
{
    Q_OBJECT

public:
    explicit MessagingManager(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~MessagingManager() override;

    /// Configure le service de reseau pour l'envoi de messages.
    void setMessagingService(network::MessagingService *messagingService);

    /// Configure le serveur de reseau (connexions entrantes). Pour un
    /// message de groupe, le message est en plus diffuse a tous les
    /// clients actuellement connectes a ce serveur (chacun etant un
    /// membre potentiel du groupe), en complement de l'envoi point-a-
    /// point via MessagingService.
    void setMessagingServer(network::MessagingServer *messagingServer);

    /// Configure le gestionnaire de notifications.
    void setNotificationManager(NotificationManager *notificationManager);

    /// Configure le gestionnaire d'utilisateurs, necessaire a
    /// receiveMessage() pour connaitre notre propre identite locale
    /// (voir commentaire dans receiveMessage()).
    void setUserManager(UserManager *userManager);

    /// Cree ou recupere une conversation individuelle entre deux utilisateurs.
    std::optional<models::Conversation> getOrCreateConversation(qint64 userId1, qint64 userId2);

    /// Envoie un message dans une conversation.
    std::optional<models::Message> sendMessage(qint64 conversationId, qint64 senderId, const QString &content);

    /// Traite un message recu du reseau (payload JSON envoye par sendMessage
    /// sur le poste distant) : le persiste en base et emet messageReceived.
    /// Retourne std::nullopt si le payload est invalide ou d'un type inconnu.
    std::optional<models::Message> receiveMessage(const QString &jsonPayload);

    /// Recupere tous les messages d'une conversation.
    QVector<models::Message> getMessages(qint64 conversationId, int limit = 100);

    /// Recupere le dernier message (le plus recent) d'une conversation,
    /// pour l'apercu affiche dans ConversationsView.
    std::optional<models::Message> getLastMessage(qint64 conversationId);

    /// Recupere toutes les conversations d'un utilisateur.
    QVector<models::Conversation> getUserConversations(qint64 userId);

    /// Marque tous les messages recus d'une conversation comme lus pour
    /// userId (appele quand l'utilisateur ouvre la conversation).
    bool markConversationAsRead(qint64 conversationId, qint64 userId);

    /// Nombre de messages non lus dans une conversation pour userId,
    /// utilise pour le badge dans ConversationsView.
    int getUnreadCount(qint64 conversationId, qint64 userId);

    /// Resout les uuids des destinataires reels d'un payload "message" deja
    /// recu du reseau (participant1Uuid/participant2Uuid s'ils sont
    /// presents, sinon membres du groupe via conversationUuid), afin que
    /// l'appelant (Application::handleIncomingPayload) puisse relayer ce
    /// message uniquement a ces destinataires plutot que de le rediffuser
    /// a tous les clients connectes (issue #2). Retourne une liste vide si
    /// le payload n'est pas un message ou si aucun destinataire n'a pu
    /// etre resolu.
    QStringList resolveTargetUuidsFromPayload(const QString &jsonPayload) const;

    /// Derniere erreur survenue.
    MessagingManagerError lastError() const { return m_lastError; }
    QString lastErrorString() const { return m_lastErrorString; }

signals:
    /// Emis lorsqu'un nouveau message est recu (via reseau).
    void messageReceived(const models::Message &message);

    /// Emis lorsqu'un message est envoye avec succes.
    void messageSent(const models::Message &message);

    /// Emis en cas d'erreur lors de l'envoi.
    void messageSendFailed(qint64 conversationId, const QString &error);

private:
    /// Uuids des membres du groupe associe a la conversation @p conversationId
    /// (liste vide si ce n'est pas une conversation de groupe, ou si le
    /// groupe/ses membres sont introuvables localement). Factorise entre
    /// sendMessage() et resolveTargetUuidsFromPayload().
    QStringList resolveGroupMemberUuids(qint64 conversationId) const;

    database::DatabaseManager *m_dbManager = nullptr;
    database::MessageRepository m_repository;
    network::MessagingService *m_messagingService = nullptr;
    network::MessagingServer *m_messagingServer = nullptr;
    NotificationManager *m_notificationManager = nullptr;
    UserManager *m_userManager = nullptr;
    MessagingManagerError m_lastError = MessagingManagerError::None;
    QString m_lastErrorString;
};

} // namespace core

#endif // CORE_MESSAGINGMANAGER_H