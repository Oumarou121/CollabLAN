#include "SharedFolderContext.h"

#include <algorithm>
#include <QHash>
#include <QVariantMap>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QUrl>
#include "models/SharedFolderPermission.h"

namespace core {

SharedFolderContext::SharedFolderContext(QObject *parent)
    : QObject(parent)
    , m_folderModel(new models::SharedFolderModel(this))
    , m_folderFilterProxy(new models::SharedFolderFilterProxy(this))
{
    m_folderFilterProxy->setSourceModel(m_folderModel);
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
        // Rafraîchir l'UI quand un accès est accordé localement (toujours
        // émis), et -- uniquement pour un grant réellement NOUVEAU
        // (isNewGrant, cf. commentaire du signal dans SharedFolderManager.h)
        // -- demander confirmation avant de proposer d'auto-provisionner un
        // dossier DISTANT reçu sans localPath : sans le filtre isNewGrant,
        // ce dialogue réapparaîtrait à chaque reconnexion/catchup pour un
        // partage déjà connu.
        connect(m_manager, &SharedFolderManager::accessGrantedLocal,
                this, [this](qint64 folderId, qint64 userId, bool isNewGrant) {
                    refresh();

                    if (!isNewGrant) {
                        return;
                    }
                    if (!m_userManager || !m_userManager->currentUserId().has_value()
                        || static_cast<qint64>(*m_userManager->currentUserId()) != userId) {
                        return;
                    }

                    const auto folder = m_manager->getFolder(folderId);
                    if (!folder.has_value() || folder->isLocalOrigin() || !folder->localPath().isEmpty()) {
                        return; // dossier local, ou deja provisionne/choisi
                    }

                    QString ownerName;
                    const auto users = m_userManager->allUsers();
                    auto it = std::find_if(users.begin(), users.end(),
                        [&folder](const models::User &u) { return u.id() == folder->ownerId(); });
                    if (it != users.end()) {
                        ownerName = it->name();
                    }

                    const QString suggestedPath = m_manager->previewDefaultLocalPath(folderId).value_or(QString());

                    // Permission accordee a l'utilisateur courant sur ce dossier,
                    // pour affichage d'un badge lecture/ecriture dans la boite de
                    // confirmation (direction visuelle validee sur la maquette).
                    bool allowWrite = false;
                    for (const models::SharedFolderAccess &access : m_manager->accessForFolder(folderId)) {
                        if (access.userId() == userId) {
                            allowWrite = models::canWrite(access.permission());
                            break;
                        }
                    }

                    emit folderShareConfirmationRequested(folderId, folder->name(), ownerName, suggestedPath, allowWrite);
                });
        // Rafraîchir l'UI quand un accès est révoqué localement (toujours émis)
        connect(m_manager, &SharedFolderManager::accessRevokedLocal,
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
        connect(m_syncEngine, &core::sync::SyncEngine::reindexingStarted,
                this, &SharedFolderContext::indexingStarted);
    }
}

void SharedFolderContext::setUserManager(UserManager *manager)
{
    m_userManager = manager;
    if (m_userManager) {
        // Rafraîchir l'UI après login réussi (pour mettre à jour currentUserId)
        connect(m_userManager, &UserManager::loginSucceeded,
                this, [this]() { refresh(); });
    }
}

void SharedFolderContext::setFolderSyncService(core::sync::FolderSyncService *svc)
{
    m_folderSyncService = svc;
    if (m_folderSyncService) {
        // Retransmet conflictDetected a QML pour que SharedFolderView puisse
        // afficher un badge ou une banniere sans connaitre FolderSyncService.
        connect(m_folderSyncService, &core::sync::FolderSyncService::conflictDetected,
                this, &SharedFolderContext::conflictDetected);

        // Retransmet fileIntegrated a QML (fileReceived) ET rafraîchit le
        // modele de dossiers (compteur de fichiers sur les tuiles) : sans
        // cela, un fichier recu du reseau (transfert de synchronisation)
        // n'apparaissait dans l'UI qu'apres avoir quitte puis rouvert
        // l'ecran SharedFolderView, faute de signal ecoute entre-temps.
        connect(m_folderSyncService, &core::sync::FolderSyncService::fileIntegrated,
                this, [this](const QString &folderUuid, const QString &relativePath, bool /*wasConflict*/) {
                    refresh();
                    emit fileReceived(folderUuid, relativePath);
                });

        // Retransmet la progression agrégée d'une rafale de synchronisation
        // (barre de progression globale de l'UI) telle quelle.
        connect(m_folderSyncService, &core::sync::FolderSyncService::folderTransferProgress,
                this, &SharedFolderContext::folderTransferProgress);

        // Unifie folderFilesReceived/folderFilesSent (qui portent chacun le
        // nombre final de fichiers, utile pour la notification texte mais
        // pas pour la barre de progression) en un simple signal "fin de
        // rafale" avec le sens (incoming), pour que l'UI sache quelle barre
        // masquer sans avoir à comparer des noms de dossier.
        connect(m_folderSyncService, &core::sync::FolderSyncService::folderFilesReceived,
                this, [this](const QString &folderUuid, const QString &folderName, int fileCount) {
                    emit folderTransferComplete(folderUuid, folderName, true, fileCount);
                });
        connect(m_folderSyncService, &core::sync::FolderSyncService::folderFilesSent,
                this, [this](const QString &folderUuid, const QString &folderName, int fileCount) {
                    emit folderTransferComplete(folderUuid, folderName, false, fileCount);
                });
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
    QHash<qint64, bool> conflicts;
    for (const models::SharedFolder &folder : folders) {
        counts.insert(folder.id(), m_manager->getFiles(folder.id()).size());
        conflicts.insert(folder.id(), hasConflicts(folder.id()));
    }
    m_folderModel->setFileCounts(counts);
    m_folderModel->setConflicts(conflicts);
}

bool SharedFolderContext::createFolder(const QString &name, const QString &localPath,
                                        const QVariantList &authorizedUserIds, bool allowWrite,
                                        const QString &excludePatterns)
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

    const auto folder = m_manager->createFolder(name, localPath, ownerId, userIds, permission, excludePatterns);
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

    // CORRECTIF PERF (debrief : "l'app ne repond plus" pendant le partage
    // d'un dossier sur un poste peu performant) : le parcours recursif +
    // hash SHA-256 + upserts SQLite (le vrai cout, cf. SharedFolderManager::
    // shareFolder()) est desormais effectue sur un thread dedie via
    // SyncEngine::reindexFolderAsync() -- cet appel retourne IMMEDIATEMENT,
    // avant que l'indexation ne soit terminee. Le resultat (nombre de
    // changements, erreurs eventuelles) arrive plus tard via les signaux
    // deja relayes vers QML : indexingStarted() tout de suite (pour
    // afficher un indicateur "indexation en cours..."), puis
    // folderReindexed() a la fin (pour rafraichir la liste des fichiers --
    // cf. le connect sur SharedFolderManager::folderShared dans
    // setSharedFolderManager(), qui appelle deja refresh()).
    //
    // Sans SyncEngine assigne (cas degrade, ex: certains tests), on
    // retombe sur l'appel synchrone direct a SharedFolderManager --
    // comportement inchange dans ce cas precis.
    if (m_syncEngine) {
        m_syncEngine->reindexFolderAsync(folderId);
        return true;
    }

    const auto changes = m_manager->shareFolder(folderId);
    if (!changes.has_value()) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    refresh();
    return true;
}

bool SharedFolderContext::openFolderLocation(qint64 folderId)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    const auto folder = m_manager->getFolder(folderId);
    if (!folder.has_value()) {
        m_lastErrorString = QStringLiteral("Dossier partagé introuvable");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    // Dossier distant reçu mais pas encore accepté/provisionné (cf.
    // acceptFolderShare()/provisionDefaultLocalPath()) : rien sur le
    // disque a montrer pour l'instant.
    if (folder->localPath().isEmpty()) {
        m_lastErrorString = QStringLiteral("Ce dossier n'a pas encore d'emplacement local (acceptez le partage d'abord)");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    const QDir dir(folder->localPath());
    if (!dir.exists()) {
        // Deplace/supprime manuellement depuis le dernier partage/reindex.
        m_lastErrorString = QStringLiteral("Le chemin local '%1' n'existe plus").arg(folder->localPath());
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    return QDesktopServices::openUrl(QUrl::fromLocalFile(dir.absolutePath()));
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

bool SharedFolderContext::setFolderLocalPath(qint64 folderId, const QString &localPath)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    if (!m_manager->updateFolderLocalPath(folderId, localPath)) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    // Après avoir défini le localPath, déclencher un resync pour récupérer les fichiers
    // depuis le propriétaire du dossier distant
    if (m_folderSyncService) {
        const auto folder = m_manager->getFolder(folderId);
        if (folder.has_value() && !folder->isLocalOrigin()) {
            m_folderSyncService->requestFolderResync(folder->uuid());
        }
    }

    refresh();
    return true;
}

bool SharedFolderContext::acceptFolderShare(qint64 folderId)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    // provisionDefaultLocalPath() cree le dossier sur le disque, persiste
    // le localPath, ET emet SharedFolderManager::folderLocalPathProvisioned
    // -- app/Application.cpp y est connecte pour declencher le resync
    // reseau et la notification, donc rien de plus a faire ici.
    if (!m_manager->provisionDefaultLocalPath(folderId).has_value()) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    refresh();
    return true;
}

void SharedFolderContext::declineFolderShare(qint64 /*folderId*/)
{
    // Intentionnellement un no-op : cf. commentaire Q_INVOKABLE dans le .h.
    // Le dossier reste dans la liste avec un localPath vide ; l'utilisateur
    // pourra choisir un chemin plus tard via setFolderLocalPath().
}

QString SharedFolderContext::excludePatternsForFolder(qint64 folderId) const
{
    if (!m_manager) {
        return QString();
    }
    const auto folder = m_manager->getFolder(folderId);
    return folder.has_value() ? folder->excludePatterns() : QString();
}

bool SharedFolderContext::updateExcludePatterns(qint64 folderId, const QString &excludePatterns)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    if (!m_manager->updateExcludePatterns(folderId, excludePatterns)) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    // Reindexe immediatement (plutot que d'attendre le prochain passage de
    // FolderWatcher) pour que l'effet du nouveau motif soit visible tout de
    // suite dans l'UI : les fichiers desormais exclus doivent disparaitre de
    // la liste sans que l'utilisateur ait a modifier un fichier pour
    // declencher un reindex. Uniquement pertinent pour un dossier dont ce
    // poste est l'origine -- un dossier distant sans localPath local n'a
    // rien a reindexer.
    const auto folder = m_manager->getFolder(folderId);
    if (folder.has_value() && folder->isLocalOrigin()) {
        if (m_syncEngine) {
            m_syncEngine->reindexFolder(folderId);
        } else {
            m_manager->shareFolder(folderId);
        }
    }

    refresh();
    return true;
}

QStringList SharedFolderContext::previewExcludePatternsImpact(qint64 folderId, const QString &excludePatterns) const
{
    if (!m_manager) {
        return {};
    }
    return m_manager->previewExcludePatternsImpact(folderId, excludePatterns);
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

QVariantList SharedFolderContext::getConflicts(qint64 folderId) const
{
    QVariantList result;
    if (!m_manager) {
        return result;
    }

    const auto files = m_manager->getFiles(folderId);
    QSet<QString> activePaths;
    activePaths.reserve(files.size());
    for (const auto &file : files) {
        activePaths.insert(file.relativePath());
    }

    QRegularExpression conflictRegex(QStringLiteral("^(.+) \\(([^)]{6})\\)(\\.[^/\\.]+)?$"));

    for (const auto &file : files) {
        auto match = conflictRegex.match(file.relativePath());
        if (match.hasMatch()) {
            QString basePath = match.captured(1);
            QString shortId = match.captured(2);
            QString ext = match.captured(3);
            QString originalPath = basePath + ext;

            if (activePaths.contains(originalPath)) {
                QVariantMap conflictMap;
                conflictMap.insert(QStringLiteral("relativePath"), originalPath);
                conflictMap.insert(QStringLiteral("conflictPath"), file.relativePath());
                conflictMap.insert(QStringLiteral("shortId"), shortId);
                result.append(conflictMap);
            }
        }
    }

    return result;
}

bool SharedFolderContext::hasConflicts(qint64 folderId) const
{
    if (!m_manager) {
        return false;
    }

    const auto files = m_manager->getFiles(folderId);
    QSet<QString> activePaths;
    activePaths.reserve(files.size());
    for (const auto &file : files) {
        activePaths.insert(file.relativePath());
    }

    QRegularExpression conflictRegex(QStringLiteral("^(.+) \\(([^)]{6})\\)(\\.[^/\\.]+)?$"));

    for (const auto &file : files) {
        auto match = conflictRegex.match(file.relativePath());
        if (match.hasMatch()) {
            QString basePath = match.captured(1);
            QString ext = match.captured(3);
            QString originalPath = basePath + ext;

            if (activePaths.contains(originalPath)) {
                return true;
            }
        }
    }

    return false;
}

bool SharedFolderContext::resolveConflict(qint64 folderId, const QString &relativePath, const QString &conflictPath, const QString &resolution)
{
    if (!m_manager) {
        m_lastErrorString = QStringLiteral("Module Shared Folder non disponible");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    const auto folderOpt = m_manager->getFolder(folderId);
    if (!folderOpt.has_value()) {
        m_lastErrorString = QStringLiteral("Dossier introuvable");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    const auto &folder = folderOpt.value();
    QString localPath = folder.localPath();
    if (localPath.isEmpty()) {
        m_lastErrorString = QStringLiteral("Le dossier local n'est pas configuré");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    QString originalAbsPath = QDir::cleanPath(localPath + QDir::separator() + relativePath);
    QString conflictAbsPath = QDir::cleanPath(localPath + QDir::separator() + conflictPath);

    if (resolution == QStringLiteral("keep_local")) {
        if (QFile::exists(conflictAbsPath)) {
            if (!QFile::remove(conflictAbsPath)) {
                m_lastErrorString = QStringLiteral("Impossible de supprimer le fichier de conflit");
                emit errorOccurred(m_lastErrorString);
                return false;
            }
        }
    } else if (resolution == QStringLiteral("keep_remote")) {
        if (QFile::exists(originalAbsPath)) {
            if (!QFile::remove(originalAbsPath)) {
                m_lastErrorString = QStringLiteral("Impossible de supprimer le fichier original");
                emit errorOccurred(m_lastErrorString);
                return false;
            }
        }
        if (!QFile::rename(conflictAbsPath, originalAbsPath)) {
            m_lastErrorString = QStringLiteral("Impossible de renommer la copie de conflit");
            emit errorOccurred(m_lastErrorString);
            return false;
        }
    } else if (resolution == QStringLiteral("keep_both")) {
        QFileInfo fi(originalAbsPath);
        QString baseName = fi.completeBaseName();
        QString suffix = fi.suffix();
        QString dir = fi.path();

        QString newAbsPath;
        int counter = 1;
        do {
            QString suffixPart = suffix.isEmpty() ? QString() : QStringLiteral(".") + suffix;
            QString newName = (counter == 1)
                ? QStringLiteral("%1 (copie)%2").arg(baseName, suffixPart)
                : QStringLiteral("%1 (copie %2)%3").arg(baseName, QString::number(counter), suffixPart);

            newAbsPath = QDir::cleanPath(dir + QDir::separator() + newName);
            counter++;
        } while (QFile::exists(newAbsPath));

        if (!QFile::rename(conflictAbsPath, newAbsPath)) {
            m_lastErrorString = QStringLiteral("Impossible de renommer la copie de conflit");
            emit errorOccurred(m_lastErrorString);
            return false;
        }
    } else {
        m_lastErrorString = QStringLiteral("Stratégie de résolution inconnue");
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    // Réindexer le dossier pour prendre en compte les changements sur le disque
    bool indexed = false;
    if (m_syncEngine) {
        indexed = m_syncEngine->reindexFolder(folderId) > 0;
    }
    if (!indexed) {
        const auto changes = m_manager->shareFolder(folderId);
        if (!changes.has_value()) {
            m_lastErrorString = m_manager->lastErrorString();
            emit errorOccurred(m_lastErrorString);
            return false;
        }
    }

    refresh();
    return true;
}

} // namespace core