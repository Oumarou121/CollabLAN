#include "SharedFolderManager.h"

#include "DatabaseManager.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QSet>

namespace core {

SharedFolderManager::SharedFolderManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
    , m_folderRepository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_fileRepository(dbManager ? dbManager->database() : QSqlDatabase())
{
}

SharedFolderManager::~SharedFolderManager()
{
}

std::optional<models::SharedFolder> SharedFolderManager::createFolder(const QString &name, const QString &localPath, qint64 ownerId)
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

int SharedFolderManager::shareFolder(qint64 folderId)
{
    if (!m_dbManager) {
        m_lastError = SharedFolderManagerError::DatabaseError;
        m_lastErrorString = QStringLiteral("DatabaseManager not set");
        return -1;
    }

    const auto folder = m_folderRepository.getById(folderId);
    if (!folder.has_value()) {
        m_lastError = SharedFolderManagerError::InvalidFolder;
        m_lastErrorString = QStringLiteral("Dossier partage introuvable (id=%1)").arg(folderId);
        return -1;
    }

    const QDir rootDir(folder->localPath());
    if (!rootDir.exists()) {
        m_lastError = SharedFolderManagerError::InvalidPath;
        m_lastErrorString = QStringLiteral("Le chemin local '%1' n'existe plus").arg(folder->localPath());
        return -1;
    }

    // Parcours recursif : chaque fichier trouve est indexe (upsert) avec
    // son chemin RELATIF a la racine du dossier partage (cf. commentaire
    // migration #018 -- independant du chemin absolu, qui peut differer
    // d'un poste a l'autre pour le "meme" dossier logique).
    QSet<QString> seenRelativePaths;
    QDirIterator it(folder->localPath(), QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString absolutePath = it.next();
        const QString relativePath = rootDir.relativeFilePath(absolutePath);
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
        models::SharedFile sharedFile;
        sharedFile.setFolderId(folderId);
        sharedFile.setRelativePath(relativePath);
        sharedFile.setHash(QString::fromLatin1(hasher.result().toHex()));
        sharedFile.setSize(info.size());
        sharedFile.setLastModified(info.lastModified());

        m_fileRepository.upsert(sharedFile);
    }

    // Fichiers connus en base mais absents du disque : suppression logique
    // (tombstone), afin qu'une future synchronisation reseau puisse la
    // propager plutot que de perdre l'information silencieusement.
    for (const models::SharedFile &known : m_fileRepository.getByFolderId(folderId)) {
        if (!seenRelativePaths.contains(known.relativePath())) {
            m_fileRepository.markDeleted(folderId, known.relativePath());
        }
    }

    const int fileCount = m_fileRepository.count(folderId);
    emit folderShared(folderId, fileCount);
    return fileCount;
}

QVector<models::SharedFile> SharedFolderManager::getFiles(qint64 folderId) const
{
    if (!m_dbManager) {
        return {};
    }
    return m_fileRepository.getByFolderId(folderId);
}

} // namespace core
