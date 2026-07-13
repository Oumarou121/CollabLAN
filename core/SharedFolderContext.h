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
    ///
    /// authorizedUserIds : userId (qint64, cf. availableUsers()) des
    /// utilisateurs a qui accorder l'acces immediatement -- sans cela, le
    /// dossier cree n'est visible que par son proprietaire (cf. refresh()).
    /// allowWrite : true = acces en ecriture pour tous les utilisateurs
    /// choisis, false = lecture seule (pas de granularite par utilisateur
    /// pour cette 1ere version, cf. core::SharedFolderManager::createFolder()).
    /// @return true si la creation a reussi (voir lastErrorString() sinon).
    Q_INVOKABLE bool createFolder(const QString &name, const QString &localPath,
                                   const QVariantList &authorizedUserIds, bool allowWrite);

    /// Utilisateurs locaux a qui l'on peut accorder l'acces a un dossier
    /// partage (tous sauf l'utilisateur courant), sur le meme principe que
    /// core::MessagingContext::availableUsers() -- chaque element est une
    /// QVariantMap userId/username.
    Q_INVOKABLE QVariantList availableUsers() const;

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

    /// Utilisateurs a qui l'acces a ce dossier a ete explicitement accorde
    /// (le proprietaire n'apparait pas : son acces est implicite, cf.
    /// core::SharedFolderManager::createFolder()). Chaque element est une
    /// QVariantMap userId/username/permission ("Read"/"Write") -- utilise
    /// par le dialogue "Gérer les accès" (ui/SharedFolder/SharedFolderView.qml).
    Q_INVOKABLE QVariantList accessForFolder(qint64 folderId) const;

    /// Retire l'acces d'un utilisateur a un dossier partage. Diffuse aux
    /// autres machines (cf. core::sync::FolderSyncService::announceAccessRevoked(),
    /// connecte sur SharedFolderManager::accessRevoked dans app/Application.cpp).
    /// @return true si la revocation a reussi (voir lastErrorString() sinon).
    Q_INVOKABLE bool revokeAccess(qint64 folderId, qint64 userId);

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
