#ifndef CORE_SYNC_SYNCENGINE_H
#define CORE_SYNC_SYNCENGINE_H

#include <QObject>
#include <QString>
#include <QVector>

#include "core/Sync/FolderWatcher.h"
#include "core/SharedFolderManager.h"
#include "database/Repositories/SyncOperationRepository.h"
#include "models/FileSyncOperation.h"

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

    /// Historique des operations de synchronisation d'un dossier, les
    /// plus recentes d'abord (pour affichage dans l'UI).
    QVector<models::FileSyncOperation> historyForFolder(qint64 folderId, int limit = 100) const;

public slots:
    /// Appelé quand un dossier partagé est créé (pour démarrer la surveillance)
    void onFolderCreated(const models::SharedFolder &folder);
    /// Appelé quand un dossier partagé est supprimé (pour arrêter la surveillance)
    void onFolderRemoved(qint64 folderId);

signals:
    /// Emis apres chaque reindexFolder() reussi (meme si aucun changement
    /// n'a ete detecte), avec le nombre de changements journalises.
    void folderReindexed(qint64 folderId, int changeCount);

private slots:
    void onWatcherChangesDetected(qint64 folderId);

private:
    void watchFolder(qint64 folderId);

    core::SharedFolderManager *m_folderManager;
    FolderWatcher m_watcher;
    database::SyncOperationRepository m_operationRepository;
    QString m_machineId;
};

} // namespace core::sync

#endif // CORE_SYNC_SYNCENGINE_H
