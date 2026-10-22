#ifndef MODELS_SHAREDFILE_H
#define MODELS_SHAREDFILE_H

#include <QString>
#include <QDateTime>

namespace models {

/**
 * @brief Represente un fichier connu d'un SharedFolder.
 *
 * relativePath est le chemin relatif a la racine du dossier partage (ex:
 * "Docs/cahier.pdf"), independant du chemin absolu local -- voir
 * SharedFolder::localPath(). deleted() est une suppression logique
 * (tombstone), necessaire pour qu'une future synchronisation reseau
 * puisse propager une suppression aux autres postes plutot que de la
 * faire disparaitre silencieusement de l'historique local.
 */
class SharedFile {
public:
    SharedFile();
    SharedFile(qint64 id, qint64 folderId, QString relativePath);

    qint64 id() const { return m_id; }
    void setId(qint64 id) { m_id = id; }

    qint64 folderId() const { return m_folderId; }
    void setFolderId(qint64 folderId) { m_folderId = folderId; }

    QString relativePath() const { return m_relativePath; }
    void setRelativePath(const QString &relativePath) { m_relativePath = relativePath; }

    /// Empreinte de contenu (SHA-256), chaine vide si non calculee.
    QString hash() const { return m_hash; }
    void setHash(const QString &hash) { m_hash = hash; }

    qint64 size() const { return m_size; }
    void setSize(qint64 size) { m_size = size; }

    QDateTime lastModified() const { return m_lastModified; }
    void setLastModified(const QDateTime &lastModified) { m_lastModified = lastModified; }

    int version() const { return m_version; }
    void setVersion(int version) { m_version = version; }

    bool deleted() const { return m_deleted; }
    void setDeleted(bool deleted) { m_deleted = deleted; }

    /// true tant que ce SharedFile n'est qu'un placeholder de rattrapage
    /// (FolderSyncService::registerCatchupPlaceholder(), taille 0, contenu
    /// reel pas encore telecharge). Remis a false par
    /// integrateReceivedFile() une fois le vrai fichier recu.
    /// SharedFolderManager::shareFolder() ne doit jamais tombstoner
    /// (Delete) une ligne encore a l'etat pending_download=true : son
    /// absence du disque local ne signifie pas qu'elle a ete supprimee,
    /// juste qu'elle n'a pas encore ete telechargee.
    bool pendingDownload() const { return m_pendingDownload; }
    void setPendingDownload(bool pendingDownload) { m_pendingDownload = pendingDownload; }

    /// Derniere version echangee avec le reseau (migration 037) ; vide si inconnue.
    QString syncedHash() const { return m_syncedHash; }
    void setSyncedHash(const QString &hash) { m_syncedHash = hash; }

private:
    qint64 m_id = 0;
    qint64 m_folderId = 0;
    QString m_relativePath;
    QString m_hash;
    qint64 m_size = 0;
    QDateTime m_lastModified;
    int m_version = 1;
    bool m_deleted = false;
    bool m_pendingDownload = false;
    QString m_syncedHash;
};

} // namespace models

#endif // MODELS_SHAREDFILE_H
