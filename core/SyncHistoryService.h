#ifndef CORE_SYNCHISTORYSERVICE_H
#define CORE_SYNCHISTORYSERVICE_H

#include <QObject>
#include <QVariantList>

#include "database/Repositories/SharedFileRepository.h"
#include "database/Repositories/SyncOperationRepository.h"

namespace database {
class DatabaseManager;
}

namespace core {

/**
 * @brief Historique de synchronisation d'un dossier partage, en lecture
 * seule (Phase 10 de "Shared Folder") : qui a modifie quoi et quand.
 *
 * Simple vue de lecture au-dessus de SyncOperationRepository, exposee a
 * la QML pour l'onglet "Historique" de l'ecran de dossier partage.
 */
class SyncHistoryService : public QObject {
    Q_OBJECT

public:
    explicit SyncHistoryService(database::DatabaseManager *databaseManager, QObject *parent = nullptr);
    ~SyncHistoryService() override;

    // Renvoie les operations les plus recentes pour un dossier, sous
    // forme de liste de QVariantMap{action, path, machineId, date}
    // directement consommable depuis QML (ListModel/Repeater).
    Q_INVOKABLE QVariantList recentOperations(int folderId, int limit = 50) const;

private:
    database::SharedFileRepository m_fileRepository;
    database::SyncOperationRepository m_operationRepository;
};

} // namespace core

#endif // CORE_SYNCHISTORYSERVICE_H
