#ifndef DATABASE_GROUPREPOSITORY_H
#define DATABASE_GROUPREPOSITORY_H

#include <QVector>
#include <optional>

#include "models/Group.h"

namespace database {

class DatabaseManager;

/**
 * @brief Acces aux donnees de la table Groups et GroupMembers.
 *
 * Gere la persistance des groupes et de leurs membres en base de donnees.
 */
class GroupRepository {
public:
    explicit GroupRepository(DatabaseManager *dbManager);
    ~GroupRepository();

    /// Insere un nouveau groupe dans la base de donnees.
    std::optional<models::Group> insert(const models::Group &group);

    /// Met a jour un groupe existant.
    bool update(const models::Group &group);

    /// Lie un groupe a sa Conversation (type='group') associee.
    /// Utilise par core::GroupManager juste apres la creation de la
    /// Conversation, car celle-ci ne peut etre creee qu'une fois le
    /// groupe (et donc son id) connu.
    bool setConversationId(qint64 groupId, qint64 conversationId);

    /// Supprime un groupe par son ID.
    bool remove(qint64 groupId);

    /// Recupere un groupe par son ID avec ses membres.
    std::optional<models::Group> getById(qint64 groupId);

    /// Recupere tous les groupes d'un utilisateur.
    QVector<models::Group> getByUserId(qint64 userId);

    /// Ajoute un membre a un groupe.
    bool addMember(qint64 groupId, qint64 userId);

    /// Retire un membre d'un groupe.
    bool removeMember(qint64 groupId, qint64 userId);

    /// Recupere tous les membres d'un groupe.
    QVector<qint64> getGroupMembers(qint64 groupId);

    /// Verifie si un utilisateur est membre d'un groupe.
    bool isMember(qint64 groupId, qint64 userId);

    /// Recupere un groupe par son uuid stable (independant de l'id local),
    /// utilise par SyncLogRepository pour la deduplication a la reconciliation.
    std::optional<models::Group> findByUuid(const QString &uuid);

private:
    DatabaseManager *m_dbManager = nullptr;
};

} // namespace database

#endif // DATABASE_GROUPREPOSITORY_H