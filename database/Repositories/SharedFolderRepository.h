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

    /// Corrige l'origin_machine_id d'un dossier DEJA connu localement.
    /// Necessaire quand un folder_access_granted reseau (FolderSyncService::
    /// handleFolderAccessGranted()) revele que ce dossier appartient en
    /// realite a un autre poste, alors que la ligne locale le marquait
    /// origin_machine_id = '' (isLocalOrigin() == true) -- insert() ne fixe
    /// cette colonne qu'a la creation et rien ne la corrigeait ensuite,
    /// laissant le dossier bloque en "origine locale" indefiniment (aucun
    /// resync jamais demande). Chaine vide = redevient origine locale.
    bool updateOriginMachineId(qint64 folderId, const QString &originMachineId);

    /// Supprime un dossier partage. Les SharedFiles associes sont
    /// supprimes en cascade (ON DELETE CASCADE, migration #018).
    bool remove(qint64 folderId);

    std::optional<models::SharedFolder> getById(qint64 folderId) const;
    std::optional<models::SharedFolder> findByUuid(const QString &uuid) const;

    /// Tous les dossiers partages actifs, du plus recent au plus ancien.
    QVector<models::SharedFolder> getAll() const;

    /// Dossiers partages appartenant a un utilisateur donne.
    QVector<models::SharedFolder> getByOwnerId(qint64 ownerId) const;

    /// Dossiers partages pour lesquels folderIds contient l'id (utilise
    /// par SharedFolderManager::getAccessibleFolders() pour recuperer en
    /// une fois les dossiers accordes explicitement via SharedFolderAccess).
    QVector<models::SharedFolder> getByIds(const QVector<qint64> &folderIds) const;

    QString lastError() const;

private:
    models::SharedFolder folderFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SHAREDFOLDERREPOSITORY_H
