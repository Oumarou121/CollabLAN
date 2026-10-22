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

    /// Identifiant stable inter-postes (independant de l'id local
    /// AUTOINCREMENT), utilise comme record_uuid par SyncLogRepository.
    QString uuid() const { return m_uuid; }
    void setUuid(const QString &uuid) { m_uuid = uuid; }

    /// Etat d'envoi, cote expediteur (migrations 033/034) : "pending" tant que
    /// le serveur n'en a pas accuse reception (renvoye a la reconnexion),
    /// "sent" une fois conserve par le serveur, "delivered" quand tous les
    /// destinataires l'ont recu, "read" quand tous l'ont lu.
    static inline const QString Pending = QStringLiteral("pending");
    static inline const QString Sent = QStringLiteral("sent");
    static inline const QString Delivered = QStringLiteral("delivered");
    static inline const QString Read = QStringLiteral("read");
    QString deliveryStatus() const { return m_deliveryStatus; }
    void setDeliveryStatus(const QString &status) { m_deliveryStatus = status; }
    bool isPending() const { return m_deliveryStatus == Pending; }

    /// Derniere modification du texte par son auteur (invalide si jamais modifie).
    QDateTime editedAt() const { return m_editedAt; }
    void setEditedAt(const QDateTime &at) { m_editedAt = at; }
    /// Supprime par son auteur : la ligne reste, le texte est efface.
    QDateTime deletedAt() const { return m_deletedAt; }
    void setDeletedAt(const QDateTime &at) { m_deletedAt = at; }
    bool isDeleted() const { return m_deletedAt.isValid(); }

private:
    qint64 m_id = 0;
    qint64 m_conversationId = 0;
    qint64 m_senderId = 0;
    QString m_content;
    QDateTime m_timestamp;
    bool m_isRead = false;
    QString m_uuid;
    QString m_deliveryStatus = Sent;
    QDateTime m_editedAt;
    QDateTime m_deletedAt;
};

} // namespace models

#endif // MODELS_MESSAGE_H