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

    /**
     * @brief Retrouve (ou cree si absente) la Conversation locale
     *        correspondant a cet uuid stable, et retourne son id LOCAL
     *        (jamais celui de la machine d'origine : l'autoincrement
     *        local n'a aucune raison de coincider entre deux bases
     *        SQLite independantes - cf. migration 011). Utilise en
     *        interne par applyGroupEntry/applyMessageEntry, et
     *        directement par MessagingManager::receiveMessage pour
     *        resoudre la conversation d'un message recu en temps reel.
     * @return -1 en cas d'echec.
     *
     * @param participant1Id / @param participant2Id id LOCAUX (deja resolus
     *        par l'appelant via UserRepository::findByUuid) des deux membres
     *        d'une conversation individuelle. Laisses a -1 par defaut (non
     *        renseignes : cas des groupes, ou l'appelant ne les connait pas
     *        encore). Sans cela, une conversation individuelle creee ici
     *        n'a ni participant1_id ni participant2_id : elle devient
     *        invisible pour toujours dans MessagingManager::getUserConversations()
     *        (qui filtre sur ces deux colonnes), meme si les messages sont
     *        bien inseres en base - c'etait la cause du bug "message recu
     *        mais qui n'apparait nulle part".
     */
    qint64 ensureConversationByUuid(const QString &conversationUuid, const QString &type, const QString &name,
                                     qint64 participant1Id = -1, qint64 participant2Id = -1);

    /**
     * @brief Applique une entree SyncLog de type utilisateur (idempotente,
     *        avec logique anti-collision de nom). Utilisee en interne par
     *        applyBatch(), et directement par Application pour appliquer
     *        une entree utilisateur unique recue hors reconciliation batch.
     */
    bool applyUserEntry(const models::SyncLogEntry &entry);

private:
    models::SyncLogEntry entryFromQuery(const QSqlQuery &query) const;
    bool applyDomainEntry(const models::SyncLogEntry &entry);
    bool applyMessageEntry(const models::SyncLogEntry &entry);
    bool applyGroupEntry(const models::SyncLogEntry &entry);
    bool applyGroupMemberEntry(const models::SyncLogEntry &entry);

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SYNCLOGREPOSITORY_H