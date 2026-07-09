#ifndef DATABASE_MESSAGEREPOSITORY_H
#define DATABASE_MESSAGEREPOSITORY_H

#include <QVector>
#include <optional>

#include "models/Message.h"

namespace database {

class DatabaseManager;

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

    /// Recupere les messages d'une conversation avec pagination.
    /// @param conversationId ID de la conversation
    /// @param limit Nombre maximum de messages a recuperer
    /// @param offset Nombre de messages a sauter (pour pagination)
    QVector<models::Message> getMessages(qint64 conversationId, int limit = 50, int offset = 0);

    /// Recupere le nombre total de messages dans une conversation.
    int getMessageCount(qint64 conversationId);

    /// Marque un message comme lu.
    bool markAsRead(qint64 messageId);

    /// Marque tous les messages d'une conversation comme lus pour un utilisateur.
    bool markConversationAsRead(qint64 conversationId, qint64 userId);

private:
    DatabaseManager *m_dbManager = nullptr;
};

} // namespace database

#endif // DATABASE_MESSAGEREPOSITORY_H
