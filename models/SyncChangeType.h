#ifndef MODELS_SYNCCHANGETYPE_H
#define MODELS_SYNCCHANGETYPE_H

#include <QString>

namespace models {

/**
 * @brief Nature d'un changement detecte sur un fichier partage (cf. doc
 * de conception, Release 2/3). Utilise a la fois par SharedFileChange
 * (changement ephemere detecte lors d'une (re)indexation) et par
 * SyncOperation (meme changement, une fois persiste dans le journal
 * SyncOperations par core::sync::SyncEngine).
 */
enum class SyncChangeType {
    Create,
    Update,
    Delete,
    Rename
};

inline QString syncChangeTypeToString(SyncChangeType type)
{
    switch (type) {
    case SyncChangeType::Create: return QStringLiteral("Create");
    case SyncChangeType::Update: return QStringLiteral("Update");
    case SyncChangeType::Delete: return QStringLiteral("Delete");
    case SyncChangeType::Rename: return QStringLiteral("Rename");
    }
    return QStringLiteral("Update");
}

inline SyncChangeType syncChangeTypeFromString(const QString &value)
{
    if (value == QStringLiteral("Create")) return SyncChangeType::Create;
    if (value == QStringLiteral("Delete")) return SyncChangeType::Delete;
    if (value == QStringLiteral("Rename")) return SyncChangeType::Rename;
    return SyncChangeType::Update;
}

} // namespace models

#endif // MODELS_SYNCCHANGETYPE_H
