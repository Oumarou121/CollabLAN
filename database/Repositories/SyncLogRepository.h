#ifndef DATABASE_SYNCLOGREPOSITORY_H
#define DATABASE_SYNCLOGREPOSITORY_H

#include <QJsonObject>
#include <QSqlDatabase>
#include <QString>
#include <QStringList>
#include <optional>
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
     * @brief Entrees de id local strictement superieur a afterId, dans l'ordre
     *        d'ecriture locale. Synchronisation incrementale d'un client : l'id
     *        local croit toujours, y compris pour les entrees fusionnees depuis un
     *        serveur de secours (alors que leur lamport_clock peut etre ancien).
     */
    std::vector<models::SyncLogEntry> entriesAfterId(qint64 afterId) const;
    /// Plus grand id local du journal (0 si vide).
    qint64 maxEntryId() const;
    /// Vrai si une entree existe deja pour cet enregistrement.
    bool hasRecord(const QString &tableName, const QString &recordUuid) const;

    /// Curseur de synchronisation incrementale (table SyncCursors) : dernier id
    /// du journal de ce serveur deja recu pour cet utilisateur (0 si aucun).
    qint64 syncCursor(const QString &serverKey, const QString &userUuid) const;
    bool setSyncCursor(const QString &serverKey, const QString &userUuid, qint64 lastLogId);

    /**
     * @brief Retire d'un lot les changements de comptes qu'une source autre que
     *        le serveur officiel ne doit pas imposer : aucun compte n'y devient
     *        administrateur (creation en simple utilisateur), aucun role ni mot de
     *        passe existant n'y est modifie, aucune suppression. Sans ce filtre,
     *        un poste autorise qui s'annoncait serveur de secours pouvait, par la
     *        reconciliation, changer le mot de passe d'un administrateur sur
     *        tout le reseau (regle "dernier ecrit gagne").
     * @return l'entree filtree, ou std::nullopt si elle doit etre ignoree.
     */
    static std::optional<models::SyncLogEntry> restrictUserEntry(const models::SyncLogEntry &entry);
    static std::vector<models::SyncLogEntry> restrictUserEntries(const std::vector<models::SyncLogEntry> &entries);

    /// Payload de creation (entree INSERT) d'un message journalise : expediteur,
    /// conversation, participants. Sert au serveur a verifier l'auteur d'une
    /// modification et a adresser les accuses. std::nullopt si inconnu.
    std::optional<QJsonObject> messageInsertPayload(const QString &messageUuid) const;

    /// Uuids des messages dont un accuse a ete applique depuis le dernier appel
    /// (l'appelant recalcule leur etat d'envoi).
    QStringList takeTouchedReceiptMessages();

    /**
     * @brief Purge les entrees devenues inutiles : pour un meme enregistrement,
     *        seul l'etat le plus recent est garde (comptes, accuses, membres de
     *        groupe, renommages) ; un message supprime perd aussi son texte dans
     *        l'entree de creation. Le journal ne garde ainsi que l'utile, sans
     *        rien perdre pour un poste qui se synchronise ensuite. Les messages
     *        eux-memes ne sont jamais purges (c'est l'historique).
     * @return le nombre d'entrees retirees.
     */
    int compact();

    /// Supprime localement un groupe, ses membres, sa conversation et son fil.
    /// Idempotent (groupe deja absent : vrai).
    static bool deleteGroupByUuid(QSqlDatabase db, const QString &groupUuid, QString *error = nullptr);

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
    /// Nombre d'entrees du dernier lot restees differees (dependance absente).
    int lastBatchPendingCount() const { return m_lastBatchPending; }

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
    bool applyMessageChange(const models::SyncLogEntry &entry);
    bool applyReceiptEntry(const models::SyncLogEntry &entry);
    QStringList m_touchedReceiptMessages;

    QSqlDatabase m_db;
    mutable QString m_lastError;
    int m_lastBatchPending = 0;
};

} // namespace database

#endif // DATABASE_SYNCLOGREPOSITORY_H