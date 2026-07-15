#include "FolderWatcher.h"

#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileSystemWatcher>
#include <QSet>

namespace core::sync {

namespace {

/// Dossiers techniques a ne jamais surveiller : un depot .git peut contenir
/// des milliers de sous-dossiers (.git/objects/xx/...), ce qui peut faire
/// echouer silencieusement QFileSystemWatcher::addPaths() sur certains OS
/// (limite de handles ReadDirectoryChangesW sur Windows notamment) -- sans
/// garantie que la racine du dossier partage reste dans le lot qui reussit,
/// puisque watchedDirectories est un QSet (ordre non garanti). Meme liste
/// que isExcludedRelativePath() dans SharedFolderManager.cpp (dupliquee ici
/// faute d'export -- a factoriser si un troisieme site en a besoin).
bool isWatchExcludedDirName(const QString &dirName)
{
    static const QSet<QString> excludedDirNames = {
        QStringLiteral(".git"), QStringLiteral(".svn"), QStringLiteral(".hg"),
        QStringLiteral("node_modules"), QStringLiteral("__pycache__"),
    };
    return excludedDirNames.contains(dirName);
}

} // namespace

FolderWatcher::FolderWatcher(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
{
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &FolderWatcher::onDirectoryChanged);
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, &FolderWatcher::onFileChanged);
}

FolderWatcher::~FolderWatcher()
{
    qDeleteAll(m_debounceTimers);
}

void FolderWatcher::watchFolder(qint64 folderId, const QString &rootPath, const QStringList &knownRelativePaths)
{
    unwatchFolder(folderId);

    WatchedFolder watched;
    watched.rootPath = rootPath;

    const QDir rootDir(rootPath);

    // Surveille la racine et tous les sous-dossiers : seul moyen avec
    // QFileSystemWatcher de detecter un ajout/suppression/renommage
    // d'entree (fichier ou sous-dossier) sans deja connaitre son nom.
    watched.watchedDirectories.insert(rootPath);
    m_directoryToFolderId.insert(rootPath, folderId);

    QDirIterator dirIt(rootPath, QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (dirIt.hasNext()) {
        const QString absoluteDir = dirIt.next();
        if (isWatchExcludedDirName(dirIt.fileName())) {
            // N'ajoute pas ce dossier (.git, node_modules...) a la
            // surveillance. QDirIterator::Subdirectories n'offre pas de
            // moyen d'elaguer une branche : il continuera de lister son
            // contenu (cout de scan inchange), mais aucune de ces entrees
            // ne sera passee a addPaths().
            continue;
        }
        watched.watchedDirectories.insert(absoluteDir);
        m_directoryToFolderId.insert(absoluteDir, folderId);
    }

    // Surveille aussi chaque fichier deja connu : seul moyen de detecter
    // une modification de CONTENU en place (directoryChanged() ne
    // declenche que sur ajout/suppression/renommage d'entrees, jamais sur
    // une ecriture dans un fichier existant).
    for (const QString &relativePath : knownRelativePaths) {
        const QString absolutePath = rootDir.absoluteFilePath(relativePath);
        watched.watchedFilePaths.insert(absolutePath);
        m_fileToFolderId.insert(absolutePath, folderId);
    }

    QStringList allPaths;
    allPaths.reserve(watched.watchedDirectories.size() + watched.watchedFilePaths.size());
    for (const QString &dir : watched.watchedDirectories) allPaths.append(dir);
    for (const QString &file : watched.watchedFilePaths) allPaths.append(file);
    if (!allPaths.isEmpty()) {
        const QStringList failed = m_watcher->addPaths(allPaths);
        if (!failed.isEmpty()) {
            qWarning() << "[FolderWatcher] addPaths() a echoue pour" << failed.size()
                       << "chemin(s) sur" << allPaths.size() << "-- ces changements ne seront"
                       << "PAS detectes automatiquement (dossier :" << rootPath << ")" << failed;
        }
    }

    m_folders.insert(folderId, watched);
}

void FolderWatcher::unwatchFolder(qint64 folderId)
{
    const auto it = m_folders.constFind(folderId);
    if (it == m_folders.constEnd()) {
        return;
    }

    QStringList pathsToRemove;
    for (const QString &dir : it->watchedDirectories) {
        pathsToRemove.append(dir);
        m_directoryToFolderId.remove(dir);
    }
    for (const QString &file : it->watchedFilePaths) {
        pathsToRemove.append(file);
        m_fileToFolderId.remove(file);
    }
    if (!pathsToRemove.isEmpty()) {
        m_watcher->removePaths(pathsToRemove);
    }

    m_folders.remove(folderId);

    if (QTimer *timer = m_debounceTimers.take(folderId)) {
        timer->deleteLater();
    }
}

void FolderWatcher::refreshWatchedFiles(qint64 folderId, const QStringList &knownRelativePaths)
{
    const auto it = m_folders.find(folderId);
    if (it == m_folders.end()) {
        return;
    }

    const QDir rootDir(it->rootPath);
    QSet<QString> desiredAbsolutePaths;
    for (const QString &relativePath : knownRelativePaths) {
        desiredAbsolutePaths.insert(rootDir.absoluteFilePath(relativePath));
    }

    // Fichiers plus present (supprimes/renommes) : ne plus surveiller.
    QStringList toRemove;
    for (const QString &watchedFile : it->watchedFilePaths) {
        if (!desiredAbsolutePaths.contains(watchedFile)) {
            toRemove.append(watchedFile);
            m_fileToFolderId.remove(watchedFile);
        }
    }
    if (!toRemove.isEmpty()) {
        m_watcher->removePaths(toRemove);
        for (const QString &path : toRemove) it->watchedFilePaths.remove(path);
    }

    // Nouveaux fichiers : a surveiller pour detecter leurs futures
    // modifications de contenu en place.
    QStringList toAdd;
    for (const QString &desired : desiredAbsolutePaths) {
        if (!it->watchedFilePaths.contains(desired)) {
            toAdd.append(desired);
            it->watchedFilePaths.insert(desired);
            m_fileToFolderId.insert(desired, folderId);
        }
    }
    if (!toAdd.isEmpty()) {
        m_watcher->addPaths(toAdd);
    }

    // Nouveaux sous-dossiers eventuellement crees depuis le dernier scan :
    // il faut aussi les surveiller pour capter de futurs ajouts/suppressions
    // en leur sein.
    QDirIterator dirIt(it->rootPath, QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    QStringList newDirs;
    while (dirIt.hasNext()) {
        const QString absoluteDir = dirIt.next();
        if (isWatchExcludedDirName(dirIt.fileName())) {
            continue;
        }
        if (!it->watchedDirectories.contains(absoluteDir)) {
            newDirs.append(absoluteDir);
            it->watchedDirectories.insert(absoluteDir);
            m_directoryToFolderId.insert(absoluteDir, folderId);
        }
    }
    if (!newDirs.isEmpty()) {
        const QStringList failed = m_watcher->addPaths(newDirs);
        if (!failed.isEmpty()) {
            qWarning() << "[FolderWatcher] addPaths() (refresh) a echoue pour" << failed.size()
                       << "chemin(s) -- dossier :" << it->rootPath << failed;
        }
    }
}

void FolderWatcher::setDebounceInterval(int milliseconds)
{
    m_debounceIntervalMs = milliseconds;
}

void FolderWatcher::onDirectoryChanged(const QString &path)
{
    const auto it = m_directoryToFolderId.constFind(path);
    if (it != m_directoryToFolderId.constEnd()) {
        scheduleNotification(it.value());
    }
}

void FolderWatcher::onFileChanged(const QString &path)
{
    const auto it = m_fileToFolderId.constFind(path);
    if (it != m_fileToFolderId.constEnd()) {
        scheduleNotification(it.value());
    }

    // Qt cesse de surveiller un fichier une fois qu'il a ete signale comme
    // modifie si son inode a change (ex: certains editeurs remplacent le
    // fichier plutot que de l'ecrire en place) -- on le re-ajoute pour
    // continuer a detecter ses modifications futures. Sans effet s'il a
    // ete supprime (le prochain rescan/refreshWatchedFiles() le retirera).
    if (QFile::exists(path) && !m_watcher->files().contains(path)) {
        m_watcher->addPath(path);
    }
}

void FolderWatcher::scheduleNotification(qint64 folderId)
{
    QTimer *timer = m_debounceTimers.value(folderId, nullptr);
    if (!timer) {
        timer = new QTimer(this);
        timer->setSingleShot(true);
        connect(timer, &QTimer::timeout, this, [this, folderId]() {
            emit changesDetected(folderId);
        });
        m_debounceTimers.insert(folderId, timer);
    }
    timer->start(m_debounceIntervalMs);
}

} // namespace core::sync