#include "GroupManager.h"

#include "DatabaseManager.h"
#include "Messaging/MessagingServer.h"
#include "Messaging/MessagingService.h"
#include "database/Repositories/UserRepository.h"
#include "database/Repositories/SyncLogRepository.h"
#include "models/SyncLogEntry.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QUuid>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QDebug>

namespace core {

GroupManager::GroupManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
    , m_repository(dbManager)
{
}

GroupManager::~GroupManager()
{
}

void GroupManager::setMessagingServer(network::MessagingServer *messagingServer)
{
    m_messagingServer = messagingServer;
}

void GroupManager::setMessagingService(network::MessagingService *messagingService)
{
    m_messagingService = messagingService;
}

std::optional<models::Group> GroupManager::createGroup(const QString &name, qint64 ownerId, const QVector<qint64> &initialMembers)
{
    if (!m_dbManager) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return std::nullopt;
    }

    if (name.trimmed().isEmpty()) {
        m_lastError = GroupManagerError::InvalidName;
        m_lastErrorString = QStringLiteral("Group name cannot be empty");
        return std::nullopt;
    }

    // Construire le groupe en memoire (proprietaire + membres initiaux)
    // avant persistance : GroupRepository::insert() sauvegarde le groupe
    // ET ses membres en une seule fois.
    models::Group group(0, name);
    group.setOwnerId(ownerId);
    group.addMember(ownerId);
    for (qint64 memberId : initialMembers) {
        if (memberId != ownerId) {
            group.addMember(memberId);
        }
    }

    const auto insertedGroup = m_repository.insert(group);
    if (!insertedGroup.has_value()) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Failed to persist group");
        return std::nullopt;
    }
    group = *insertedGroup;

    // Creer la Conversation (type='group') associee, pour reutiliser telle
    // quelle la messagerie existante (Messages.conversationId) : envoyer/
    // recevoir un message dans un groupe ne differe alors en rien d'une
    // conversation individuelle du point de vue de MessagingManager.
    // (Conversations n'a pas de repository dedie ; requete directe.)
    // uuid : identifiant stable inter-postes indispensable a la
    // reconciliation (SyncLogRepository::ensureConversationByUuid) - cf.
    // migration 011.
    QSqlDatabase db = m_dbManager->database();
    QSqlQuery convQuery(db);
    const QString conversationUuid = QUuid::createUuid().toString(QUuid::WithoutBraces);
    convQuery.prepare(QStringLiteral(
        "INSERT INTO Conversations (type, name, uuid) VALUES ('group', :name, :uuid)"));
    convQuery.bindValue(QStringLiteral(":name"), name);
    convQuery.bindValue(QStringLiteral(":uuid"), conversationUuid);

    if (!convQuery.exec()) {
        qWarning() << "Failed to create conversation for group:" << convQuery.lastError().text();
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = convQuery.lastError().text();
        return std::nullopt;
    }

    const qint64 conversationId = convQuery.lastInsertId().toLongLong();
    group.setConversationId(conversationId);

    if (!m_repository.setConversationId(group.id(), conversationId)) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Failed to link group to conversation");
        return std::nullopt;
    }

    // Diffuser la creation du groupe en temps reel a tous les postes
    // actuellement connectes (type "group_created"), afin que ses membres
    // en soient notifies immediatement plutot que d'attendre la prochaine
    // reconciliation SyncLog (cf. Application::appendGroupSyncLog, qui ne
    // journalise que pour un rejeu differe). On y reutilise le meme jeu de
    // champs (ownerUuid/conversationUuid/memberUuids) que
    // SyncLogRepository::applyGroupEntry, afin que receiveGroupCreated()
    // puisse s'appuyer sur cette meme logique de resolution par uuid.
    //
    // Envoi via les DEUX canaux, comme MessagingManager::sendMessage : le
    // createur peut etre le SERVER actif (m_messagingServer diffuse alors
    // directement a tous les clients connectes) OU un simple CLIENT
    // (m_messagingServer n'ecoute jamais dans ce role, cf. Application.cpp
    // - seul m_messagingService, la connexion sortante vers le SERVER,
    // permet alors de faire parvenir la creation du groupe a qui que ce
    // soit). Sans le second canal, un groupe cree depuis un poste Client
    // n'etait jamais transmis a personne avant la prochaine reconciliation.
    if (m_messagingServer || m_messagingService) {
        database::UserRepository users(m_dbManager->database());
        QString ownerUuid;
        if (const auto owner = users.findById(static_cast<int>(ownerId)); owner.has_value()) {
            ownerUuid = owner->uuid();
        }

        QJsonArray memberUuids;
        for (qint64 memberId : group.memberIds()) {
            if (const auto member = users.findById(static_cast<int>(memberId)); member.has_value()) {
                memberUuids.append(member->uuid());
            }
        }

        QJsonObject payload;
        payload.insert(QStringLiteral("type"), QStringLiteral("group_created"));
        payload.insert(QStringLiteral("groupUuid"), group.uuid());
        payload.insert(QStringLiteral("name"), name);
        payload.insert(QStringLiteral("ownerUuid"), ownerUuid);
        payload.insert(QStringLiteral("conversationUuid"), conversationUuid);
        payload.insert(QStringLiteral("memberUuids"), memberUuids);
        const QString jsonMessage = QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));

        if (m_messagingService && m_messagingService->isConnected()) {
            m_messagingService->sendMessage(jsonMessage);
        }
        if (m_messagingServer) {
            m_messagingServer->broadcastMessage(jsonMessage);
        }
    }

    emit groupCreated(group);
    return group;
}

bool GroupManager::addMember(qint64 groupId, qint64 memberId, qint64 requesterId)
{
    if (!m_dbManager) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return false;
    }

    // Verifier que le demandeur est le propriétaire
    const auto group = getGroup(groupId);
    if (!group.has_value()) {
        m_lastError = GroupManagerError::InvalidGroup;
        m_lastErrorString = QStringLiteral("Group not found");
        return false;
    }

    if (group->ownerId() != requesterId) {
        m_lastError = GroupManagerError::NotOwner;
        m_lastErrorString = QStringLiteral("Only the owner can add members");
        return false;
    }

    // Verifier que le membre n'est pas déjà dans le groupe
    if (group->memberIds().contains(memberId)) {
        return true;  // Déjà membre
    }

    if (!m_repository.addMember(groupId, memberId)) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Failed to add member to group");
        return false;
    }

    emit memberAdded(groupId, memberId);
    return true;
}

bool GroupManager::removeMember(qint64 groupId, qint64 memberId, qint64 requesterId)
{
    if (!m_dbManager) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return false;
    }

    // Verifier que le demandeur est le propriétaire
    const auto group = getGroup(groupId);
    if (!group.has_value()) {
        m_lastError = GroupManagerError::InvalidGroup;
        m_lastErrorString = QStringLiteral("Group not found");
        return false;
    }

    if (group->ownerId() != requesterId) {
        m_lastError = GroupManagerError::NotOwner;
        m_lastErrorString = QStringLiteral("Only the owner can remove members");
        return false;
    }

    // On ne peut pas retirer le propriétaire
    if (memberId == group->ownerId()) {
        m_lastError = GroupManagerError::InvalidUser;
        m_lastErrorString = QStringLiteral("Cannot remove the group owner");
        return false;
    }

    if (!m_repository.removeMember(groupId, memberId)) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Failed to remove member from group");
        return false;
    }

    emit memberRemoved(groupId, memberId);
    return true;
}

QVector<models::Group> GroupManager::getUserGroups(qint64 userId)
{
    if (!m_dbManager) {
        return {};
    }

    return m_repository.getByUserId(userId);
}

std::optional<models::Group> GroupManager::getGroup(qint64 groupId)
{
    if (!m_dbManager) {
        return std::nullopt;
    }

    return m_repository.getById(groupId);
}

std::optional<models::Group> GroupManager::receiveGroupCreated(const QString &jsonPayload)
{
    if (!m_dbManager) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return std::nullopt;
    }

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(jsonPayload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        return std::nullopt;
    }

    const QJsonObject obj = doc.object();
    if (obj.value(QStringLiteral("type")).toString() != QStringLiteral("group_created")) {
        // Autre type de message reseau (ex. "message") : on ignore silencieusement ici.
        return std::nullopt;
    }

    const QString groupUuid = obj.value(QStringLiteral("groupUuid")).toString();
    if (groupUuid.isEmpty()) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Payload group_created invalide (groupUuid manquant)");
        return std::nullopt;
    }

    // Deja connu localement (cree en meme temps que ce broadcast a ete
    // recu, ou rejeu ulterieur via reconciliation SyncLog) : pas de
    // doublon, mais pas d'erreur non plus.
    if (const auto existing = m_repository.findByUuid(groupUuid); existing.has_value()) {
        return std::nullopt;
    }

    // On reutilise SyncLogRepository::applyBatch (meme logique de
    // resolution uuid -> id local que la reconciliation post-panne) :
    // owner/membres sont retrouves via leur uuid stable, jamais via l'id
    // local de la machine emettrice (cf. MessagingManager::receiveMessage
    // pour la meme problematique cote messages). applyBatch journalise en
    // plus l'entree dans SyncLog, ce qui la rend disponible pour une
    // future reconciliation si necessaire (idempotent par entry_uuid).
    models::SyncLogEntry entry;
    entry.setTableName(QStringLiteral("Groups"));
    entry.setRecordUuid(groupUuid);
    entry.setOperation(models::SyncOperation::Insert);
    entry.setPayloadJson(jsonPayload);

    database::SyncLogRepository syncRepo(m_dbManager->database());
    const int insertedCount = syncRepo.applyBatch({entry});
    if (insertedCount == 0) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = syncRepo.lastError().isEmpty()
            ? QStringLiteral("Groupe distant non applique (owner/membre pas encore connu localement ?)")
            : syncRepo.lastError();
        qWarning() << "GroupManager::receiveGroupCreated:" << m_lastErrorString;
        return std::nullopt;
    }

    const auto group = m_repository.findByUuid(groupUuid);
    if (!group.has_value()) {
        return std::nullopt;
    }

    emit groupCreated(*group);
    return group;
}

} // namespace core