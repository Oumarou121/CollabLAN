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
    refresh();
}

void SharedFolderContext::setUserManager(UserManager *manager)
{
    m_userManager = manager;
}

void SharedFolderContext::refresh()
{
    if (!m_manager) {
        return;
    }

    const QVector<models::SharedFolder> folders = m_manager->getFolders();
    m_folderModel->setFolders(folders);

    QHash<qint64, int> counts;
    for (const models::SharedFolder &folder : folders) {
        counts.insert(folder.id(), m_manager->getFiles(folder.id()).size());
    }
    m_folderModel->setFileCounts(counts);
}

bool SharedFolderContext::createFolder(const QString &name, const QString &localPath)
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

    const auto folder = m_manager->createFolder(name, localPath, ownerId);
    if (!folder.has_value()) {
        m_lastErrorString = m_manager->lastErrorString();
        emit errorOccurred(m_lastErrorString);
        return false;
    }

    // Indexation locale immediate : l'utilisateur s'attend a voir le
    // nombre de fichiers des la creation, pas seulement au premier clic
    // manuel sur "actualiser" (voir commentaire Q_INVOKABLE createFolder()).
    m_manager->shareFolder(folder->id());
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

    const int count = m_manager->shareFolder(folderId);
    if (count < 0) {
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

} // namespace core
