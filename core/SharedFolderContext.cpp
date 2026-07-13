#include "SharedFolderContext.h"

#include <QHash>
#include <QVariantMap>

namespace core {

SharedFolderContext::SharedFolderContext(QObject *parent)
    : QObject(parent)
    , m_folderModel(new models::SharedFolderModel(this))
{
}

SharedFolderContext::~SharedFolderContext()
{
}

void SharedFolderContext::setSharedFolderManager(SharedFolderManager *manager)
{
    m_manager = manager;

    // Mise a jour automatique du modele de dossiers (compteur de fichiers)
    // apres chaque (re)indexation, meme declenchee automatiquement par
    // FolderWatcher -- sans ce connect, l'utilisateur devait naviguer
    // manuellement hors/dans l'ecran pour voir le nouveau compteur.
    if (m_manager) {
        connect(m_manager, &SharedFolderManager::folderShared,
                this, [this](qint64, int) { refresh(); });
        // Rafraîchir l'UI quand un accès est accordé localement (toujours émis)
        connect(m_manager, &SharedFolderManager::accessGrantedLocal,
                this, [this](qint64, qint64) { refresh(); });
    }

    refresh();
}

void SharedFolderContext::setSyncEngine(core::sync::SyncEngine *engine)
{
    m_syncEngine = engine;

    // Transmet le signal SyncEngine::folderReindexed a QML : SharedFolderView
    // l'ecoute pour rafraichir la liste des fichiers et l'historique de
    // synchronisation des qu'un changement est detecte par FolderWatcher,
    // sans action manuelle de l'utilisateur.
    if (m_syncEngine) {
        connect(m_syncEngine, &core::sync::SyncEngine::folderReindexed,
                this, &SharedFolderContext::folderReindexed);
    }
}

void SharedFolderContext::setUserManager(UserManager *manager)
{
    m_userManager = manager;
}

void SharedFolderContext::setFolderSyncService(core::sync::FolderSyncService *svc)
{
    m_folderSyncService = svc;
    if (m_folderSyncService) {
        // Retransmet conflictDetected a QML pour que SharedFolderView puisse
        // afficher un badge ou une banniere sans connaitre FolderSyncService.
        connect(m_folderSyncService, &core::sync::FolderSyncService::conflictDetected,
                this, &SharedFolderContext::conflictDetected);
    }
}

void SharedFolderContext::refresh()
{
    if (!m_manager) {
        return;
    }

    // Filtre par acces (proprietaire + acces explicitement accordes) plutot
    // que getFolders() (TOUS les dossiers, sans aucune restriction) : un
    // dossier partage ne doit etre visible que par les utilisateurs choisis
    // a sa creation (ou a qui l'acces a ete accorde ensuite), pas par tout
    // compte local sans distinction.
    qint64 currentUserId = 0;
    if (m_userManager) {
        if (const auto id = m_userManager->currentUserId(); id.has_value()) {
            currentUserId = *id;
        }
    }
    const QVector<models::SharedFolder> folders = m_manager->getAccessibleFolders(currentUserId);
    m_folderModel->setFolders(folders);

    QHash<qint64, int> counts;
    for (const models::SharedFolder &folder : folders) {
        counts.insert(folder.id(), m_manager->getFiles(folder.id()).size());
    }
    m_folderModel->setFileCounts(counts);
}

bool SharedFolderContext::createFolder(const QString &name, const QString &localPath,
                                        const QVariantList &authorizedUserIds, bool allowWrite)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    qint64 ownerId = 0;
    if (m_userManager) {
        if (const auto currentId = m_userManager->currentUserId(); currentId.has_value()) {
            ownerId = *currentId;
        }
    }

    QVector<qint64> userIds;
    userIds.reserve(authorizedUserIds.size());
    for (const QVariant &value : authorizedUserIds) {
        userIds.append(value.toLongLong());
    }
    const auto permission = allowWrite ? models::SharedFolderPermission::Write
                                        : models::SharedFolderPermission::Read;

    const auto folder = m_manager->createFolder(name, localPath, ownerId, userIds, permission);
    if (!folder.has_value()) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    // Indexation locale immediate : l'utilisateur s'attend a voir le
    // nombre de fichiers des la creation, pas seulement au premier clic
    // manuel sur "actualiser" (voir commentaire Q_INVOKABLE createFolder()).
    // Passe par SyncEngine (s'il est disponible) plutot que par le
    // manager directement, afin que les fichiers deja presents soient
    // aussi journalises comme des SyncOperation de type Create.
    if (m_syncEngine) {
        m_syncEngine->reindexFolder(folder->id());
    } else {
        m_manager->shareFolder(folder->id());
    }
    refresh();
    return true;
}

bool SharedFolderContext::removeFolder(qint64 folderId)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    const bool ok = m_manager->removeFolder(folderId);
    if (!ok) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    refresh();
    return true;
}

bool SharedFolderContext::shareFolder(qint64 folderId)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    int changeCount = -1;
    if (m_syncEngine) {
        changeCount = m_syncEngine->reindexFolder(folderId);
    } else {
        const auto changes = m_manager->shareFolder(folderId);
        changeCount = changes.has_value() ? changes->size() : -1;
    }

    if (changeCount < 0) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    refresh();
    return true;
}

QVariantList SharedFolderContext::filesForFolder(qint64 folderId) const
{
    QVariantList result;
    if (!m_manager) {
        return result;
    }

    for (const models::SharedFile &file : m_manager->getFiles(folderId)) {
        QVariantMap entry;
        entry.insert(QStringLiteral("relativePath"), file.relativePath());
        entry.insert(QStringLiteral("size"), file.size());
        entry.insert(QStringLiteral("hash"), file.hash());
        entry.insert(QStringLiteral("version"), file.version());
        entry.insert(QStringLiteral("lastModified"), file.lastModified().toString(Qt::ISODate));
        result.append(entry);
    }
    return result;
}

QVariantList SharedFolderContext::availableUsers() const
{
    QVariantList list;
    if (!m_userManager) {
        return list;
    }

    qint64 currentId = 0;
    if (const auto id = m_userManager->currentUserId(); id.has_value()) {
        currentId = *id;
    }

    for (const auto &user : m_userManager->allUsers()) {
        if (user.id() == currentId) {
            continue; // on ne se propose pas soi-meme (acces proprietaire implicite)
        }
        QVariantMap entry;
        entry.insert(QStringLiteral("userId"), static_cast<qint64>(user.id()));
        entry.insert(QStringLiteral("username"), user.name());
        list.append(entry);
    }
    return list;
}

QVariantList SharedFolderContext::accessForFolder(qint64 folderId) const
{
    QVariantList result;
    if (!m_manager) {
        return result;
    }

    // allUsers() est appele une seule fois puis indexe par id : evite un
    // aller-retour DB par acces (listes courtes en pratique, mais pas la
    // peine de refaire une recherche a chaque tour de boucle).
    QHash<qint64, QString> usernamesById;
    if (m_userManager) {
        for (const auto &user : m_userManager->allUsers()) {
            usernamesById.insert(user.id(), user.name());
        }
    }

    for (const models::SharedFolderAccess &access : m_manager->accessForFolder(folderId)) {
        QVariantMap entry;
        entry.insert(QStringLiteral("userId"), access.userId());
        entry.insert(QStringLiteral("username"), usernamesById.value(access.userId(), QStringLiteral("(utilisateur supprimé)")));
        entry.insert(QStringLiteral("permission"), models::sharedFolderPermissionToString(access.permission()));
        result.append(entry);
    }
    return result;
}

bool SharedFolderContext::revokeAccess(qint64 folderId, qint64 userId)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    if (!m_manager->revokeAccess(folderId, userId)) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    refresh();
    return true;
}

bool SharedFolderContext::grantAccess(qint64 folderId, qint64 userId, bool allowWrite)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    qint64 grantedBy = 0;
    if (m_userManager) {
        if (const auto id = m_userManager->currentUserId(); id.has_value()) {
            grantedBy = *id;
        }
    }

    const auto permission = allowWrite ? models::SharedFolderPermission::Write
                                       : models::SharedFolderPermission::Read;

    if (!m_manager->grantAccess(folderId, userId, grantedBy, permission)) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    return true;
}

bool SharedFolderContext::changePermission(qint64 folderId, qint64 userId, bool allowWrite)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    // Revoque puis re-accorde avec le nouveau niveau de permission.
    if (!m_manager->revokeAccess(folderId, userId)) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    return grantAccess(folderId, userId, allowWrite);
}

QVariantList SharedFolderContext::syncHistoryForFolder(qint64 folderId, int limit) const
{
    QVariantList result;
    if (!m_syncEngine) {
        return result;
    }

    for (const models::FileSyncOperation &operation : m_syncEngine->historyForFolder(folderId, limit)) {
        QVariantMap entry;
        entry.insert(QStringLiteral("type"), models::syncChangeTypeToString(operation.type()));
        entry.insert(QStringLiteral("relativePath"), operation.relativePath());
        entry.insert(QStringLiteral("oldRelativePath"), operation.oldRelativePath());
        entry.insert(QStringLiteral("version"), operation.version());
        entry.insert(QStringLiteral("createdAt"), operation.createdAt().toString(Qt::ISODate));
        result.append(entry);
    }
    return result;
}

} // namespace core
