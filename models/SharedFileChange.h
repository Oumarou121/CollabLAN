#ifndef MODELS_SHAREDFILECHANGE_H
#define MODELS_SHAREDFILECHANGE_H

#include <QString>
#include <utility>

#include "SharedFile.h"
#include "SyncChangeType.h"

namespace models {

/**
 * @brief Changement detecte lors d'une (re)indexation d'un SharedFolder
 * (core::SharedFolderManager::shareFolder()).
 *
 * Purement ephemere/local : ce n'est qu'une fois transforme en
 * models::SyncOperation par core::sync::SyncEngine qu'un changement est
 * effectivement persiste (table SyncOperations). SharedFolderManager n'a
 * donc aucune dependance vers SyncOperationRepository -- il se contente
 * de rapporter CE QUI a change lors de l'indexation, conformement au
 * decoupage de responsabilites de la doc de conception (SharedFolderManager
 * = metier/indexation, SyncEngine = orchestration/journal).
 */
class SharedFileChange {
public:
    SharedFileChange() = default;

    SharedFileChange(SyncChangeType type, models::SharedFile file, QString oldRelativePath = QString())
        : m_type(type)
        , m_file(std::move(file))
        , m_oldRelativePath(std::move(oldRelativePath))
    {
    }

    SyncChangeType type() const { return m_type; }
    const models::SharedFile &file() const { return m_file; }

    /// Uniquement renseigne pour type() == Rename.
    QString oldRelativePath() const { return m_oldRelativePath; }

    /// Empreinte du fichier avant ce changement (vide pour une creation).
    QString previousHash() const { return m_previousHash; }
    void setPreviousHash(const QString &hash) { m_previousHash = hash; }

private:
    SyncChangeType m_type = SyncChangeType::Update;
    models::SharedFile m_file;
    QString m_oldRelativePath;
    QString m_previousHash;
};

} // namespace models

#endif // MODELS_SHAREDFILECHANGE_H
