#ifndef DATABASE_SYNCLOGREPOSITORY_H
#define DATABASE_SYNCLOGREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <vector>

#include "models/SyncLogEntry.h"
#include "models/User.h"

class QSqlQuery;

namespace database {

/**
 * @brief Acces aux donnees des tables SyncLog / PeerSyncState
 *        (HYBRID_SERVER_FAILOVER.md, sections 3 et 7).
 *
 * Utilise par le poste courant pour journaliser ses propres ecritures
 * quand il fait autorite (SERVER ou TEMP_SERVER), et par SyncService pour
 * construire/appliquer les sync_batch echanges a la reconciliation.
 */
class SyncLogRepository
{
public:
    explicit SyncLogRepository(QSqlDatabase database);
    ~SyncLogRepository();

    /**
     * @brief Journalise une ecriture locale. entryUuid genere aleatoirement si vide.
     */
    bool append(const models::SyncLogEntry &entry);

    /**
     * @brief Entrees dont l'epoch est superieur ou egal a fromEpoch (inclusif), triees
     *        par lamport_clock croissant puis id croissant. Utilise par le SERVER officiel
     *        pour construire son sync_request / interpreter un sync_batch recu.
     */
    std::vector<models::SyncLogEntry> entriesSinceEpoch(int fromEpoch) const;

    /**
     * @brief Applique un lot d'entrees recu d'un pair (sync_batch), en ignorant les entrees
     *        deja connues (entry_uuid dupliquee) : idempotent, rejouable sans risque.
     *        Ne resout pas les conflits de contenu applicatif (a la charge de l'appelant,
     *        qui doit utiliser lamport_clock/updated_at pour un LWW le cas echeant) ; se
     *        contente ici de fusionner le journal lui-meme.
     *
     * @return le nombre d'entrees effectivement inserees (les doublons ne comptent pas).
     */
    int applyBatch(const std::vector<models::SyncLogEntry> &batch);

    /**
     * @brief Plus grande valeur de lamport_clock connue localement (0 si journal vide),
     *        pour faire avancer l'horloge logique locale a chaque nouvelle ecriture.
     */
    qint64 highestLamportClock() const;

    /**
     * @brief Marque machineUuid comme synchronise jusqu'a l'epoch donne (PeerSyncState),
     *        pour eviter de rejouer deux fois le meme sync_batch (sync_ack idempotent).
     */
    bool markPeerSynced(const QString &machineUuid, int epoch);

    /**
     * @brief Dernier epoch connu comme synchronise pour ce pair (0 si jamais synchronise).
     */
    int lastSyncedEpoch(const QString &machineUuid) const;

    QString lastError() const;

private:
    models::SyncLogEntry entryFromQuery(const QSqlQuery &query) const;
    bool applyDomainEntry(const models::SyncLogEntry &entry);
    bool applyMessageEntry(const models::SyncLogEntry &entry);
    bool applyGroupEntry(const models::SyncLogEntry &entry);
    bool applyGroupMemberEntry(const models::SyncLogEntry &entry);
    bool applyUserEntry(const models::SyncLogEntry &entry);
    bool ensureConversation(qint64 conversationId, const QString &type, const QString &name);

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SYNCLOGREPOSITORY_H