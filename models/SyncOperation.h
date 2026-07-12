#ifndef MODELS_SYNCOPERATION_H
#define MODELS_SYNCOPERATION_H

#include <QDateTime>
#include <QString>

namespace models {

/**
 * @brief Type d'operation applique a un SharedFile.
 */
enum class SyncOperationType {
    Create,
    Update,
    Delete,
    Rename
};

QString syncOperationTypeToString(SyncOperationType type);
SyncOperationType syncOperationTypeFromString(const QString &value);

/**
 * @brief Historique des operations de synchronisation (table `SyncOperations`).
 *
 * Chaque changement applique a un SharedFile (localement ou recu du
 * reseau) cree une ligne. Cette table permet a un poste qui revient en
 * ligne apres une coupure de rattraper toutes les operations manquees
 * (cf. Phase 6 : synchronisation initiale) et alimente
 * core::SyncHistoryService pour l'affichage/le debogage (Phase 10).
 */
class SyncOperation {
public:
    SyncOperation();
    SyncOperation(int id,
                 SyncOperationType type,
                 int fileId,
                 int version,
                 QString machineId,
                 QDateTime date = QDateTime::currentDateTimeUtc());

    int id() const;
    void setId(int id);

    SyncOperationType type() const;
    void setType(SyncOperationType type);

    int fileId() const;
    void setFileId(int fileId);

    int version() const;
    void setVersion(int version);

    // Identifiant du poste (DiscoveryService::localId) a l'origine de
    // l'operation, pour distinguer les changements locaux des changements
    // recus d'un autre poste.
    QString machineId() const;
    void setMachineId(const QString &machineId);

    QDateTime date() const;
    void setDate(const QDateTime &date);

    bool isValid() const;

private:
    int m_id = -1;
    SyncOperationType m_type = SyncOperationType::Create;
    int m_fileId = -1;
    int m_version = 1;
    QString m_machineId;
    QDateTime m_date;
};

} // namespace models

#endif // MODELS_SYNCOPERATION_H
