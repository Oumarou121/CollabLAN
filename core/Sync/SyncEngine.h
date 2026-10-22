#ifndef CORE_SYNC_SYNCENGINE_H
#define CORE_SYNC_SYNCENGINE_H

#include <QObject>
#include <QPointer>
#include <QHash>
#include <QSet>
#include <QTimer>
#include <QString>
#include <QThread>
#include <QVector>

#include "core/Sync/FolderWatcher.h"
#include "core/Sync/SharedFolderIndexWorker.h"
#include "core/SharedFolderManager.h"
#include "database/Repositories/SyncOperationRepository.h"
#include "database/Repositories/SharedFolderAccessRepository.h"
#include "database/Repositories/UserRepository.h"
#include "models/FileSyncOperation.h"
#include "models/SharedFolderPermission.h"

namespace database {
class DatabaseManager;
}

namespace core::sync {

/**
 * @brief Point d'orchestration unique de la synchronisation d'un dossier
 * partage (doc de conception : "SyncEngine" extrait de SharedFolderManager
 * pour ne pas melanger CRUD/metier et orchestration).
 *
 * Possede un FolderWatcher (detection locale, Release 2) et un
 * SyncOperationRepository (journal, Release 3). Toute (re)indexation --
 * qu'elle vienne de la creation d'un dossier, d'un bouton "reindexer"
 * manuel dans l'UI, ou d'un changement detecte par FolderWatcher -- DOIT
 * passer par reindexFolder() plutot que d'appeler
 * SharedFolderManager::shareFolder() directement, afin que chaque
 * changement soit systematiquement journalise (SyncOperations).
 *
 * Aucune logique reseau ici (Release 4+) : cette classe restera le point
 * d'ancrage pour un futur NetworkManager/FileTransferService/
 * ConflictResolver, mais rien de tel n'est instancie pour l'instant.
 */
class SyncEngine : public QObject
{
    Q_OBJECT

public:
    /// machineId : identifiant local (network::DiscoveryService::localId())
    /// enregistre sur chaque SyncOperation produite par ce poste.
    SyncEngine(core::SharedFolderManager *folderManager,
               database::DatabaseManager *dbManager,
               QString machineId,
               QObject *parent = nullptr);
    ~SyncEngine() override;

    /// Commence a surveiller tous les dossiers partages actuellement
    /// connus (a appeler une fois au demarrage de l'application, une fois
    /// SharedFolderManager pret).
    void start();

    /// (Re)indexe un dossier partage via SharedFolderManager::shareFolder(),
    /// persiste chaque changement detecte comme une models::FileSyncOperation,
    /// rafraichit la surveillance FolderWatcher (nouveaux/anciens fichiers),
    /// et retourne le nombre de changements journalises (-1 en cas
    /// d'erreur, voir SharedFolderManager::lastError()).
    int reindexFolder(qint64 folderId);

    /// Variante non bloquante de reindexFolder(), destinee aux
    /// declenchements interactifs (bouton "partager"/"reindexer" de
    /// l'UI, cf. SharedFolderContext::shareFolder()) : le parcours
    /// recursif + hash SHA-256 + upserts SQLite (SharedFolderManager::
    /// shareFolder(), le vrai cout) s'execute sur un QThread dedie
    /// (m_indexThread/m_indexWorker) avec sa propre connexion SQLite --
    /// la boucle d'evenements du thread UI n'est plus jamais bloquee,
    /// meme sur un poste peu performant avec un gros dossier (cf. debrief
    /// perf : "l'app ne repond plus" lors du partage d'un dossier).
    ///
    /// Emet reindexingStarted(folderId) immediatement (appelant a l'etat
    /// "indexation en cours" pour retour visuel UI), puis, une fois le
    /// worker termine, effectue le meme travail de post-traitement que
    /// reindexFolder() (journalisation SyncOperations, rafraichissement
    /// FolderWatcher) sur le thread UI avant d'emettre folderReindexed()
    /// -- ces ecritures-la restent rapides (une ligne par changement) et
    /// n'ont pas besoin d'etre deportees.
    ///
    /// No-op silencieux (ni reindexingStarted ni folderReindexed) si le
    /// dossier ne doit pas etre reindexe (memes conditions que
    /// reindexFolder() : localPath vide ou permission Read seule, cf.
    /// canWatchFolder()).
    void reindexFolderAsync(qint64 folderId);

    /// Historique des operations de synchronisation d'un dossier, les
    /// plus recentes d'abord (pour affichage dans l'UI).
    QVector<models::FileSyncOperation> historyForFolder(qint64 folderId, int limit = 100) const;

    /// Identifiant de l'utilisateur courant sur cette machine
    /// (core::UserManager::currentUserId()). Necessaire pour resoudre la
    /// permission effective (Read/Write) du poste local sur un dossier
    /// distant replique (localPath non vide, isLocalOrigin() == false) :
    /// seul un membre Write doit voir son FolderWatcher surveiller le
    /// dossier et diffuser ses changements (cf. plan de synchronisation
    /// bidirectionnelle, point 1 et 3). Sans identifiant connu (avant
    /// connexion), seuls les dossiers dont isLocalOrigin() est vrai sont
    /// surveilles.
    ///
    /// CORRECTIF (reindex manuel necessaire cote expediteur) : start() est
    /// appele au demarrage de l'app, potentiellement AVANT que le login ne
    /// soit termine (setLocalUserId() n'est alors appele que plus tard,
    /// via UserManager::loginSucceeded). Pour tout dossier dont on est
    /// membre Write mais pas isLocalOrigin(), canWatchFolder() refusait la
    /// surveillance a ce moment-la (m_localUserId encore a -1) -- et rien
    /// ne redeclenchait watchFolder() une fois l'identifiant connu : ce
    /// dossier restait non surveille pour toute la session, obligeant a
    /// un reindex manuel pour que les nouveaux fichiers locaux soient pris
    /// en compte. setLocalUserId() reevalue desormais canWatchFolder()
    /// pour tous les dossiers connus (watchFolder() est idempotent).
    void setLocalUserId(qint64 userId);

    /// Reevalue canWatchFolder() pour tous les dossiers connus et
    /// (re)demarre leur surveillance si necessaire. watchFolder() est
    /// idempotent (unwatchFolder() puis reajout), donc sans effet de bord
    /// sur un dossier deja correctement surveille. A appeler chaque fois
    /// qu'une condition affectant canWatchFolder() change (ex :
    /// identifiant utilisateur local desormais connu).
    void refreshWatchedFolders();

    /// Ignore temporairement les notifications du watcher apres l'ecriture
    /// d'un fichier recu du reseau. La metadata est deja enregistree par
    /// FolderSyncService : un reindex immediat le rediffuserait comme une
    /// fausse modification locale.
    void suppressWatcherChanges(qint64 folderId, int durationMs = 3000);

public slots:
    /// Appelé quand un dossier partagé est créé (pour démarrer la surveillance)
    void onFolderCreated(const models::SharedFolder &folder);
    /// Appelé quand un dossier partagé est supprimé (pour arrêter la surveillance)
    void onFolderRemoved(qint64 folderId);

signals:
    /// Emis apres chaque reindexFolder() reussi (meme si aucun changement
    /// n'a ete detecte), avec le nombre de changements journalises.
    void folderReindexed(qint64 folderId, int changeCount);

    /// Emis par reindexFolderAsync() des que l'indexation demarre sur le
    /// thread dedie (avant que le resultat ne soit connu) -- permet a
    /// l'UI d'afficher un indicateur "indexation en cours..." pendant que
    /// l'appli reste reactive, plutot que de sembler figee.
    void reindexingStarted(qint64 folderId);

private slots:
    void onWatcherChangesDetected(qint64 folderId);
    void onIndexWorkerFinished(qint64 folderId, bool ok, QVector<models::SharedFileChange> changes, QString errorString);

private slots:
    /// Appele quand SharedFolderManager assigne (ou change) le localPath
    /// d'un dossier distant (provisionnement initial ou choix utilisateur
    /// via setFolderLocalPath()) : demarre la surveillance si le poste
    /// local a la permission Write, sans quoi le contenu recu ne serait
    /// jamais rediffuse (cf. plan, point 1).
    void onFolderLocalPathProvisioned(qint64 folderId, const QString &localPath);

private:
    void watchFolder(qint64 folderId);

    /// Un dossier peut etre surveille par ce poste s'il a un contenu
    /// local reel (localPath non vide) ET si l'utilisateur local a la
    /// permission Write dessus. Le proprietaire (isLocalOrigin()) a
    /// toujours Write ; pour un dossier replique, la permission
    /// explicite est interrogee via SharedFolderAccessRepository.
    bool canWatchFolder(const models::SharedFolder &folder) const;

    /// Factorise le post-traitement commun a reindexFolder() (synchrone)
    /// et onIndexWorkerFinished() (issu de reindexFolderAsync()) : chaque
    /// SharedFileChange devient une models::FileSyncOperation persistee,
    /// puis la surveillance FolderWatcher est rafraichie. Retourne le
    /// nombre de changements effectivement journalises. N'emet PAS
    /// folderReindexed() elle-meme -- laisse a l'appelant (qui peut avoir
    /// besoin d'agir juste avant, cf. onIndexWorkerFinished()).
    int persistIndexChanges(qint64 folderId, const QVector<models::SharedFileChange> &changes);

    core::SharedFolderManager *m_folderManager;
    FolderWatcher m_watcher;
    database::SyncOperationRepository m_operationRepository;
    database::SharedFolderAccessRepository m_accessRepository;
    database::UserRepository m_userRepository;
    QString m_machineId;
    qint64 m_localUserId = -1;
    QHash<qint64, qint64> m_ignoreWatcherUntilMs;
    /// Reindexation demandee pendant la fenetre d'ignorance : relancee a sa fin
    /// (auparavant abandonnee, et une modification locale faite a ce moment
    /// n'etait jamais diffusee).
    QHash<qint64, QTimer *> m_deferredReindex;
    /// Indexations asynchrones en cours, et dossiers a reindexer de nouveau a
    /// leur fin (changements survenus pendant le parcours).
    QSet<qint64> m_indexInFlight;
    QSet<qint64> m_indexDirty;
    void requestReindex(qint64 folderId);

    // Indexation asynchrone (reindexFolderAsync()) : thread + worker
    // dedies, vivant pour toute la duree de vie de ce SyncEngine (cf.
    // SharedFolderIndexWorker pour le detail de la connexion SQLite
    // separee qu'il possede).
    QThread *m_indexThread = nullptr;
    QPointer<SharedFolderIndexWorker> m_indexWorker;
};

} // namespace core::sync

#endif // CORE_SYNC_SYNCENGINE_H
