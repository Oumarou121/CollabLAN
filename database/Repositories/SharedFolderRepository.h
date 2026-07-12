#ifndef DATABASE_SHAREDFOLDERREPOSITORY_H
#define DATABASE_SHAREDFOLDERREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <QVector>
#include <optional>

#include "models/SharedFolder.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees de la table SharedFolders.
 *
 * Couche fine au-dessus de QSqlDatabase (requetes preparees, aucune
 * logique reseau ni de systeme de fichiers) : core::SharedFolderManager
 * s'en sert pour creer/lister/supprimer des dossiers partages.
 */
class SharedFolderRepository {
public:
    explicit SharedFolderRepository(QSqlDatabase database);
    ~SharedFolderRepository();

    /// Insere un nouveau dossier partage. Genere un uuid si folder.uuid()
    /// est vide (cas normal : appele depuis SharedFolderManager::createFolder()).
    std::optional<models::SharedFolder> insert(const models::SharedFolder &folder);

    bool update(const models::SharedFolder &folder);

    /// Supprime un dossier partage. Les SharedFiles associes sont
    /// supprimes en cascade (ON DELETE CASCADE, migration #018).
    bool remove(qint64 folderId);

    std::optional<models::SharedFolder> getById(qint64 folderId) const;
    std::optional<models::SharedFolder> findByUuid(const QString &uuid) const;

    /// Tous les dossiers partages actifs, du plus recent au plus ancien.
    QVector<models::SharedFolder> getAll() const;

    /// Dossiers partages appartenant a un utilisateur donne.
    QVector<models::SharedFolder> getByOwnerId(qint64 ownerId) const;

    QString lastError() const;

private:
    models::SharedFolder folderFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SHAREDFOLDERREPOSITORY_H
