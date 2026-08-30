#ifndef DATABASE_SYNCOPERATIONREPOSITORY_H
#define DATABASE_SYNCOPERATIONREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <QVector>
#include <optional>

#include "models/FileSyncOperation.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees de la table SyncOperations (journal de
 * synchronisation, migration #018).
 *
 * Utilisee par core::sync::SyncEngine pour enregistrer chaque changement
 * (Create/Update/Delete/Rename) rapporte par
 * core::SharedFolderManager::shareFolder() lors d'une (re)indexation.
 * Aucune logique reseau ici -- c'est un simple journal local (Release 3
 * de la doc de conception), consomme plus tard par un mecanisme de
 * reprise apres deconnexion (Release 7).
 */
class SyncOperationRepository {
public:
    explicit SyncOperationRepository(QSqlDatabase database);
    ~SyncOperationRepository();

    std::optional<models::FileSyncOperation> insert(const models::FileSyncOperation &operation);

    /// Operations d'un dossier partage (jointure sur SharedFiles.folder_id
    /// via file_id), les plus recentes d'abord. relativePath() de chaque
    /// SyncOperation retournee est renseigne pour l'affichage.
    QVector<models::FileSyncOperation> getByFolderId(qint64 folderId, int limit = 100) const;

    /// Etat courant (snapshot) d'un dossier partage, une seule ligne par
    /// fichier -- sa DERNIERE operation connue (Create/Update/Delete/
    /// Rename), les plus recentes d'abord. Utilisee pour le rattrapage
    /// hors-ligne (FolderSyncService::handleFolderHello(), Release 7) a la
    /// place de getByFolderId() : contrairement a un rejeu chronologique
    /// complet, le volume renvoye est ici borne par le nombre de fichiers
    /// DISTINCTS jamais connus dans le dossier (actuels + tombstones),
    /// jamais par le nombre d'evenements survenus au fil du temps -- un
    /// fichier reedite des centaines de fois ne compte que pour UNE seule
    /// ligne (son etat final), au lieu de saturer une fenetre de taille
    /// fixe et de faire perdre les operations plus anciennes d'AUTRES
    /// fichiers du meme dossier. relativePath() de chaque SyncOperation
    /// retournee est renseigne pour l'affichage, comme getByFolderId().
    QVector<models::FileSyncOperation> getLatestPerFileByFolderId(qint64 folderId, int limit = 2000) const;

    /// Operations dont id() > sinceId, triees par id croissant -- utilise
    /// par un futur mecanisme de reprise apres deconnexion (Release 7)
    /// pour rattraper un poste qui indique sa derniere operation connue.
    QVector<models::FileSyncOperation> getSinceId(qint64 sinceId, int limit = 500) const;

    /// Plus grand id connu (0 si aucune operation) : sert de "curseur"
    /// pour un poste qui revient en ligne.
    qint64 latestId() const;

    QString lastError() const;

private:
    models::FileSyncOperation operationFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SYNCOPERATIONREPOSITORY_H