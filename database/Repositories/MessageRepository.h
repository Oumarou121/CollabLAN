#ifndef DATABASE_MESSAGEREPOSITORY_H
#define DATABASE_MESSAGEREPOSITORY_H

#include <QDateTime>
#include <QStringList>
#include <QVector>
#include <optional>

#include "models/Message.h"

namespace database {

class DatabaseManager;

/// Accuse d'un destinataire pour un message (table MessageReceipts).
struct MessageReceipt {
    QString messageUuid;
    QString userUuid;
    QDateTime deliveredAt;
    QDateTime readAt;
};

/**
 * @brief Acces aux donnees de la table Messages.
 *
 * Gere la persistance des messages en base de donnees,
 * supportant les conversations individuelles et de groupe.
 */
class MessageRepository {
public:
    explicit MessageRepository(DatabaseManager *dbManager);
    ~MessageRepository();

    /// Insere un nouveau message dans la base de donnees.
    std::optional<models::Message> insert(const models::Message &message);

    /// Recupere les messages les plus recents d'une conversation, rendus du
    /// plus ancien au plus recent (ordre chronologique d'envoi).
    /// @param conversationId ID de la conversation
    /// @param limit Nombre maximum de messages a recuperer
    /// @param offset Nombre de messages recents a sauter (page precedente)
    /// @param viewerUserId utilisateur qui lit : isRead() vaut alors "lu par
    ///        lui" (accuses), sinon l'ancien indicateur par poste
    QVector<models::Message> getMessages(qint64 conversationId, int limit = 50, int offset = 0,
                                         qint64 viewerUserId = 0);

    /// Recupere le nombre total de messages dans une conversation.
    int getMessageCount(qint64 conversationId);

    /// Recupere le DERNIER message d'une conversation (le plus recent),
    /// utilise par ConversationsView pour l'apercu de la liste des
    /// conversations.
    std::optional<models::Message> getLastMessage(qint64 conversationId);

    /// Marque un message comme lu (pour tous les utilisateurs du poste).
    bool markAsRead(qint64 messageId);

    /// Marque tous les messages recus d'une conversation comme lus par cet
    /// utilisateur (accuses "lu" locaux, a transmettre a leurs expediteurs).
    bool markConversationAsRead(qint64 conversationId, qint64 userId);

    /// Uuids des messages recus de cette conversation que l'utilisateur n'a pas lus.
    QStringList unreadMessageUuids(qint64 conversationId, qint64 userId) const;

    /// Nombre de messages non lus dans une conversation, pour un utilisateur
    /// donne (ne compte que les messages recus, pas ceux qu'il a envoyes).
    /// Utilise par ConversationsView pour afficher un badge.
    int getUnreadCount(qint64 conversationId, qint64 userId);

    /// Recupere un message par son uuid stable (independant de l'id local),
    /// utilise par SyncLogRepository pour la deduplication a la reconciliation.
    std::optional<models::Message> findByUuid(const QString &uuid) const;

    /// Messages de cet expediteur encore en attente d'accuse de reception du
    /// serveur, du plus ancien au plus recent (file d'envoi).
    QVector<models::Message> pendingMessages(qint64 senderId) const;
    /// Tous les messages en attente, quel que soit l'expediteur.
    QVector<models::Message> allPendingMessages() const;
    /// Fait progresser l'etat d'envoi (pending < sent < delivered < read), sans
    /// jamais revenir en arriere ; faux si inconnu ou deja a ce stade ou au-dela.
    bool setDeliveryStatus(const QString &uuid, const QString &status);

    /// Modification du texte par son auteur. Faux si le message est inconnu,
    /// supprime, ou si une modification plus recente est deja appliquee.
    bool updateContent(const QString &uuid, const QString &content, const QDateTime &editedAt);
    /// Suppression par son auteur : texte efface, ligne conservee.
    bool markDeleted(const QString &uuid, const QDateTime &deletedAt);
    /// Retire un message encore en attente (jamais parti), et lui seul.
    bool removePending(const QString &uuid);

    /// Enregistre ou complete l'accuse d'un destinataire (les heures deja connues
    /// sont gardees). pendingSend : accuse produit ici, a transmettre au serveur.
    /// @return vrai si l'accuse a change.
    bool upsertReceipt(const MessageReceipt &receipt, bool pendingSend);
    std::optional<MessageReceipt> receipt(const QString &messageUuid, const QString &userUuid) const;
    /// Accuses produits ici et pas encore transmis au serveur.
    QVector<MessageReceipt> pendingReceipts() const;
    void clearPendingReceipt(const QString &messageUuid, const QString &userUuid);

    /// Recalcule l'etat d'envoi d'un message a partir des accuses de ses
    /// destinataires (tous remis -> "delivered", tous lus -> "read").
    /// @return le nouvel etat s'il a progresse.
    std::optional<QString> refreshDeliveryStatus(const QString &messageUuid);

    /// Messages recus par cet utilisateur (conversations dont il est membre)
    /// sans accuse "remis" de sa part.
    QStringList undeliveredMessageUuids(qint64 userId) const;

private:
    DatabaseManager *m_dbManager = nullptr;
};

} // namespace database

#endif // DATABASE_MESSAGEREPOSITORY_H
