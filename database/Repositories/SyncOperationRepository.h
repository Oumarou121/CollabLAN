#ifndef DATABASE_SYNCOPERATIONREPOSITORY_H
#define DATABASE_SYNCOPERATIONREPOSITORY_H

#include <QDateTime>
#include <QSqlDatabase>
#include <vector>

#include "models/SyncOperation.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees de la table `SyncOperations` (historique).
 *
 * Table en ajout seul (pas d'update/delete) : chaque changement applique
 * a un SharedFile cree une nouvelle ligne, ce qui permet de reconstituer
 * la chronologie complete d'un dossier partage.
 */
class SyncOperationRepository {
public:
    explicit SyncOperationRepository(QSqlDatabase database);
    ~SyncOperationRepository();

    int create(const models::SyncOperation &operation);

    std::vector<models::SyncOperation> findByFile(int fileId) const;

    // Utilise au retour en ligne d'un poste : recupere toutes les
    // operations plus recentes que `since`, quel que soit le poste
    // d'origine (permet de rattraper les operations manquees).
    std::vector<models::SyncOperation> findSince(const QDateTime &since) const;

    std::vector<models::SyncOperation> findRecentByFolder(int folderId, int limit = 50) const;

    QString lastError() const;

private:
    models::SyncOperation operationFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SYNCOPERATIONREPOSITORY_H
