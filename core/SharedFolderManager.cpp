#include "SharedFolderManager.h"

#include "DatabaseManager.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QStringList>

namespace core {

namespace {

/**
 * @brief Filtre d'exclusion (Release 9 partielle) : evite d'indexer et de
 * synchroniser des fichiers techniques/temporaires qui n'ont pas de sens a
 * partager entre postes (fichiers de verrouillage d'editeurs, dossiers de
 * VCS, caches, etc.).
 *
 * userPatterns (debrief point #4, sync selective) : motifs glob
 * SUPPLEMENTAIRES propres a un dossier partage donne (cf.
 * models::SharedFolder::excludePatterns(), rempli via createFolder()/
 * updateExcludePatterns()), en plus des exclusions codees en dur
 * ci-dessus qui restent toujours actives. Chaque motif est teste :
 *  - contre le chemin relatif complet (ex: "docs/*.log" exclut tous les
 *    .log du sous-dossier docs) ;
 *  - contre chaque segment de dossier ET le nom de fichier pris seuls
 *    (ex: "drafts" exclut tout le sous-arbre "drafts/", sans avoir a
 *    ecrire "drafts/*" ; "*.log" exclut n'importe quel .log a n'importe
 *    quelle profondeur, pas seulement a la racine).
 * Comparaison insensible a la casse (usage mixte Windows/Linux en LAN).
 */
// Exclusions toujours actives, aussi affichees telles quelles dans l'interface
// (SharedFolderManager::builtinExcludePatterns).
const QStringList &excludedDirNameList()
{
    static const QStringList names = {
        QStringLiteral(".git"), QStringLiteral(".svn"), QStringLiteral(".hg"),
        QStringLiteral("node_modules"), QStringLiteral("__pycache__"),
    };
    return names;
}
const QStringList &excludedFileNameList()
{
    static const QStringList names = {
        QStringLiteral(".DS_Store"), QStringLiteral("Thumbs.db"), QStringLiteral("desktop.ini"),
    };
    return names;
}
const QStringList &excludedSuffixList()
{
    // localink-tmp : copie temporaire d'un fichier recu, le temps du
    // remplacement (FolderSyncService::replaceFileSafely).
    static const QStringList suffixes = {
        QStringLiteral("tmp"), QStringLiteral("temp"), QStringLiteral("obj"),
        QStringLiteral("o"), QStringLiteral("swp"), QStringLiteral("bak"),
        QStringLiteral("crdownload"), QStringLiteral("part"), QStringLiteral("localink-tmp"),
    };
    return suffixes;
}

bool isExcludedRelativePath(const QString &relativePath, const QVector<QRegularExpression> &userPatterns = {})
{
    static const QSet<QString> excludedDirNames(excludedDirNameList().cbegin(), excludedDirNameList().cend());
    static const QSet<QString> excludedFileNames(excludedFileNameList().cbegin(), excludedFileNameList().cend());
    static const QSet<QString> excludedSuffixes(excludedSuffixList().cbegin(), excludedSuffixList().cend());

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

    for (const QRegularExpression &regex : userPatterns) {
        if (!regex.isValid()) continue; // deja filtre par normalizeExcludePatterns(), defense en profondeur

        if (regex.match(relativePath).hasMatch()) return true;
        if (regex.match(fileName).hasMatch()) return true;
        for (const QString &segment : segments) {
            if (regex.match(segment).hasMatch()) return true;
        }
    }

    return false;
}

/**
 * @brief Parse la chaine brute stockee dans SharedFolder::excludePatterns()
 * (motifs separes par des virgules) en une liste de motifs individuels,
 * en supprimant les espaces superflus et les entrees vides (ex: virgule
 * finale). Utilise a la fois pour construire la liste passee a
 * isExcludedRelativePath() (shareFolder()) et pour valider une saisie
 * utilisateur (createFolder()/updateExcludePatterns()).
 */
QStringList parseExcludePatterns(const QString &raw)
{
    QStringList patterns;
    const QStringList parts = raw.split(QLatin1Char(','), Qt::SkipEmptyParts);
    patterns.reserve(parts.size());
    for (const QString &part : parts) {
        const QString trimmed = part.trimmed();
        if (!trimmed.isEmpty()) {
            patterns.append(trimmed);
        }
    }
    return patterns;
}

/**
 * @brief Compile chaque motif de userPatterns en QRegularExpression, une
 * seule fois par appel (a la difference de l'ancienne version qui
 * recompilait un QRegularExpression par motif ET par fichier a l'interieur
 * de isExcludedRelativePath() -- cout non negligeable une fois combine a
 * l'optimisation du debrief point #1, qui fait que le hash SHA-256 n'est
 * plus le poste dominant sur un scan de dossier inchange).
 */
QVector<QRegularExpression> compileExcludePatterns(const QStringList &userPatterns)
{
    QVector<QRegularExpression> compiled;
    compiled.reserve(userPatterns.size());
    for (const QString &pattern : userPatterns) {
        compiled.append(QRegularExpression(
            QRegularExpression::wildcardToRegularExpression(pattern),
            QRegularExpression::CaseInsensitiveOption));
    }
    return compiled;
}

/**
 * @brief Valide une chaine de motifs telle que saisie par l'utilisateur.
 * Chaque motif doit produire une expression reguliere valide une fois
 * converti via QRegularExpression::wildcardToRegularExpression() -- en
 * pratique, un glob simple (*, ?, []) est toujours valide ; ce garde-fou
 * protege surtout contre une saisie completement degenerate. Retourne la
 * chaine normalisee (motifs retrimmes, rejoints par ", ") dans
 * *normalized si non nul et que la validation reussit.
 */
bool validateExcludePatterns(const QString &raw, QString *normalized, QString *errorMessage)
{
    const QStringList patterns = parseExcludePatterns(raw);
    for (const QString &pattern : patterns) {
        const QRegularExpression regex(QRegularExpression::wildcardToRegularExpression(pattern));
        if (!regex.isValid()) {
            if (errorMessage) {
                *errorMessage = QStringLiteral("Motif d'exclusion invalide : '%1'").arg(pattern);
            }
            return false;
        }
    }
    if (normalized) {
        *normalized = patterns.join(QStringLiteral(", "));
    }
    return true;
}

} // namespace

QStringList SharedFolderManager::builtinExcludePatterns()
{
    QStringList patterns;
    for (const QString &name : excludedDirNameList())
        patterns << name + QLatin1Char('/');
    patterns << excludedFileNameList();
    patterns << QStringLiteral("~$*") << QStringLiteral(".~lock.*");
    for (const QString &suffix : excludedSuffixList())
        patterns << QStringLiteral("*.") + suffix;
    return patterns;
}

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
                                                                        models::SharedFolderPermission permission,
                                                                        const QString &excludePatterns)
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

    QString normalizedExcludePatterns;
    QString excludePatternsError;
    if (!validateExcludePatterns(excludePatterns, &normalizedExcludePatterns, &excludePatternsError)) {
        m_lastError = SharedFolderManagerError::InvalidExcludePatterns;
        m_lastErrorString = excludePatternsError;
        return std::nullopt;
    }

    models::SharedFolder folder(0, name.trimmed(), pathInfo.absoluteFilePath());
    folder.setOwnerId(ownerId);
    folder.setIsActive(true);
    folder.setExcludePatterns(normalizedExcludePatterns);

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

    // Motifs d'exclusion propres a CE dossier (debrief point #4), en plus
    // des exclusions codees en dur toujours actives dans
    // isExcludedRelativePath(). Parse une seule fois avant la boucle
    // plutot qu'a chaque fichier.
    const QVector<QRegularExpression> userExcludePatterns =
        compileExcludePatterns(parseExcludePatterns(folder->excludePatterns()));

    // Parcours recursif : chaque fichier trouve est indexe (upsert) avec
    // son chemin RELATIF a la racine du dossier partage (cf. commentaire
    // migration #018 -- independant du chemin absolu, qui peut differer
    // d'un poste a l'autre pour le "meme" dossier logique).
    QSet<QString> seenRelativePaths;
    // Liens symboliques ignores : un lien vers un fichier hors du dossier
    // l'exposait (annonce aux membres) sans pouvoir le leur envoyer (le
    // controle de chemin refuse les cibles hors du dossier).
    QDirIterator it(folder->localPath(), QDir::Files | QDir::NoDotAndDotDot | QDir::NoSymLinks,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString absolutePath = it.next();
        const QString relativePath = rootDir.relativeFilePath(absolutePath);

        if (isExcludedRelativePath(relativePath, userExcludePatterns)) {
            // Fichier technique/temporaire (Release 9 partielle) : ni
            // indexe, ni compte comme "vu" -- s'il etait connu d'une
            // indexation precedente (peu probable, ce filtre est nouveau),
            // il sera tombstone plus bas comme tout fichier disparu.
            continue;
        }

        seenRelativePaths.insert(relativePath);

        const QFileInfo info(absolutePath);
        const auto previousIt = previousByRelativePath.constFind(relativePath);
        const bool existedBefore = (previousIt != previousByRelativePath.constEnd());

        // Optimisation (debrief perf, point #1) : taille + date de derniere
        // modification viennent d'un simple stat() (QFileInfo, deja fait
        // pour parcourir le dossier), sans lire le contenu. Si les deux
        // sont identiques a la derniere indexation connue, on considere le
        // fichier inchange et on evite la lecture complete + le SHA-256 --
        // c'est cette lecture/hash qui coutait cher sur de gros dossiers a
        // chaque notification de FolderWatcher, meme pour un seul fichier
        // modifie. Comparaison de lastModified() a la SECONDE pres :
        // SharedFileRepository persiste les dates en Qt::ISODate, qui
        // tronque les millisecondes -- comparer au msec pres aurait rendu
        // ce raccourci inoperant a quasi tous les coups.
        //
        // Limite acceptee (comme rsync/git en mode par defaut) : un fichier
        // modifie en place avec exactement la meme taille ET la meme
        // seconde de mtime que l'etat connu ne sera pas detecte. Cas
        // extremement rare en usage reel (necessite un outil qui force la
        // mtime), et le prochain evenement watcher (qui met a jour la
        // mtime) rattrapera de toute facon la modification.
        const bool metadataUnchanged = existedBefore
            && !previousIt->hash().isEmpty()
            && previousIt->size() == info.size()
            && previousIt->lastModified().toUTC().toSecsSinceEpoch()
                   == info.lastModified().toUTC().toSecsSinceEpoch();

        if (metadataUnchanged) {
            continue; // rien a relire, rien a rapporter : fichier inchange
        }

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

        const QString newHash = QString::fromLatin1(hasher.result().toHex());
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

        models::SharedFileChange change(
            existedBefore ? models::SyncChangeType::Update : models::SyncChangeType::Create, *upserted);
        // Version dont part cette modification : un destinataire qui l'a
        // exactement avance sans conflit (cf. FolderSyncService::integrateReceivedFile).
        if (existedBefore)
            change.setPreviousHash(previousIt->hash());
        changes.append(change);
    }

    // Fichiers connus en base mais absents du disque : suppression logique
    // (tombstone), sauf si le meme contenu (hash) est reapparu sous un
    // nouveau chemin relatif -- ce cas est alors un renommage/deplacement,
    // pas une suppression suivie d'une creation independante.
    QHash<QString, QString> createdPathsByHash; // hash -> relativePath, pour les Create de cette passe
    QSet<QString> consumedRenamePaths;
    for (const models::SharedFileChange &change : changes) {
        if (change.type() == models::SyncChangeType::Create) {
            createdPathsByHash.insert(change.file().hash(), change.file().relativePath());
        }
    }

    for (const models::SharedFile &known : previouslyKnown) {
        if (seenRelativePaths.contains(known.relativePath())) {
            continue; // toujours present, deja traite ci-dessus
        }

        // CORRECTIF (suppression en masse au partage) : une ligne encore
        // pending_download=true n'est qu'un placeholder de rattrapage
        // (FolderSyncService::registerCatchupPlaceholder()) -- son
        // contenu reel n'a jamais existe sur CE disque, donc son absence
        // ici ne veut pas dire "supprime", juste "pas encore telecharge".
        // La tombstoner ferait diffuser un Delete pour un fichier qui,
        // ailleurs sur le reseau, existe toujours bel et bien. Le
        // telechargement en cours (requestFolderResync()) mettra ce flag
        // a jour via integrateReceivedFile() une fois le contenu recu.
        if (known.pendingDownload()) {
            continue;
        }

        const auto renamedToIt = createdPathsByHash.constFind(known.hash());
        if (!known.hash().isEmpty() && renamedToIt != createdPathsByHash.constEnd()
            && !consumedRenamePaths.contains(*renamedToIt)) {
            // Renommage/deplacement detecte : on retire le Create genere
            // plus haut pour ce nouveau chemin et on le remplace par un
            // seul changement Rename (ancien -> nouveau chemin relatif).
            const QString newRelativePath = *renamedToIt;
            bool convertedToRename = false;
            for (int i = 0; i < changes.size(); ++i) {
                if (changes.at(i).type() == models::SyncChangeType::Create
                    && changes.at(i).file().relativePath() == newRelativePath) {
                    // Le scan a deja insere une ligne pour le nouveau nom.
                    // Supprimer cette ligne avant de déplacer la ligne
                    // existante évite de laisser deux chemins pour le même
                    // fichier dans SharedFiles.
                    const qint64 newFileId = changes.at(i).file().id();
                    if (m_fileRepository.remove(newFileId)
                        && m_fileRepository.renameFile(folderId, known.relativePath(), newRelativePath)) {
                        const auto renamedFile =
                            m_fileRepository.findByRelativePath(folderId, newRelativePath);
                        if (renamedFile.has_value()) {
                            changes[i] = models::SharedFileChange(
                                models::SyncChangeType::Rename, *renamedFile, known.relativePath());
                            convertedToRename = true;
                            consumedRenamePaths.insert(newRelativePath);
                        }
                    }
                    break;
                }
            }
            if (convertedToRename)
                continue;
        }

        if (m_fileRepository.markDeleted(folderId, known.relativePath())) {
            models::SharedFile tombstoned = known;
            tombstoned.setDeleted(true);
            models::SharedFileChange change(models::SyncChangeType::Delete, tombstoned);
            // Version supprimee : un destinataire qui l'a modifiee entre-temps
            // garde sa modification (cf. FolderSyncService::applyRemoteDelete).
            change.setPreviousHash(known.hash());
            changes.append(change);
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

QHash<qint64, int> SharedFolderManager::fileCountsByFolder() const
{
    if (!m_dbManager) {
        return {};
    }
    return m_fileRepository.countsByFolder();
}

QVector<models::SharedFile> SharedFolderManager::conflictCandidates(qint64 folderId) const
{
    if (!m_dbManager) {
        return {};
    }
    return m_fileRepository.conflictCandidates(folderId);
}

bool SharedFolderManager::hasActiveFile(qint64 folderId, const QString &relativePath) const
{
    if (!m_dbManager) {
        return false;
    }
    const auto file = m_fileRepository.findByRelativePath(folderId, relativePath);
    return file.has_value() && !file->deleted();
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

    // A verifier AVANT le grant() (qui est un UPSERT) : c'est la seule
    // facon de savoir si cette paire (folderId, userId) est vraiment
    // nouvelle, ou si ce grantAccess() ne fait que re-appliquer un acces
    // deja connu (cf. commentaire accessGrantedLocal() dans le .h -- ce
    // second cas survient a chaque reconnexion/catchup hors-ligne, ou
    // FolderSyncService::handleFolderAccessGranted() rappelle grantAccess()
    // sans condition).
    const bool isNewGrant =
        m_accessRepository.permissionFor(folderId, userId) == models::SharedFolderPermission::None;

    const auto access = m_accessRepository.grant(folderId, userId, permission, grantedBy);
    if (!access.has_value()) {
        return false;
    }

    // Toujours émettre accessGrantedLocal pour le rafraîchissement UI, mais
    // avec isNewGrant pour que les abonnés qui declenchent une action
    // visible UNE SEULE FOIS par partage (notification, confirmation) ne se
    // redeclenchent pas a chaque repetition idempotente du meme grant.
    QMetaObject::invokeMethod(this, [this, folderId, userId, isNewGrant]() {
        emit accessGrantedLocal(folderId, userId, isNewGrant);
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

bool SharedFolderManager::reconcileFolderOrigin(qint64 folderId, const QString &originMachineId)
{
    if (!m_dbManager) {
        return false;
    }
    if (!m_folderRepository.updateOriginMachineId(folderId, originMachineId)) {
        qWarning() << "[SharedFolderManager] reconcileFolderOrigin: echec pour le dossier"
                   << folderId << "->" << originMachineId;
        return false;
    }
    return true;
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

    // Meme suite que pour le chemin par defaut (provisionDefaultLocalPath) :
    // surveillance pour un membre en ecriture, puis demande du contenu. Sans
    // ce signal, un dossier accepte dans un emplacement choisi n'etait pas
    // surveille : les modifications du membre ne repartaient jamais.
    if (QDir::cleanPath(folder->localPath()) != QDir::cleanPath(localPath))
        emit folderLocalPathProvisioned(folderId, localPath);
    return true;
}

void SharedFolderManager::setSharedFoldersBaseDirOverrideForTests(const QString &baseDir)
{
    m_sharedFoldersBaseDirOverride = baseDir;
}

std::optional<QString> SharedFolderManager::previewDefaultLocalPath(qint64 folderId) const
{
    const auto folder = m_folderRepository.getById(folderId);
    if (!folder.has_value()) {
        return std::nullopt;
    }

    if (!folder->localPath().isEmpty()) {
        return folder->localPath(); // deja assigne (choisi par l'utilisateur ou provisionne avant)
    }

    // Un dossier d'origine LOCALE a toujours un localPath (choisi
    // explicitement a la creation, cf. createFolder()) : localPath vide ne
    // devrait donc jamais arriver ici pour un dossier local.
    if (folder->isLocalOrigin()) {
        return std::nullopt;
    }

    const QString baseDir = m_sharedFoldersBaseDirOverride.isEmpty()
        ? QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
              + QStringLiteral("/LocaLink Shared Folders")
        : m_sharedFoldersBaseDirOverride;

    // Assainit le nom pour l'utiliser comme nom de dossier sur le disque :
    // caracteres interdits par Windows/NTFS (le proprietaire distant a pu
    // les utiliser sur un OS plus permissif) remplaces par '_' plutot que
    // supprimes, pour rester lisible sans creer de collisions artificielles
    // entre deux noms qui ne differaient que par un caractere interdit.
    QString sanitizedName = folder->name().trimmed();
    static const QRegularExpression forbiddenChars(QStringLiteral("[\\\\/:*?\"<>|]"));
    sanitizedName.replace(forbiddenChars, QStringLiteral("_"));
    if (sanitizedName.isEmpty()) {
        sanitizedName = QStringLiteral("Dossier partage");
    }

    // Desambiguisation ("Projet", "Projet (2)", ...) : deux pairs peuvent
    // partager un dossier du meme nom, et ce poste peut recevoir 2 dossiers
    // LOGIQUEMENT distincts (uuid different) qui portent le meme nom. On
    // verifie a la fois l'absence sur le disque ET l'absence d'un autre
    // SharedFolder deja connu pointant vers ce chemin -- une simple
    // verification disque ne suffirait pas si le dossier candidat n'existe
    // pas encore mais est deja reserve par un autre SharedFolder de cette
    // meme passe (provisionnement de plusieurs dossiers recus d'affilee).
    QSet<QString> reservedPaths;
    for (const models::SharedFolder &existing : m_folderRepository.getAll()) {
        if (!existing.localPath().isEmpty()) {
            reservedPaths.insert(QDir::cleanPath(existing.localPath()));
        }
    }

    QString candidatePath = QDir::cleanPath(baseDir + QLatin1Char('/') + sanitizedName);
    for (int suffix = 2; QDir(candidatePath).exists() || reservedPaths.contains(candidatePath); ++suffix) {
        candidatePath = QDir::cleanPath(
            QStringLiteral("%1/%2 (%3)").arg(baseDir, sanitizedName).arg(suffix));
    }

    return candidatePath;
}

std::optional<QString> SharedFolderManager::provisionDefaultLocalPath(qint64 folderId)
{
    if (!m_dbManager) {
        m_lastError = SharedFolderManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager non disponible");
        return std::nullopt;
    }

    const auto folder = m_folderRepository.getById(folderId);
    if (!folder.has_value()) {
        m_lastError = SharedFolderManagerError::InvalidFolder;
        m_lastErrorString = QStringLiteral("Dossier introuvable");
        return std::nullopt;
    }

    if (!folder->localPath().isEmpty()) {
        return folder->localPath(); // deja assigne (choisi par l'utilisateur ou provisionne avant) : no-op
    }

    if (folder->isLocalOrigin()) {
        m_lastError = SharedFolderManagerError::InvalidFolder;
        m_lastErrorString = QStringLiteral("Dossier d'origine locale sans chemin -- etat inattendu");
        return std::nullopt;
    }

    const auto candidate = previewDefaultLocalPath(folderId);
    if (!candidate.has_value()) {
        m_lastError = SharedFolderManagerError::InvalidFolder;
        m_lastErrorString = QStringLiteral("Impossible de calculer un chemin par defaut");
        return std::nullopt;
    }
    const QString candidatePath = *candidate;

    if (!QDir().mkpath(candidatePath)) {
        m_lastError = SharedFolderManagerError::InvalidPath;
        m_lastErrorString = QStringLiteral("Impossible de creer le dossier local par defaut : %1").arg(candidatePath);
        return std::nullopt;
    }

    models::SharedFolder updated = *folder;
    updated.setLocalPath(candidatePath);
    if (!m_folderRepository.update(updated)) {
        m_lastError = SharedFolderManagerError::DatabaseError;
        m_lastErrorString = m_folderRepository.lastError();
        return std::nullopt;
    }

    emit folderLocalPathProvisioned(folderId, candidatePath);
    return candidatePath;
}

bool SharedFolderManager::isPathExcluded(qint64 folderId, const QString &relativePath) const
{
    const auto folder = m_folderRepository.getById(folderId);
    if (!folder.has_value()) {
        return false;
    }

    const QVector<QRegularExpression> userExcludePatterns =
        compileExcludePatterns(parseExcludePatterns(folder->excludePatterns()));
    return isExcludedRelativePath(relativePath, userExcludePatterns);
}

bool SharedFolderManager::updateExcludePatterns(qint64 folderId, const QString &excludePatterns)
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

    QString normalizedExcludePatterns;
    QString excludePatternsError;
    if (!validateExcludePatterns(excludePatterns, &normalizedExcludePatterns, &excludePatternsError)) {
        m_lastError = SharedFolderManagerError::InvalidExcludePatterns;
        m_lastErrorString = excludePatternsError;
        return false;
    }

    models::SharedFolder updated = *folder;
    updated.setExcludePatterns(normalizedExcludePatterns);

    if (!m_folderRepository.update(updated)) {
        m_lastError = SharedFolderManagerError::DatabaseError;
        m_lastErrorString = m_folderRepository.lastError();
        return false;
    }

    return true;
}

QStringList SharedFolderManager::previewExcludePatternsImpact(qint64 folderId, const QString &candidateExcludePatterns) const
{
    if (!m_dbManager) {
        return {};
    }

    QString normalized;
    QString errorMessage;
    if (!validateExcludePatterns(candidateExcludePatterns, &normalized, &errorMessage)) {
        // Motif malforme : rien a previsualiser (le dialogue affichera sa
        // propre erreur de validation au moment de l'enregistrement reel).
        return {};
    }

    const QVector<QRegularExpression> candidatePatterns =
        compileExcludePatterns(parseExcludePatterns(normalized));
    if (candidatePatterns.isEmpty()) {
        return {}; // aucun motif candidat : aucun fichier deja indexe ne peut devenir exclu
    }

    // getByFolderId() ne renvoie deja que les fichiers non supprimes (filtre
    // "deleted = 0" cote SQL) : un fichier deja tombstone (exclu par un
    // motif precedent, ou disparu du disque) n'a pas d'impact supplementaire
    // a signaler ici, pas besoin de refiltrer.
    QStringList impacted;
    for (const models::SharedFile &file : m_fileRepository.getByFolderId(folderId)) {
        // isExcludedRelativePath() teste aussi les exclusions codees en dur,
        // mais un fichier deja indexe ne peut par construction pas les
        // matcher (shareFolder() ne les indexe jamais) -- seuls les motifs
        // candidats ci-dessous peuvent donc faire basculer le resultat.
        if (isExcludedRelativePath(file.relativePath(), candidatePatterns)) {
            impacted.append(file.relativePath());
        }
    }

    impacted.sort(Qt::CaseInsensitive);
    return impacted;
}

} // namespace core
