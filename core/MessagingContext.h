#ifndef CORE_MESSAGINGCONTEXT_H
#define CORE_MESSAGINGCONTEXT_H

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include "MessagingManager.h"
#include "GroupManager.h"
#include "UserManager.h"
#include "../models/MessageModel.h"
#include "../models/GroupModel.h"

namespace core {

/**
 * @brief Wrapper pour exposer MessagingManager à QML.
 *
 * Facilite l'intégration entre QML et MessagingManager
 * en gérant les connexions de signaux et les modèles.
 */
class MessagingContext : public QObject
{
    Q_OBJECT
    Q_PROPERTY(MessagingManager* messagingManager READ messagingManager WRITE setMessagingManager NOTIFY messagingManagerChanged)
    Q_PROPERTY(models::MessageModel* messageModel READ messageModel CONSTANT)
    Q_PROPERTY(GroupManager* groupManager READ groupManager WRITE setGroupManager NOTIFY groupManagerChanged)
    Q_PROPERTY(models::GroupModel* groupModel READ groupModel CONSTANT)

public:
    explicit MessagingContext(QObject *parent = nullptr);
    ~MessagingContext() override;

    MessagingManager* messagingManager() const { return m_messagingManager; }
    void setMessagingManager(MessagingManager *manager);

    models::MessageModel* messageModel() const { return m_messageModel; }

    GroupManager* groupManager() const { return m_groupManager; }
    void setGroupManager(GroupManager *manager);

    models::GroupModel* groupModel() const { return m_groupModel; }

    /// Configure le UserManager (necessaire a userName() ci-dessous).
    void setUserManager(UserManager *manager);

    /// Définit la conversation active.
    Q_INVOKABLE void setConversation(qint64 conversationId);

    /// Envoie un message dans la conversation active.
    Q_INVOKABLE void sendMessage(const QString &content);

    /// Cree ou recupere une conversation individuelle avec un autre
    /// utilisateur et la definit comme conversation active. Retourne l'id
    /// de la conversation, ou 0 en cas d'echec (ex. otherUserId invalide).
    Q_INVOKABLE qint64 startConversationWith(qint64 otherUserId);

    /// Charge les groupes de l'utilisateur actuel.
    Q_INVOKABLE void loadUserGroups();

    /// Crée un nouveau groupe. Retourne l'id du groupe cree, ou 0 en cas d'echec.
    Q_INVOKABLE qint64 createGroup(const QString &name, const QVariantList &memberIds);

    /// Liste fusionnee des conversations individuelles et de groupe de
    /// l'utilisateur actuel, prete a etre utilisee comme modele QML
    /// (chaque element est une map conversationId/name/lastMessage/timestamp).
    Q_INVOKABLE QVariantList conversationsList();

    /// Liste des utilisateurs disponibles pour la creation d'un groupe
    /// (tous les utilisateurs sauf l'utilisateur courant), prete a l'emploi
    /// comme modele QML : chaque element est une map userId/username.
    Q_INVOKABLE QVariantList availableUsers() const;

    /// Nom d'affichage d'un utilisateur a partir de son id (utilise pour
    /// afficher l'expediteur dans une conversation de groupe). Retourne
    /// "Utilisateur <id>" si l'utilisateur est inconnu.
    Q_INVOKABLE QString userName(qint64 userId) const;

    /// Id de l'utilisateur actuellement authentifie (depuis UserManager).
    Q_INVOKABLE qint64 currentUserId() const;

signals:
    void messagingManagerChanged();
    void groupManagerChanged();
    void availableUsersChanged();

    /// Emis chaque fois que la liste des conversations (individuelles ou
    /// de groupe) de l'utilisateur courant a pu changer : nouveau message
    /// envoye/recu (apercu/horodatage a rafraichir) ou nouveau groupe
    /// cree/recu. ConversationsView.qml n'ecoutait jusqu'ici que
    /// Component.onCompleted, ce qui obligeait a quitter puis revenir sur
    /// l'ecran pour voir la liste se mettre a jour.
    void conversationsChanged();

private slots:
    void onMessageReceived(const models::Message &message);
    void onMessageSent(const models::Message &message);
    void onGroupCreated(const models::Group &group);

private:
    MessagingManager *m_messagingManager = nullptr;
    models::MessageModel *m_messageModel;
    GroupManager *m_groupManager = nullptr;
    models::GroupModel *m_groupModel;
    UserManager *m_userManager = nullptr;
};

} // namespace core

#endif // CORE_MESSAGINGCONTEXT_H