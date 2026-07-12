#include "SyncHistoryService.h"

#include <QVariantMap>

#include "database/DatabaseManager.h"
#include "models/SyncOperation.h"

namespace core {

SyncHistoryService::SyncHistoryService(database::DatabaseManager *databaseManager, QObject *parent)
    : QObject(parent)
    , m_fileRepository(databaseManager ? databaseManager->database() : QSqlDatabase())
    , m_operationRepository(databaseManager ? databaseManager->database() : QSqlDatabase())
{
}

SyncHistoryService::~SyncHistoryService() = default;

QVariantList SyncHistoryService::recentOperations(int folderId, int limit) const
{
    QVariantList result;
    const auto operations = m_operationRepository.findRecentByFolder(folderId, limit);

    for (const models::SyncOperation &operation : operations) {
        QString path;
        if (auto file = m_fileRepository.findById(operation.fileId())) {
            path = file->relativePath();
        }

        QVariantMap entry;
        entry.insert(QStringLiteral("action"), models::syncOperationTypeToString(operation.type()));
        entry.insert(QStringLiteral("path"), path);
        entry.insert(QStringLiteral("machineId"), operation.machineId());
        entry.insert(QStringLiteral("version"), operation.version());
        entry.insert(QStringLiteral("date"), operation.date());
        result.append(entry);
    }

    return result;
}

} // namespace core
