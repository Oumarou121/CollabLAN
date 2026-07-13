#ifndef DATABASE_SHAREDFOLDERACCESSREPOSITORY_H
#define DATABASE_SHAREDFOLDERACCESSREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <QVector>
#include <optional>

#include "models/SharedFolderAccess.h"
#include "models/SharedFolderPermission.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees de la table SharedFolderAccess (migration 020).
 *
 * Couche fine au-dessus de QSqlDatabase, sur le meme principe que
 * SharedFolderRepository/SharedFileRepository : aucune logique metier
 * (verification des droits, qui peut accorder/revoquer...) ici, laissee
 * a core::SharedFolderManager.
 */
class SharedFolderAccessRepository {
public:
    explicit SharedFolderAccessRepository(QSqlDatabase database);
    ~SharedFolderAccessRepository();

    /// Accorde (ou met a jour si deja existante) une permission a
    /// userId sur folderId. grantedBy = 0 si inconnu/non applicable.
    std::optional<models::SharedFolderAccess> grant(qint64 folderId, qint64 userId,
                                                      models::SharedFolderPermission permission,
                                                      qint64 grantedBy);

    /// Revoque l'acces explicite de userId a folderId (no-op si aucune
    /// ligne n'existait deja : retourne true dans les deux cas).
    bool revoke(qint64 folderId, qint64 userId);

    /// Permission explicite accordee, ou SharedFolderPermission::None si
    /// aucune ligne n'existe pour (folderId, userId) -- ne prejuge pas du
    /// cas proprietaire/administrateur, verifie en amont par l'appelant
    /// (core::SharedFolderManager).
    models::SharedFolderPermission permissionFor(qint64 folderId, qint64 userId) const;

    /// Toutes les permissions explicites accordees sur un dossier.
    QVector<models::SharedFolderAccess> listForFolder(qint64 folderId) const;

    /// Tous les dossiers (par id) pour lesquels userId a une permission
    /// explicite -- n'inclut PAS les dossiers dont userId est proprietaire.
    QVector<models::SharedFolderAccess> listForUser(qint64 userId) const;

    /// Acces dont id() > sinceId, tries par id croissant -- utilise par
    /// core::sync::FolderSyncService pour le rattrapage hors-ligne des
    /// annonces de partage (folder_hello / folder_catchup_batch), sur le
    /// meme principe que SyncOperationRepository::getSinceId().
    QVector<models::SharedFolderAccess> getSinceId(qint64 sinceId, int limit = 500) const;

    /// Plus grand id connu (0 si aucun acces) : sert de "curseur" pour un
    /// poste qui revient en ligne (cf. getSinceId()).
    qint64 latestId() const;

    QString lastError() const;

private:
    models::SharedFolderAccess accessFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SHAREDFOLDERACCESSREPOSITORY_H
