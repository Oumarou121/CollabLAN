#ifndef DATABASE_SHAREDFOLDERREPOSITORY_H
#define DATABASE_SHAREDFOLDERREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <optional>
#include <vector>

#include "models/SharedFolder.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees de la table `SharedFolders` (CRUD complet).
 *
 * Couche fine au-dessus de QSqlDatabase, sans logique metier : la
 * gestion des dossiers partages (validation, activation...) vit dans
 * core::SharedFolderManager.
 */
class SharedFolderRepository {
public:
    explicit SharedFolderRepository(QSqlDatabase database);
    ~SharedFolderRepository();

    int create(const models::SharedFolder &folder);
    std::optional<models::SharedFolder> findById(int id) const;
    bool update(const models::SharedFolder &folder);
    bool remove(int id);

    std::vector<models::SharedFolder> findAll() const;
    std::vector<models::SharedFolder> findActive() const;
    bool existsByLocalPath(const QString &localPath) const;

    QString lastError() const;

private:
    models::SharedFolder folderFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SHAREDFOLDERREPOSITORY_H
