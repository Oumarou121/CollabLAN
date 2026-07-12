#ifndef DATABASE_SHAREDFILEREPOSITORY_H
#define DATABASE_SHAREDFILEREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <QVector>
#include <optional>

#include "models/SharedFile.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees de la table SharedFiles.
 *
 * Couche fine au-dessus de QSqlDatabase : core::SharedFolderManager s'en
 * sert pour indexer localement le contenu d'un dossier partage
 * (SharedFolderManager::shareFolder()). Aucune logique reseau ici -- la
 * synchronisation entre postes est laissee a un futur SyncEngine.
 */
class SharedFileRepository {
public:
    explicit SharedFileRepository(QSqlDatabase database);
    ~SharedFileRepository();

    /// Insere ou met a jour (upsert par folder_id + relative_path) une
    /// entree. Incremente version si le fichier existait deja et que le
    /// hash a change.
    std::optional<models::SharedFile> upsert(const models::SharedFile &file);

    bool remove(qint64 fileId);

    /// Marque un fichier comme supprime (tombstone) plutot que de le
    /// retirer physiquement, afin qu'une future synchronisation reseau
    /// puisse propager la suppression aux autres postes.
    bool markDeleted(qint64 folderId, const QString &relativePath);

    /// Renomme/deplace un fichier en base (Rename recu d'un pair distant).
    /// Met a jour relative_path de oldPath vers newPath dans le meme dossier.
    /// Retourne false si la ligne oldPath n'existe pas.
    bool renameFile(qint64 folderId, const QString &oldPath, const QString &newPath);

    std::optional<models::SharedFile> getById(qint64 fileId) const;
    std::optional<models::SharedFile> findByRelativePath(qint64 folderId, const QString &relativePath) const;

    /// Fichiers non supprimes d'un dossier, tries par chemin relatif.
    QVector<models::SharedFile> getByFolderId(qint64 folderId) const;

    /// Nombre de fichiers non supprimes d'un dossier (pour l'UI, cf.
    /// models::SharedFolderModel::FileCountRole).
    int count(qint64 folderId) const;

    QString lastError() const;

private:
    models::SharedFile fileFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SHAREDFILEREPOSITORY_H
