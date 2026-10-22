#ifndef CORE_MESSAGINGMANAGER_H
#define CORE_MESSAGINGMANAGER_H

#include <QJsonObject>
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

    /// Verifie si l'utilisateur local est un participant de la conversation
    /// decrite dans le payload (sender, participant1, participant2, ou membre
    /// du groupe). Utilise par handleIncomingPayload pour eviter de persister
    /// et notifier localement des messages qui ne concernent pas l'utilisateur
    /// courant (ex: serveur qui relaye un message entre deux autres clients).
    bool isLocalUserParticipant(const QString &jsonPayload) const;

    /// File d'envoi : renvoie au serveur, dans l'ordre, les messages de cet
    /// expediteur qui n'ont pas encore ete accuses (poste hors connexion au
    /// moment de l'envoi, ou accuse perdu). Le destinataire les deduplique par
    /// uuid. A appeler une fois l'identification envoyee au serveur.
    /// @return le nombre de messages renvoyes.
    int resendPendingMessages(qint64 senderId);

    /// Accuse de reception du serveur ("message_ack") : le message est conserve
    /// par le serveur, il ne sera plus renvoye.
    bool markMessageSent(const QString &messageUuid);

    /// Les messages en attente de ce poste sont desormais conserves ici (ce
    /// poste est devenu serveur) : marques envoyes. Retourne ces messages.
    QVector<models::Message> takeOverPendingMessages();

    /// A appeler apres une synchronisation qui a ajoute des messages en base sans
    /// passer par receiveMessage : l'interface recharge conversations et fil.
    void notifySynchronized(int mergedEntryCount);

    /// Modification / suppression d'un message par son auteur (requesterId),
    /// appliquee tout de suite ici puis propagee (messageChangeOutgoing :
    /// l'appelant l'envoie au serveur, ou la met en file d'attente sans
    /// connexion). Un message encore en attente (jamais parti) est modifie ou
    /// retire localement, sans rien propager.
    bool editMessage(const QString &messageUuid, const QString &newContent, qint64 requesterId);
    bool deleteMessage(const QString &messageUuid, qint64 requesterId);
    /// Applique une modification recue ("message_update"). Seul l'auteur du
    /// message peut le modifier : sinon, sans effet.
    bool receiveMessageUpdate(const QJsonObject &payload);
    /// Payload "message_update" pour un message deja modifie en base.
    QJsonObject messageUpdatePayload(const models::Message &message) const;
    /// Destinataires d'un message (participants ou membres du groupe).
    QStringList recipientUuids(const models::Message &message) const;

    /// Accuses : "remis" pour les messages recus par cet utilisateur et pas
    /// encore accuses (apres une synchronisation, au login).
    void recordDeliveredFor(qint64 userId);
    /// Accuses produits ici et pas encore transmis (cf. MessageRepository).
    QVector<database::MessageReceipt> pendingReceipts() const;
    void clearPendingReceipt(const QString &messageUuid, const QString &userUuid);
    /// Accuses recus (du serveur, ou d'un client quand ce poste est le serveur) :
    /// enregistres, puis etat d'envoi des messages concernes recalcule.
    void applyReceipts(const QVector<database::MessageReceipt> &receipts);
    /// Recalcule l'etat d'envoi de ces messages (accuses appliques ailleurs).
    void refreshDeliveryStatuses(const QStringList &messageUuids);

    /// Le serveur a refuse un changement transmis (raison lisible).
    void notifyActionRefused(const QString &reason);

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

    /// CORRECTIF : emis quand un message temps reel arrive AVANT que son
    /// expediteur (senderUuid) ne soit connu localement (Users pas encore
    /// reconcilie). Contrairement aux entrees d'un sync_batch (rejouees
    /// automatiquement tant qu'elles ne sont pas journalisees, cf.
    /// SyncLogRepository::applyBatch), ce message temps reel etait
    /// jusqu'ici perdu silencieusement ("Sender inconnu ... message
    /// ignore") sans aucune reprise possible : la personne qui l'a envoye
    /// n'obtenait ni erreur ni retransmission, et son destinataire ne
    /// recevait jamais la notification correspondante. Ce signal permet a
    /// l'appelant (Application) de declencher une reconciliation cote
    /// pair pour rattraper l'utilisateur manquant, puis de rejouer ce
    /// message une fois l'utilisateur connu.
    void unresolvedSenderMessage(const QString &senderUuid, const QString &jsonPayload);

    /// Etat d'envoi d'un message change (models::Message::Pending / Sent).
    void messageDeliveryChanged(const QString &messageUuid, const QString &status);

    /// Des messages ont ete ajoutes par synchronisation (cf. notifySynchronized).
    void messagesSynchronized(int mergedEntryCount);

    /// Pas de connexion au serveur : le message est garde et partira a la
    /// reconnexion (ce n'est pas un echec, cf. messageSendFailed).
    void messageQueued(qint64 conversationId);

    /// Un message a ete modifie ou supprime (localement ou par son auteur).
    void messageUpdated(const models::Message &message);

    /// Modification locale a propager ("message_update") : l'appelant la
    /// journalise si ce poste est le serveur.
    void messageChangeOutgoing(const QJsonObject &payload);

    /// Des accuses ont ete produits ici et attendent d'etre transmis.
    void receiptsPending();

    /// Message en attente retire avant d'etre parti (supprime par son auteur).
    void messageRemoved(const models::Message &message);

    /// Changement refuse par le serveur (cf. notifyActionRefused).
    void actionRefused(const QString &reason);

private:
    /// Payload reseau d'un message deja en base, et ses destinataires (uuids
    /// des participants, ou des membres pour un groupe).
    struct OutgoingMessage {
        QJsonObject payload;
        QString json;
        QStringList targetUuids;
    };
    QString localUserUuid() const;
    OutgoingMessage buildOutgoing(const models::Message &message) const;

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