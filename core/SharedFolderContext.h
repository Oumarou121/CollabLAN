#ifndef CORE_SHAREDFOLDERCONTEXT_H
#define CORE_SHAREDFOLDERCONTEXT_H

#include <QObject>
#include <QString>
#include <QVariantList>

#include "SharedFolderManager.h"
#include "UserManager.h"
#include "core/Sync/SyncEngine.h"
#include "models/SharedFolderModel.h"

namespace core {

/**
 * @brief Wrapper pour exposer le module "Shared Folder" a QML
 * (ui/SharedFolder/SharedFolderView.qml), sur le meme principe que
 * core::TransferContext pour le transfert de fichiers.
 *
 * Pour tout ce qui est CRUD pur (creer/supprimer/lister/lire le contenu
 * deja indexe), on appelle SharedFolderManager directement. En revanche,
 * toute (re)indexation passe par SyncEngine::reindexFolder() plutot que
 * par SharedFolderManager::shareFolder() directement, afin que les
 * changements detectes soient systematiquement journalises
 * (SyncOperations) -- cf. doc de conception, decoupage
 * SharedFolderManager (metier) / SyncEngine (orchestration).
 */
class SharedFolderContext : public QObject
{
    Q_OBJECT
    Q_PROPERTY(models::SharedFolderModel* folderModel READ folderModel CONSTANT)
    Q_PROPERTY(QString lastErrorString READ lastErrorString NOTIFY errorOccurred)

public:
    explicit SharedFolderContext(QObject *parent = nullptr);
    ~SharedFolderContext() override;

    void setSharedFolderManager(SharedFolderManager *manager);
    void setSyncEngine(core::sync::SyncEngine *engine);
    void setUserManager(UserManager *manager);

    models::SharedFolderModel* folderModel() const { return m_folderModel; }
    QString lastErrorString() const { return m_lastErrorString; }

    /// Recharge la liste des dossiers partages (et le nombre de fichiers
    /// de chacun) depuis la base. Appele automatiquement apres chaque
    /// creation/suppression/partage.
    Q_INVOKABLE void refresh();

    /// Cree un dossier partage a partir de localPath (chemin choisi via
    /// FolderDialog cote QML) puis l'indexe immediatement (shareFolder()) :
    /// depuis l'UI, "creer" et "partager" ne font qu'un, la distinction
    /// createFolder()/shareFolder() servant surtout a SharedFolderManager
    /// (ex: reindexer un dossier deja partage sans le recreer).
    /// @return true si la creation a reussi (voir lastErrorString() sinon).
    Q_INVOKABLE bool createFolder(const QString &name, const QString &localPath);

    Q_INVOKABLE bool removeFolder(qint64 folderId);

    /// Reindexe le contenu local d'un dossier deja partage (ex: apres
    /// modification manuelle des fichiers hors CollabLAN).
    Q_INVOKABLE bool shareFolder(qint64 folderId);

    /// Contenu (fichiers non supprimes) d'un dossier partage, pret a
    /// servir de modele QML : chaque element est une QVariantMap
    /// relativePath/size/hash/version/lastModified.
    Q_INVOKABLE QVariantList filesForFolder(qint64 folderId) const;

    /// Historique des operations de synchronisation (Create/Update/
    /// Delete/Rename) d'un dossier, les plus recentes d'abord. Chaque
    /// element est une QVariantMap type/relativePath/oldRelativePath/
    /// version/createdAt. Liste vide si SyncEngine n'est pas encore
    /// disponible (setSyncEngine() pas encore appele).
    Q_INVOKABLE QVariantList syncHistoryForFolder(qint64 folderId, int limit = 50) const;

signals:
    void errorOccurred(const QString &message);

    /// Emis apres chaque reindexation reussie (qu'elle soit declenchee par
    /// FolderWatcher ou par l'utilisateur via shareFolder()), avec le nombre
    /// de changements journalises dans SyncOperations.  L'UI (SharedFolderView
    /// QML) ecoute ce signal pour rafraichir automatiquement la liste des
    /// fichiers et le panneau d'historique sans que l'utilisateur ait a
    /// cliquer sur "Reindexer".
    void folderReindexed(qint64 folderId, int changeCount);

private:
    SharedFolderManager *m_manager = nullptr;
    core::sync::SyncEngine *m_syncEngine = nullptr;
    UserManager *m_userManager = nullptr;
    models::SharedFolderModel *m_folderModel = nullptr;
    QString m_lastErrorString;
};

} // namespace core

#endif // CORE_SHAREDFOLDERCONTEXT_H
