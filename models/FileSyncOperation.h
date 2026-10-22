#ifndef MODELS_FILESYNCOPERATION_H
#define MODELS_FILESYNCOPERATION_H

#include <QDateTime>
#include <QString>

#include "SyncChangeType.h"

namespace models {

/**
 * @brief Une ligne de la table SyncOperations : journal de synchronisation
 * (doc de conception, Release 3) alimente par core::sync::SyncEngine a
 * chaque changement detecte sur un fichier partage.
 *
 * Sert de base a un futur mecanisme de reprise apres deconnexion
 * (Release 7) : un poste qui revient en ligne pourra indiquer son
 * dernier id connu et ne recevoir/rejouer que les operations posterieures,
 * plutot que de rescanner integralement chaque dossier partage.
 */
class FileSyncOperation {
public:
    FileSyncOperation();

    qint64 id() const { return m_id; }
    void setId(qint64 id) { m_id = id; }

    SyncChangeType type() const { return m_type; }
    void setType(SyncChangeType type) { m_type = type; }

    /// Reference vers SharedFiles.id -- pour Delete/Rename, c'est la ligne
    /// (tombstonee ou renommee) telle qu'elle existe APRES l'operation.
    qint64 fileId() const { return m_fileId; }
    void setFileId(qint64 fileId) { m_fileId = fileId; }

    /// Ancien chemin relatif (uniquement pour type() == Rename, vide sinon).
    QString oldRelativePath() const { return m_oldRelativePath; }
    void setOldRelativePath(const QString &path) { m_oldRelativePath = path; }

    int version() const { return m_version; }
    void setVersion(int version) { m_version = version; }

    /// Identifiant du poste (network::DiscoveryService::localId()) qui a
    /// produit cette operation.
    QString machineId() const { return m_machineId; }
    void setMachineId(const QString &machineId) { m_machineId = machineId; }

    QDateTime createdAt() const { return m_createdAt; }
    void setCreatedAt(const QDateTime &createdAt) { m_createdAt = createdAt; }

    /// Chemin relatif courant du fichier concerne -- champ d'affichage
    /// denormalise (jointure SharedFiles), jamais persiste tel quel dans
    /// SyncOperations. Uniquement renseigne par
    /// database::SyncOperationRepository::getByFolderId().
    QString relativePath() const { return m_relativePath; }
    void setRelativePath(const QString &relativePath) { m_relativePath = relativePath; }

    /// Version dont part la modification (empreinte precedente chez l'auteur).
    QString baseHash() const { return m_baseHash; }
    void setBaseHash(const QString &hash) { m_baseHash = hash; }
    /// Auteur reel (uuid du compte), vide si inconnu.
    QString authorUuid() const { return m_authorUuid; }
    void setAuthorUuid(const QString &uuid) { m_authorUuid = uuid; }

private:
    qint64 m_id = 0;
    SyncChangeType m_type = SyncChangeType::Update;
    qint64 m_fileId = 0;
    QString m_oldRelativePath;
    int m_version = 1;
    QString m_machineId;
    QDateTime m_createdAt;
    QString m_relativePath;
    QString m_baseHash;
    QString m_authorUuid;
};

} // namespace models

#endif // MODELS_FILESYNCOPERATION_H
