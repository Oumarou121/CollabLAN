#include "SharedFolderManager.h"

#include "DatabaseManager.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSet>
#include <QStringList>

namespace core {

namespace {

/**
 * @brief Filtre d'exclusion (Release 9 partielle) : evite d'indexer et de
 * synchroniser des fichiers techniques/temporaires qui n'ont pas de sens a
 * partager entre postes (fichiers de verrouillage d'editeurs, dossiers de
 * VCS, caches, etc.).
 */
bool isExcludedRelativePath(const QString &relativePath)
{
    static const QSet<QString> excludedDirNames = {
        QStringLiteral(".git"), QStringLiteral(".svn"), QStringLiteral(".hg"),
        QStringLiteral("node_modules"), QStringLiteral("__pycache__"),
    };
    static const QSet<QString> excludedFileNames = {
        QStringLiteral(".DS_Store"), QStringLiteral("Thumbs.db"), QStringLiteral("desktop.ini"),
    };
    static const QSet<QString> excludedSuffixes = {
        QStringLiteral("tmp"), QStringLiteral("temp"), QStringLiteral("obj"),
        QStringLiteral("o"), QStringLiteral("swp"), QStringLiteral("bak"),
        QStringLiteral("crdownload"), QStringLiteral("part"),
    };

    const QStringList segments = relativePath.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    for (const QString &segment : segments) {
        if (excludedDirNames.contains(segment)) return true;
    }

    const QFileInfo info(relativePath);
    const QString fileName = info.fileName();
    if (excludedFileNames.contains(fileName)) return true;
    if (fileName.startsWith(QStringLiteral("~$"))) return true;   // verrou Office
    if (fileName.startsWith(QStringLiteral(".~lock."))) return true; // verrou LibreOffice

    if (excludedSuffixes.contains(info.suffix().toLower())) return true;

    return false;
}

} // namespace

SharedFolderManager::SharedFolderManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
    , m_folderRepository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_fileRepository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_accessRepository(dbManager ? dbManager->database() : QSqlDatabase())
{
}

SharedFolderManager::~SharedFolderManager()
{
}

std::optional<models::SharedFolder> SharedFolderManager::createFolder(const QString &name, const QString &localPath, qint64 ownerId,
                                                                        const QVector<qint64> &authorizedUserIds,
                                                                        models::SharedFolderPermission permission)
{
    if (!m_dbManager) {
        m_lastError = SharedFolderManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return std::nullopt;
    }

    if (name.trimmed().isEmpty()) {
        m_lastError = SharedFolderManagerError::InvalidName;
        m_lastErrorString = QStringLiteral("Le nom du dossier partage ne peut pas etre vide");
        return std::nullopt;
    }

    if (localPath.trimmed().isEmpty()) {
        m_lastError = SharedFolderManagerError::InvalidPath;
        m_lastErrorString = QStringLiteral("Le chemin local ne peut pas etre vide");
        return std::nullopt;
    }

    const QFileInfo pathInfo(localPath);
    if (!pathInfo.exists()) {
        m_lastError = SharedFolderManagerError::InvalidPath;
        m_lastErrorString = QStringLiteral("Le chemin '%1' n'existe pas").arg(localPath);
        return std::nullopt;
    }
    if (!pathInfo.isDir()) {
        m_lastError = SharedFolderManagerError::PathNotDirectory;
        m_lastErrorString = QStringLiteral("'%1' n'est pas un dossier").arg(localPath);
        return std::nullopt;
    }

    models::SharedFolder folder(0, name.trimmed(), pathInfo.absoluteFilePath());
    folder.setOwnerId(ownerId);
    folder.setIsActive(true);

    const auto inserted = m_folderRepository.insert(folder);
    if (!inserted.has_value()) {
        m_lastError = SharedFolderManagerError::DatabaseError;
        m_lastErrorString = m_folderRepository.lastError().isEmpty()
            ? QStringLiteral("Echec de la creation du dossier partage")
            : m_folderRepository.lastError();
        return std::nullopt;
    }

    emit folderCreated(*inserted);

    // Accorde immediatement l'acces aux utilisateurs choisis a la creation
    // (cf. commentaire createFolder() dans le .h). Le proprietaire n'a pas
    // besoin d'une ligne SharedFolderAccess (acces implicite total).
    for (const qint64 userId : authorizedUserIds) {
        if (userId == ownerId) continue;
        grantAccess(inserted->id(), userId, ownerId, permission);
    }

    return inserted;
}

bool SharedFolderManager::removeFolder(qint64 folderId)
{
    if (!m_dbManager) {
        m_lastError = SharedFolderManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return false;
    }

    if (!m_folderRepository.remove(folderId)) {
        m_lastError = SharedFolderManagerError::InvalidFolder;
        m_lastErrorString = m_folderRepository.lastError().isEmpty()
            ? QStringLiteral("Dossier partage introuvable")
            : m_folderRepository.lastError();
        return false;
    }

    emit folderRemoved(folderId);
    return true;
}

QVector<models::SharedFolder> SharedFolderManager::getFolders() const
{
    if (!m_dbManager) {
        return {};
    }
    return m_folderRepository.getAll();
}

QVector<models::SharedFolder> SharedFolderManager::getFolders(qint64 ownerId) const
{
    if (!m_dbManager) {
        return {};
    }
    return m_folderRepository.getByOwnerId(ownerId);
}

std::optional<models::SharedFolder> SharedFolderManager::getFolder(qint64 folderId) const
{
    if (!m_dbManager) {
        return std::nullopt;
    }
    return m_folderRepository.getById(folderId);
}

std::optional<QVector<models::SharedFileChange>> SharedFolderManager::shareFolder(qint64 folderId)
{
    if (!m_dbManager) {
        m_lastError = SharedFolderManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return std::nullopt;
    }

    const auto folder = m_folderRepository.getById(folderId);
    if (!folder.has_value()) {
        m_lastError = SharedFolderManagerError::InvalidFolder;
        m_lastErrorString = QStringLiteral("Dossier partage introuvable (id=%1)").arg(folderId);
        return std::nullopt;
    }

    const QDir rootDir(folder->localPath());
    if (!rootDir.exists()) {
        m_lastError = SharedFolderManagerError::InvalidPath;
        m_lastErrorString = QStringLiteral("Le chemin local '%1' n'existe plus").arg(folder->localPath());
        return std::nullopt;
    }

    // Etat connu AVANT le scan (utilise pour classifier chaque fichier
    // trouve en Create/Update, et pour detecter les renommages ci-dessous).
    const QVector<models::SharedFile> previouslyKnown = m_fileRepository.getByFolderId(folderId);
    QHash<QString, models::SharedFile> previousByRelativePath;
    for (const models::SharedFile &file : previouslyKnown) {
        previousByRelativePath.insert(file.relativePath(), file);
    }

    QVector<models::SharedFileChange> changes;

    // Parcours recursif : chaque fichier trouve est indexe (upsert) avec
    // son chemin RELATIF a la racine du dossier partage (cf. commentaire
    // migration #018 -- independant du chemin absolu, qui peut differer
    // d'un poste a l'autre pour le "meme" dossier logique).
    QSet<QString> seenRelativePaths;
    QDirIterator it(folder->localPath(), QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString absolutePath = it.next();
        const QString relativePath = rootDir.relativeFilePath(absolutePath);

        if (isExcludedRelativePath(relativePath)) {
            // Fichier technique/temporaire (Release 9 partielle) : ni
            // indexe, ni compte comme "vu" -- s'il etait connu d'une
            // indexation precedente (peu probable, ce filtre est nouveau),
            // il sera tombstone plus bas comme tout fichier disparu.
            continue;
        }

        seenRelativePaths.insert(relativePath);

        QFile file(absolutePath);
        if (!file.open(QIODevice::ReadOnly)) {
            // Fichier illisible (permissions, verrouille...) : on l'ignore
            // plutot que d'interrompre l'indexation des autres fichiers.
            continue;
        }
        QCryptographicHash hasher(QCryptographicHash::Sha256);
        if (!hasher.addData(&file)) {
            file.close();
            continue;
        }
        file.close();

        const QFileInfo info(absolutePath);
        const QString newHash = QString::fromLatin1(hasher.result().toHex());

        const auto previousIt = previousByRelativePath.constFind(relativePath);
        const bool existedBefore = (previousIt != previousByRelativePath.constEnd());
        const bool contentChanged = !existedBefore || previousIt->hash() != newHash;

        models::SharedFile sharedFile;
        sharedFile.setFolderId(folderId);
        sharedFile.setRelativePath(relativePath);
        sharedFile.setHash(newHash);
        sharedFile.setSize(info.size());
        sharedFile.setLastModified(info.lastModified());

        const auto upserted = m_fileRepository.upsert(sharedFile);
        if (!upserted.has_value() || !contentChanged) {
            // Pas d'echec silencieux souhaite ici : upsert() peut echouer
            // (verrou base, etc), mais on continue les autres fichiers
            // plutot que d'abandonner toute l'indexation ; simplement pas
            // de SharedFileChange rapporte pour celui-ci.
            continue;
        }

        changes.append(models::SharedFileChange(
            existedBefore ? models::SyncChangeType::Update : models::SyncChangeType::Create,
            *upserted));
    }

    // Fichiers connus en base mais absents du disque : suppression logique
    // (tombstone), sauf si le meme contenu (hash) est reapparu sous un
    // nouveau chemin relatif -- ce cas est alors un renommage/deplacement,
    // pas une suppression suivie d'une creation independante.
    QHash<QString, QString> createdPathsByHash; // hash -> relativePath, pour les Create de cette passe
    for (const models::SharedFileChange &change : changes) {
        if (change.type() == models::SyncChangeType::Create) {
            createdPathsByHash.insert(change.file().hash(), change.file().relativePath());
        }
    }

    for (const models::SharedFile &known : previouslyKnown) {
        if (seenRelativePaths.contains(known.relativePath())) {
            continue; // toujours present, deja traite ci-dessus
        }

        const auto renamedToIt = createdPathsByHash.constFind(known.hash());
        if (!known.hash().isEmpty() && renamedToIt != createdPathsByHash.constEnd()) {
            // Renommage/deplacement detecte : on retire le Create genere
            // plus haut pour ce nouveau chemin et on le remplace par un
            // seul changement Rename (ancien -> nouveau chemin relatif).
            const QString newRelativePath = *renamedToIt;
            for (int i = 0; i < changes.size(); ++i) {
                if (changes.at(i).type() == models::SyncChangeType::Create
                    && changes.at(i).file().relativePath() == newRelativePath) {
                    changes[i] = models::SharedFileChange(
                        models::SyncChangeType::Rename, changes.at(i).file(), known.relativePath());
                    break;
                }
            }
            continue;
        }

        if (m_fileRepository.markDeleted(folderId, known.relativePath())) {
            models::SharedFile tombstoned = known;
            tombstoned.setDeleted(true);
            changes.append(models::SharedFileChange(models::SyncChangeType::Delete, tombstoned));
        }
    }

    const int fileCount = m_fileRepository.count(folderId);
    emit folderShared(folderId, fileCount);
    return changes;
}

QVector<models::SharedFile> SharedFolderManager::getFiles(qint64 folderId) const
{
    if (!m_dbManager) {
        return {};
    }
    return m_fileRepository.getByFolderId(folderId);
}

std::optional<models::SharedFolder> SharedFolderManager::getFolderByUuid(const QString &uuid) const
{
    if (!m_dbManager) {
        return std::nullopt;
    }
    return m_folderRepository.findByUuid(uuid);
}

QVector<models::SharedFolder> SharedFolderManager::getAccessibleFolders(qint64 userId) const
{
    if (!m_dbManager) {
        return {};
    }

    QVector<models::SharedFolder> result = m_folderRepository.getByOwnerId(userId);

    QVector<qint64> grantedFolderIds;
    for (const models::SharedFolderAccess &access : m_accessRepository.listForUser(userId)) {
        grantedFolderIds.append(access.folderId());
    }
    if (!grantedFolderIds.isEmpty()) {
        result += m_folderRepository.getByIds(grantedFolderIds);
    }

    return result;
}

bool SharedFolderManager::grantAccess(qint64 folderId, qint64 userId, qint64 grantedBy,
                                       models::SharedFolderPermission permission, bool broadcastNetwork)
{
    if (!m_dbManager) {
        return false;
    }

    const auto access = m_accessRepository.grant(folderId, userId, permission, grantedBy);
    if (!access.has_value()) {
        return false;
    }

    // Toujours émettre accessGrantedLocal pour le rafraîchissement UI
    QMetaObject::invokeMethod(this, [this, folderId, userId]() {
        emit accessGrantedLocal(folderId, userId);
    }, Qt::QueuedConnection);

    if (broadcastNetwork) {
        // Émettre accessGranted pour la diffusion réseau
        QMetaObject::invokeMethod(this, [this, folderId, userId, permission]() {
            emit accessGranted(folderId, userId, permission);
        }, Qt::QueuedConnection);
    }
    return true;
}

bool SharedFolderManager::revokeAccess(qint64 folderId, qint64 userId, bool broadcastNetwork)
{
    if (!m_dbManager) {
        return false;
    }
    if (!m_accessRepository.revoke(folderId, userId)) {
        return false;
    }

    // Toujours émettre accessRevokedLocal pour le rafraîchissement UI
    QMetaObject::invokeMethod(this, [this, folderId, userId]() {
        emit accessRevokedLocal(folderId, userId);
    }, Qt::QueuedConnection);

    // Émettre accessRevoked pour la diffusion réseau UNIQUEMENT si cette
    // revocation est locale (pas issue d'un message reseau deja recu) --
    // sinon FolderSyncService::announceAccessRevoked() rediffuse l'evenement
    // avec un nouvel origin_machine_id, et chaque pair qui le recoit rappelle
    // revokeAccess() a son tour : boucle de rediffusion infinie entre pairs
    // (et notifications repetees) des qu'au moins deux pairs partagent encore
    // le dossier.
    if (broadcastNetwork) {
        QMetaObject::invokeMethod(this, [this, folderId, userId]() {
            emit accessRevoked(folderId, userId);
        }, Qt::QueuedConnection);
    }

    return true;
}

QVector<models::SharedFolderAccess> SharedFolderManager::accessForFolder(qint64 folderId) const
{
    if (!m_dbManager) {
        return {};
    }
    return m_accessRepository.listForFolder(folderId);
}

std::optional<models::SharedFolder> SharedFolderManager::registerRemoteFolder(const QString &uuid, const QString &name,
                                                                                qint64 ownerId, const QString &originMachineId)
{
    if (!m_dbManager) {
        return std::nullopt;
    }

    const auto existing = m_folderRepository.findByUuid(uuid);
    if (existing.has_value()) {
        return existing; // deja connu localement (idempotent)
    }

    // QString() (constructeur par defaut) est une chaine NULLE (isNull() ==
    // true), pas une chaine vide -- QSqlQuery::bindValue() la lie alors
    // comme un vrai NULL SQL plutot que '', ce qui viole la contrainte
    // "local_path TEXT NOT NULL" (migration 018) et fait echouer insert()
    // silencieusement pour TOUT dossier distant. Un dossier partage
    // replique depuis un autre poste n'a pas de contenu reel sur ce
    // disque (cf. migration 020) : local_path doit donc etre une chaine
    // VIDE, pas nulle.
    models::SharedFolder folder(0, name, QStringLiteral(""));
    folder.setUuid(uuid);
    folder.setOwnerId(ownerId);
    folder.setIsActive(true);
    folder.setOriginMachineId(originMachineId);

    const auto inserted = m_folderRepository.insert(folder);
    if (!inserted.has_value()) {
        return std::nullopt;
    }

    emit folderCreated(*inserted);
    return inserted;
}

bool SharedFolderManager::updateFolderLocalPath(qint64 folderId, const QString &localPath)
{
    if (!m_dbManager) {
        m_lastError = SharedFolderManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager non disponible");
        return false;
    }

    const auto folder = m_folderRepository.getById(folderId);
    if (!folder.has_value()) {
        m_lastError = SharedFolderManagerError::InvalidFolder;
        m_lastErrorString = QStringLiteral("Dossier introuvable");
        return false;
    }

    // Vérifier que le chemin existe et est un dossier
    const QDir dir(localPath);
    if (!dir.exists()) {
        m_lastError = SharedFolderManagerError::InvalidPath;
        m_lastErrorString = QStringLiteral("Le chemin n'existe pas : %1").arg(localPath);
        return false;
    }

    models::SharedFolder updated = *folder;
    updated.setLocalPath(localPath);

    if (!m_folderRepository.update(updated)) {
        m_lastError = SharedFolderManagerError::DatabaseError;
        m_lastErrorString = m_folderRepository.lastError();
        return false;
    }

    return true;
}

} // namespace core