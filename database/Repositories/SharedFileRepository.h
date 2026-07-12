#ifndef DATABASE_SHAREDFILEREPOSITORY_H
#define DATABASE_SHAREDFILEREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <optional>
#include <vector>

#include "models/SharedFile.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees de la table `SharedFiles` (CRUD complet).
 */
class SharedFileRepository {
public:
    explicit SharedFileRepository(QSqlDatabase database);
    ~SharedFileRepository();

    int create(const models::SharedFile &file);
    std::optional<models::SharedFile> findById(int id) const;
    bool update(const models::SharedFile &file);
    bool remove(int id);

    std::optional<models::SharedFile> findByFolderAndPath(int folderId, const QString &relativePath) const;
    std::vector<models::SharedFile> findByFolder(int folderId, bool includeDeleted = false) const;
    int countActiveByFolder(int folderId) const;

    QString lastError() const;

private:
    models::SharedFile fileFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SHAREDFILEREPOSITORY_H
