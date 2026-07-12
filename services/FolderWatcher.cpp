#include "FolderWatcher.h"

#include <QDir>
#include <QFileInfo>

namespace services {

FolderWatcher::FolderWatcher(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
{
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &FolderWatcher::onDirectoryChanged);
}

FolderWatcher::~FolderWatcher() = default;

bool FolderWatcher::watch(const QString &rootPath)
{
    const QFileInfo info(rootPath);
    if (!info.exists() || !info.isDir()) {
        return false;
    }

    unwatch();
    m_rootPath = QDir(rootPath).absolutePath();

    // Scan initial silencieux : on construit l'etat connu sans emettre
    // fileCreated pour les fichiers deja presents avant la surveillance.
    watchDirectoryRecursive(m_rootPath, /*emitSignals=*/false);
    return true;
}

void FolderWatcher::unwatch()
{
    if (!m_watcher->directories().isEmpty()) {
        m_watcher->removePaths(m_watcher->directories());
    }
    m_knownFiles.clear();
    m_rootPath.clear();
}

QString FolderWatcher::rootPath() const
{
    return m_rootPath;
}

bool FolderWatcher::isWatching() const
{
    return !m_rootPath.isEmpty();
}

QString FolderWatcher::toRelativePath(const QString &absolutePath) const
{
    QDir rootDir(m_rootPath);
    return rootDir.relativeFilePath(absolutePath);
}

void FolderWatcher::watchDirectoryRecursive(const QString &absoluteDirPath, bool emitSignals)
{
    m_watcher->addPath(absoluteDirPath);
    scanDirectory(absoluteDirPath, emitSignals);

    QDir dir(absoluteDirPath);
    const QFileInfoList subDirs = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QFileInfo &subDir : subDirs) {
        watchDirectoryRecursive(subDir.absoluteFilePath(), emitSignals);
    }
}

void FolderWatcher::scanDirectory(const QString &absoluteDirPath, bool emitSignals)
{
    QDir dir(absoluteDirPath);
    const QFileInfoList entries = dir.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot);

    for (const QFileInfo &entry : entries) {
        if (entry.isDir()) {
            // Nouveau sous-dossier : le surveiller a son tour. S'il
            // contient deja des fichiers (ex. deplacement d'un dossier
            // entier), scanDirectory() les remontera comme des creations.
            if (!m_watcher->directories().contains(entry.absoluteFilePath())) {
                if (emitSignals) {
                    emit directoryCreated(toRelativePath(entry.absoluteFilePath()));
                }
                watchDirectoryRecursive(entry.absoluteFilePath(), emitSignals);
            }
            continue;
        }

        const QString relativePath = toRelativePath(entry.absoluteFilePath());
        const FileState newState{ entry.size(), entry.lastModified() };
        const auto it = m_knownFiles.find(relativePath);

        if (it == m_knownFiles.end()) {
            m_knownFiles.insert(relativePath, newState);
            if (emitSignals) {
                emit fileCreated(relativePath);
            }
        } else if (it->size != newState.size || it->lastModified != newState.lastModified) {
            *it = newState;
            if (emitSignals) {
                emit fileChanged(relativePath);
            }
        }
    }

    // Detecte les suppressions : tout fichier connu, situe dans ce
    // dossier, absent de la liste actuelle.
    QDir rootDir(m_rootPath);
    const QString relativeDirPath = rootDir.relativeFilePath(absoluteDirPath);
    const QStringList knownPaths = m_knownFiles.keys();
    for (const QString &knownRelativePath : knownPaths) {
        const QString knownDir = QFileInfo(knownRelativePath).path();
        const bool sameDir = (relativeDirPath == QStringLiteral(".") && knownDir == QStringLiteral("."))
                              || knownDir == relativeDirPath;
        if (!sameDir) {
            continue;
        }
        const QString absoluteKnownPath = QDir(m_rootPath).filePath(knownRelativePath);
        if (!QFileInfo::exists(absoluteKnownPath)) {
            m_knownFiles.remove(knownRelativePath);
            if (emitSignals) {
                emit fileDeleted(knownRelativePath);
            }
        }
    }
}

void FolderWatcher::onDirectoryChanged(const QString &path)
{
    if (!QFileInfo::exists(path)) {
        // Le dossier surveille lui-meme a ete supprime/deplace.
        m_watcher->removePath(path);
        return;
    }
    scanDirectory(path, /*emitSignals=*/true);
}

} // namespace services
