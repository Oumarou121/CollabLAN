#ifndef CORE_SHAREDFOLDERMANAGER_H
#define CORE_SHAREDFOLDERMANAGER_H

#include <QObject>
#include <QString>
#include <QVector>
#include <optional>

#include "database/Repositories/SharedFolderRepository.h"
#include "database/Repositories/SharedFileRepository.h"
#include "models/SharedFolder.h"
#include "models/SharedFile.h"
#include "models/SharedFileChange.h"

namespace database {
class DatabaseManager;
}

namespace core {

enum class SharedFolderManagerError {
    None,
    InvalidName,
    InvalidPath,
    PathNotDirectory,
    InvalidFolder,
    DatabaseError
};

/**
 * @brief Gestionnaire des dossiers partages (module "Shared Folder").
 *
 * Responsabilites, volontairement limitees au "metier" (cf. doc de
 * conception, section reorganisation) : creer/supprimer/lister des
 * dossiers partages et les indexer localement. Aucune logique reseau ni
 * de journal de synchronisation ici -- la surveillance du systeme de
 * fichiers (core::sync::FolderWatcher) et l'orchestration (creation de
 * SyncOperation, future synchronisation reseau) sont la responsabilite de
 * core::sync::SyncEngine, qui appelle shareFolder() et transforme son
 * resultat (QVector<models::SharedFileChange>) en journal persiste.
 *
 * shareFolder() effectue une indexation locale du contenu du dossier
 * (parcours recursif + hash SHA-256 de chaque fichier) et RAPPORTE ce qui
 * a change (nouveau fichier, modification, suppression, renommage) sans
 * jamais ecrire dans SyncOperations lui-meme : cette etape reste purement
 * locale (aucun octet n'est envoye sur le reseau).
 */
class SharedFolderManager : public QObject
{
    Q_OBJECT

public:
    explicit SharedFolderManager(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~SharedFolderManager() override;

    /// Cree un nouveau dossier partage a partir d'un chemin local existant.
    /// Echoue si le chemin n'existe pas ou n'est pas un dossier.
    std::optional<models::SharedFolder> createFolder(const QString &name, const QString &localPath, qint64 ownerId);

    /// Supprime un dossier partage (et son historique de fichiers, cascade
    /// SQL). Ne touche jamais aux fichiers reels sur le disque.
    bool removeFolder(qint64 folderId);

    /// Recupere tous les dossiers partages connus localement.
    QVector<models::SharedFolder> getFolders() const;

    /// Recupere les dossiers partages appartenant a un utilisateur donne.
    QVector<models::SharedFolder> getFolders(qint64 ownerId) const;

    std::optional<models::SharedFolder> getFolder(qint64 folderId) const;

    /// Parcourt recursivement localPath() et indexe (upsert) chaque
    /// fichier trouve dans SharedFiles (hash SHA-256, taille, date de
    /// derniere modification). Les entrees precedemment indexees dont le
    /// fichier n'existe plus sur le disque sont marquees supprimees
    /// (tombstone), sauf si un fichier de meme hash est apparu ailleurs
    /// sous un autre chemin relatif : ce cas est alors rapporte comme un
    /// Rename plutot qu'un Delete+Create.
    ///
    /// Retourne la liste des changements detectes (vide si le dossier
    /// n'a pas change depuis la derniere indexation), ou std::nullopt en
    /// cas d'erreur (dossier introuvable/inaccessible, voir lastError()).
    std::optional<QVector<models::SharedFileChange>> shareFolder(qint64 folderId);

    /// Fichiers actuellement connus (non supprimes) d'un dossier partage.
    QVector<models::SharedFile> getFiles(qint64 folderId) const;

    SharedFolderManagerError lastError() const { return m_lastError; }
    QString lastErrorString() const { return m_lastErrorString; }

signals:
    void folderCreated(const models::SharedFolder &folder);
    void folderRemoved(qint64 folderId);
    /// fileCount = nombre de fichiers non supprimes APRES l'indexation
    /// (utilise par l'UI, cf. models::SharedFolderModel::FileCountRole).
    /// Emis meme si changes() (shareFolder()) est vide.
    void folderShared(qint64 folderId, int fileCount);

private:
    database::DatabaseManager *m_dbManager = nullptr;
    database::SharedFolderRepository m_folderRepository;
    database::SharedFileRepository m_fileRepository;
    SharedFolderManagerError m_lastError = SharedFolderManagerError::None;
    QString m_lastErrorString;
};

} // namespace core

#endif // CORE_SHAREDFOLDERMANAGER_H
