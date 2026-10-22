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

namespace {
QStringList memberUuidsOf(database::DatabaseManager *db, const models::Group &group)
{
    QStringList uuids;
    database::UserRepository users(db->database());
    QVector<qint64> ids = group.memberIds();
    if (!ids.contains(group.ownerId()))
        ids << group.ownerId();
    for (qint64 id : ids) {
        if (const auto user = users.findById(static_cast<int>(id)); user.has_value() && !user->uuid().isEmpty())
            uuids << user->uuid();
    }
    return uuids;
}
} // namespace

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

void GroupManager::setLocalMachineUuid(const QString &machineUuid)
{
    m_localMachineUuid = machineUuid;
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
    // Transmission par l'appelant (groupChangeOutgoing) : envoi au serveur, ou
    // file d'attente sans connexion (un groupe cree hors connexion n'etait
    // jusqu'ici jamais transmis), ou relais direct si ce poste est le serveur.
    {
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
        QStringList targets{ownerUuid};
        for (const QJsonValue &uuid : std::as_const(memberUuids))
            targets << uuid.toString();
        targets.removeAll(QString());
        targets.removeDuplicates();
        emit groupChangeOutgoing(payload, targets);
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

    // Transmis par l'appelant (groupChangeOutgoing) aux membres, ajoute compris.
    {
        database::UserRepository users(m_dbManager->database());

        const auto group = m_repository.getById(groupId);
        if (group.has_value()) {
            QString memberUuid;
            if (const auto member = users.findById(static_cast<int>(memberId)); member.has_value()) {
                memberUuid = member->uuid();
            }

            QJsonObject payload;
            payload.insert(QStringLiteral("type"), QStringLiteral("member_added"));
            payload.insert(QStringLiteral("groupUuid"), group->uuid());
            payload.insert(QStringLiteral("memberUuid"), memberUuid);
            emit groupChangeOutgoing(payload, memberUuidsOf(m_dbManager, *group));
        }
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

    // Transmis par l'appelant aux membres restants et a la personne retiree.
    {
        database::UserRepository users(m_dbManager->database());

        const auto group = m_repository.getById(groupId);
        if (group.has_value()) {
            QString memberUuid;
            if (const auto member = users.findById(static_cast<int>(memberId)); member.has_value()) {
                memberUuid = member->uuid();
            }

            QJsonObject payload;
            payload.insert(QStringLiteral("type"), QStringLiteral("member_removed"));
            payload.insert(QStringLiteral("groupUuid"), group->uuid());
            payload.insert(QStringLiteral("memberUuid"), memberUuid);
            QStringList targets = memberUuidsOf(m_dbManager, *group);
            if (!memberUuid.isEmpty() && !targets.contains(memberUuid))
                targets << memberUuid;
            emit groupChangeOutgoing(payload, targets);
        }
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
    // CORRECTIF : origin_machine_id est NOT NULL en base (SyncLog), mais
    // n'est jamais present dans le payload "group_created" temps reel lui-
    // meme (contrairement aux entrees d'un sync_batch classique). Sans
    // cette ligne, l'INSERT plus bas echouait systematiquement avec
    // "NOT NULL constraint failed: SyncLog.origin_machine_id" et le
    // groupe n'etait alors jamais cree via ce chemin temps reel (il ne
    // finissait par apparaitre qu'a la prochaine reconciliation
    // sync_batch, epoch suivant). On utilise l'uuid de CETTE machine (le
    // recepteur), coherent avec le fait que c'est elle qui journalise
    // localement cette entree SyncLog.
    if (m_localMachineUuid.isEmpty()) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral(
            "GroupManager::receiveGroupCreated: m_localMachineUuid non renseigne "
            "(setLocalMachineUuid jamais appele) - abandon plutot que violer "
            "SyncLog.origin_machine_id NOT NULL");
        qWarning() << m_lastErrorString;
        return std::nullopt;
    }

    models::SyncLogEntry entry;
    entry.setTableName(QStringLiteral("Groups"));
    entry.setRecordUuid(groupUuid);
    entry.setOperation(models::SyncOperation::Insert);
    entry.setPayloadJson(jsonPayload);
    entry.setOriginMachineId(m_localMachineUuid);

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

bool GroupManager::receiveMemberAdded(const QString &jsonPayload)
{
    if (!m_dbManager) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return false;
    }

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(jsonPayload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        return false;
    }

    const QJsonObject obj = doc.object();
    if (obj.value(QStringLiteral("type")).toString() != QStringLiteral("member_added")) {
        return false;
    }

    const QString groupUuid = obj.value(QStringLiteral("groupUuid")).toString();
    const QString memberUuid = obj.value(QStringLiteral("memberUuid")).toString();
    
    if (groupUuid.isEmpty() || memberUuid.isEmpty()) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Payload member_added invalide (groupUuid ou memberUuid manquant)");
        return false;
    }

    // Résoudre les UUID vers les IDs locaux
    const auto group = m_repository.findByUuid(groupUuid);
    if (!group.has_value()) {
        // Groupe pas encore connu localement : on diffère pour une future réconciliation
        qWarning() << "GroupManager::receiveMemberAdded: groupe inconnu (uuid=" << groupUuid << "), différé";
        return false;
    }

    database::UserRepository users(m_dbManager->database());
    const auto member = users.findByUuid(memberUuid);
    if (!member.has_value()) {
        // Membre pas encore connu localement : on diffère pour une future réconciliation
        qWarning() << "GroupManager::receiveMemberAdded: membre inconnu (uuid=" << memberUuid << "), différé";
        return false;
    }

    // Vérifier si déjà membre (idempotent)
    if (group->memberIds().contains(member->id())) {
        return true;
    }

    // Ajouter le membre
    if (!m_repository.addMember(group->id(), member->id())) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Failed to add member from network payload");
        return false;
    }

    emit memberAdded(group->id(), member->id());
    return true;
}

bool GroupManager::receiveMemberRemoved(const QString &jsonPayload)
{
    if (!m_dbManager) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return false;
    }

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(jsonPayload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        return false;
    }

    const QJsonObject obj = doc.object();
    if (obj.value(QStringLiteral("type")).toString() != QStringLiteral("member_removed")) {
        return false;
    }

    const QString groupUuid = obj.value(QStringLiteral("groupUuid")).toString();
    const QString memberUuid = obj.value(QStringLiteral("memberUuid")).toString();
    
    if (groupUuid.isEmpty() || memberUuid.isEmpty()) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Payload member_removed invalide (groupUuid ou memberUuid manquant)");
        return false;
    }

    // Résoudre les UUID vers les IDs locaux
    const auto group = m_repository.findByUuid(groupUuid);
    if (!group.has_value()) {
        // Groupe pas encore connu localement : on diffère pour une future réconciliation
        qWarning() << "GroupManager::receiveMemberRemoved: groupe inconnu (uuid=" << groupUuid << "), différé";
        return false;
    }

    database::UserRepository users(m_dbManager->database());
    const auto member = users.findByUuid(memberUuid);
    if (!member.has_value()) {
        // Membre pas encore connu localement : on diffère pour une future réconciliation
        qWarning() << "GroupManager::receiveMemberRemoved: membre inconnu (uuid=" << memberUuid << "), différé";
        return false;
    }

    // Vérifier si déjà non-membre (idempotent)
    if (!group->memberIds().contains(member->id())) {
        return true;
    }

    // Retirer le membre
    if (!m_repository.removeMember(group->id(), member->id())) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("Failed to remove member from network payload");
        return false;
    }

    emit memberRemoved(group->id(), member->id());
    return true;
}


QString GroupManager::ownerUuidOf(const QString &groupUuid)
{
    if (!m_dbManager)
        return QString();
    const auto group = m_repository.findByUuid(groupUuid);
    if (!group)
        return QString();
    database::UserRepository users(m_dbManager->database());
    const auto owner = users.findById(static_cast<int>(group->ownerId()));
    return owner ? owner->uuid() : QString();
}

bool GroupManager::renameGroup(qint64 groupId, const QString &newName, qint64 requesterId)
{
    const QString name = newName.trimmed();
    const auto group = getGroup(groupId);
    if (!m_dbManager || !group) {
        m_lastError = GroupManagerError::InvalidGroup;
        m_lastErrorString = QStringLiteral("Group not found");
        return false;
    }
    if (group->ownerId() != requesterId) {
        m_lastError = GroupManagerError::NotOwner;
        m_lastErrorString = QStringLiteral("Seul le propriétaire peut renommer le groupe");
        return false;
    }
    if (name.isEmpty()) {
        m_lastError = GroupManagerError::InvalidName;
        m_lastErrorString = QStringLiteral("Nom de groupe vide");
        return false;
    }
    if (name == group->name())
        return true;

    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral("UPDATE Groups SET name = :name WHERE id = :id"));
    query.bindValue(QStringLiteral(":name"), name);
    query.bindValue(QStringLiteral(":id"), groupId);
    if (!query.exec()) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = query.lastError().text();
        return false;
    }
    QSqlQuery conv(m_dbManager->database());
    conv.prepare(QStringLiteral("UPDATE Conversations SET name = :name WHERE id = :id"));
    conv.bindValue(QStringLiteral(":name"), name);
    conv.bindValue(QStringLiteral(":id"), group->conversationId());
    conv.exec();

    database::UserRepository users(m_dbManager->database());
    const auto requester = users.findById(static_cast<int>(requesterId));
    QJsonObject payload;
    payload.insert(QStringLiteral("type"), QStringLiteral("group_renamed"));
    payload.insert(QStringLiteral("groupUuid"), group->uuid());
    payload.insert(QStringLiteral("name"), name);
    payload.insert(QStringLiteral("requesterUuid"), requester ? requester->uuid() : QString());
    emit groupChangeOutgoing(payload, memberUuidsOf(m_dbManager, *group));

    emit groupRenamed(groupId, group->uuid(), name);
    return true;
}

bool GroupManager::deleteGroup(qint64 groupId, qint64 requesterId)
{
    const auto group = getGroup(groupId);
    if (!m_dbManager || !group) {
        m_lastError = GroupManagerError::InvalidGroup;
        m_lastErrorString = QStringLiteral("Group not found");
        return false;
    }
    if (group->ownerId() != requesterId) {
        m_lastError = GroupManagerError::NotOwner;
        m_lastErrorString = QStringLiteral("Seul le propriétaire peut supprimer le groupe");
        return false;
    }

    // Destinataires releves avant la suppression.
    const QStringList members = memberUuidsOf(m_dbManager, *group);
    database::UserRepository users(m_dbManager->database());
    const auto requester = users.findById(static_cast<int>(requesterId));
    QString error;
    if (!database::SyncLogRepository::deleteGroupByUuid(m_dbManager->database(), group->uuid(), &error)) {
        m_lastError = GroupManagerError::DatabaseError;
        m_lastErrorString = error;
        return false;
    }

    QJsonObject payload;
    payload.insert(QStringLiteral("type"), QStringLiteral("group_deleted"));
    payload.insert(QStringLiteral("groupUuid"), group->uuid());
    payload.insert(QStringLiteral("requesterUuid"), requester ? requester->uuid() : QString());
    emit groupChangeOutgoing(payload, members);

    emit groupDeleted(group->uuid(), group->conversationId());
    return true;
}

bool GroupManager::receiveGroupRenamed(const QString &jsonPayload)
{
    const QJsonObject obj = QJsonDocument::fromJson(jsonPayload.toUtf8()).object();
    const QString name = obj.value(QStringLiteral("name")).toString().trimmed();
    const auto group = m_repository.findByUuid(obj.value(QStringLiteral("groupUuid")).toString());
    if (!m_dbManager || !group || name.isEmpty())
        return false;
    if (name == group->name())
        return true;
    QSqlQuery query(m_dbManager->database());
    query.prepare(QStringLiteral("UPDATE Groups SET name = :name WHERE id = :id"));
    query.bindValue(QStringLiteral(":name"), name);
    query.bindValue(QStringLiteral(":id"), group->id());
    if (!query.exec())
        return false;
    QSqlQuery conv(m_dbManager->database());
    conv.prepare(QStringLiteral("UPDATE Conversations SET name = :name WHERE id = :id"));
    conv.bindValue(QStringLiteral(":name"), name);
    conv.bindValue(QStringLiteral(":id"), group->conversationId());
    conv.exec();
    emit groupRenamed(group->id(), group->uuid(), name);
    return true;
}

bool GroupManager::receiveGroupDeleted(const QString &jsonPayload)
{
    const QJsonObject obj = QJsonDocument::fromJson(jsonPayload.toUtf8()).object();
    const QString groupUuid = obj.value(QStringLiteral("groupUuid")).toString();
    const auto group = m_repository.findByUuid(groupUuid);
    if (!m_dbManager || !group)
        return false;
    if (!database::SyncLogRepository::deleteGroupByUuid(m_dbManager->database(), groupUuid))
        return false;
    emit groupDeleted(groupUuid, group->conversationId());
    return true;
}

} // namespace core
