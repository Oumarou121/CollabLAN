#ifndef CORE_GROUPMANAGER_H
#define CORE_GROUPMANAGER_H

#include <QObject>
#include <QString>
#include <QVector>
#include <optional>

#include "database/Repositories/GroupRepository.h"
#include "models/Group.h"

namespace database {
class DatabaseManager;
}

namespace network {
class MessagingServer;
class MessagingService;
}

namespace core {

enum class GroupManagerError {
    None,
    InvalidUser,
    InvalidGroup,
    InvalidName,
    DatabaseError,
    NotOwner
};

/**
 * @brief Gestion des groupes de discussion.
 *
 * Gere la creation de groupes, l'ajout/retrait de membres,
 * et l'envoi de messages dans les groupes.
 */
class GroupManager : public QObject
{
    Q_OBJECT

public:
    explicit GroupManager(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~GroupManager() override;

    /// Configure le serveur de reseau (connexions entrantes), utilise pour
    /// diffuser en temps reel la creation d'un groupe (type "group_created")
    /// a tous les postes actuellement connectes : sans cela, les autres
    /// membres n'apprenaient l'existence du groupe qu'a la prochaine
    /// reconciliation SyncLog (potentiellement bien plus tard).
    void setMessagingServer(network::MessagingServer *messagingServer);

    /// Configure le service de reseau (connexion sortante), utilise pour
    /// diffuser la creation d'un groupe quand CE poste est un CLIENT
    /// (aucun MessagingServer actif dans ce cas, cf. Application.cpp :
    /// seuls les roles Server/TempServer en demarrent un). Sans cela, un
    /// groupe cree depuis un poste Client n'etait jamais transmis au
    /// SERVER actif - les autres membres n'en apprenaient l'existence
    /// qu'a la prochaine reconciliation SyncLog.
    void setMessagingService(network::MessagingService *messagingService);

    /// Cree un nouveau groupe avec un nom et des membres initiaux.
    std::optional<models::Group> createGroup(const QString &name, qint64 ownerId, const QVector<qint64> &initialMembers);

    /// Ajoute un membre a un groupe.
    bool addMember(qint64 groupId, qint64 memberId, qint64 requesterId);

    /// Retire un membre d'un groupe.
    bool removeMember(qint64 groupId, qint64 memberId, qint64 requesterId);

    /// Recupere tous les groupes d'un utilisateur.
    QVector<models::Group> getUserGroups(qint64 userId);

    /// Recupere un groupe par son ID.
    std::optional<models::Group> getGroup(qint64 groupId);

    /// Traite un message reseau de type "group_created" recu d'un autre
    /// poste : cree le groupe localement s'il n'est pas deja connu (par
    /// son uuid stable) et emet groupCreated pour que l'UI (et les
    /// notifications) reagissent immediatement. Retourne std::nullopt si
    /// le payload est invalide, d'un type inconnu, ou si le groupe est
    /// deja connu localement.
    std::optional<models::Group> receiveGroupCreated(const QString &jsonPayload);

    /// Derniere erreur survenue.
    GroupManagerError lastError() const { return m_lastError; }
    QString lastErrorString() const { return m_lastErrorString; }

signals:
    /// Emis lorsqu'un groupe est cree.
    void groupCreated(const models::Group &group);

    /// Emis lorsqu'un membre est ajoute a un groupe.
    void memberAdded(qint64 groupId, qint64 memberId);

    /// Emis lorsqu'un membre est retire d'un groupe.
    void memberRemoved(qint64 groupId, qint64 memberId);

private:
    database::DatabaseManager *m_dbManager = nullptr;
    database::GroupRepository m_repository;
    network::MessagingServer *m_messagingServer = nullptr;
    network::MessagingService *m_messagingService = nullptr;
    GroupManagerError m_lastError = GroupManagerError::None;
    QString m_lastErrorString;
};

} // namespace core

#endif // CORE_GROUPMANAGER_H