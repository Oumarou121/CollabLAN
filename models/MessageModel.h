#ifndef MODELS_MESSAGEMODEL_H
#define MODELS_MESSAGEMODEL_H

#include <QAbstractListModel>
#include <QVariantMap>
#include <QVector>
#include "Message.h"

namespace models {

/**
 * @brief Modele de liste de messages pour QML.
 *
 * Expose les messages d'une conversation à l'interface QML
 * avec support pour les mises à jour en temps réel.
 */
class MessageModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(qint64 conversationId READ conversationId WRITE setConversationId NOTIFY conversationIdChanged)

public:
    enum MessageRoles {
        IdRole = Qt::UserRole + 1,
        ConversationIdRole,
        SenderIdRole,
        ContentRole,
        TimestampRole,
        IsReadRole
    };

    explicit MessageModel(QObject *parent = nullptr);

    qint64 conversationId() const { return m_conversationId; }
    void setConversationId(qint64 conversationId);

    // QAbstractListModel interface
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    /// Ajoute un message au modèle.
    void addMessage(const Message &message);

    /// Définit tous les messages du modèle.
    void setMessages(const QVector<Message> &messages);

    /// Vide le modèle.
    void clear();

    /// Accès par index depuis QML (equivalent de data() mais expose
    /// toutes les proprietes d'une ligne sous forme de map, comme
    /// le ferait un ListModel classique). Retourne une map vide si
    /// l'index est hors bornes.
    Q_INVOKABLE QVariantMap get(int row) const;

signals:
    void conversationIdChanged();

private:
    QVector<Message> m_messages;
    qint64 m_conversationId = 0;
};

} // namespace models

#endif // MODELS_MESSAGEMODEL_H