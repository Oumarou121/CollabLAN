#ifndef CORE_SHAREDFOLDERCONTEXT_H
#define CORE_SHAREDFOLDERCONTEXT_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

#include "SharedFolderManager.h"
#include "UserManager.h"
#include "core/Sync/SyncEngine.h"
#include "core/Sync/FolderSyncService.h"
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

    /// Branche FolderSyncService pour que conflictDetected soit retransmis a QML.
    void setFolderSyncService(core::sync::FolderSyncService *svc);

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
    /// excludePatterns (optionnel, debrief point #4) : motifs glob separes
    /// par des virgules (ex: "*.log, build, drafts/*") a exclure de ce
    /// dossier en plus des exclusions codees en dur -- cf.
    /// core::SharedFolderManager::createFolder().
    Q_INVOKABLE bool createFolder(const QString &name, const QString &localPath,
                                   const QVariantList &authorizedUserIds, bool allowWrite,
                                   const QString &excludePatterns = QString());

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

    /// Accorde l'acces a un utilisateur sur un dossier deja partage (grant
    /// post-creation). Utilise l'utilisateur courant comme grantedBy.
    /// Diffuse le grant aux autres machines via SharedFolderManager::accessGranted
    /// → FolderSyncService::announceAccessGranted (cable dans Application.cpp).
    /// @param allowWrite  true = lecture/ecriture, false = lecture seule.
    /// @return true si le grant a reussi (voir lastErrorString() sinon).
    Q_INVOKABLE bool grantAccess(qint64 folderId, qint64 userId, bool allowWrite);

    /// Modifie le niveau de permission d'un utilisateur deja present dans
    /// la liste d'acces (revoque puis re-accorde avec le nouveau niveau).
    /// @return true si la mise a jour a reussi.
    Q_INVOKABLE bool changePermission(qint64 folderId, qint64 userId, bool allowWrite);

    /// Définit le chemin local d'un dossier distant pour permettre la réception
    /// des fichiers. Nécessaire avant de pouvoir synchroniser le contenu d'un
    /// dossier partagé reçu d'un autre poste.
    /// @return true si la mise à jour a reussi (voir lastErrorString() sinon).
    Q_INVOKABLE bool setFolderLocalPath(qint64 folderId, const QString &localPath);

    /// Motifs d'exclusion (debrief point #4) actuellement configures pour
    /// un dossier partage, tels que stockes (normalises, separes par
    /// ", ") -- utilise pour preremplir le champ de saisie du dialogue
    /// "Modifier les exclusions" (ui/SharedFolder/SharedFolderView.qml).
    /// Chaine vide si le dossier est introuvable ou n'a aucun motif.
    Q_INVOKABLE QString excludePatternsForFolder(qint64 folderId) const;

    /// Met a jour les motifs d'exclusion d'un dossier deja partage. Ne
    /// declenche PAS de reindexation automatique : les fichiers deja
    /// indexes qui correspondent desormais a un motif ne seront
    /// tombstones qu'au prochain shareFolder() (cf.
    /// core::SharedFolderManager::updateExcludePatterns()) -- on
    /// reindexe explicitement ici pour que l'effet soit visible tout de
    /// suite dans l'UI plutot que d'attendre le prochain FolderWatcher.
    /// @return true si la mise a jour a reussi (voir lastErrorString() sinon).
    Q_INVOKABLE bool updateExcludePatterns(qint64 folderId, const QString &excludePatterns);

    /// Chemins relatifs des fichiers deja indexes qui deviendraient exclus
    /// si excludePatterns (pas encore enregistre) etait applique -- pour
    /// que le dialogue "Modifier les exclusions"
    /// (ui/SharedFolder/SharedFolderView.qml) puisse avertir l'utilisateur
    /// AVANT qu'il clique sur "Enregistrer", plutot que de le laisser
    /// decouvrir apres coup que des fichiers deja partages ont disparu.
    /// Liste vide si aucun impact, si le dossier est introuvable, ou si
    /// excludePatterns est mal forme (l'erreur de validation elle-meme
    /// n'apparaitra qu'a la sauvegarde reelle, cf. updateExcludePatterns()).
    Q_INVOKABLE QStringList previewExcludePatternsImpact(qint64 folderId, const QString &excludePatterns) const;

signals:
    void errorOccurred(const QString &message);

    /**
     * @brief Retransmis depuis FolderSyncService::conflictDetected (Release 8).
     *
     * Emis quand un fichier recu depuis le reseau entre en conflit avec un
     * fichier local de meme nom mais de contenu different : le fichier recu
     * a ete renomme en conflictPath. L'UI peut afficher un badge ou une
     * banniere pour alerter l'utilisateur.
     *
     * @param folderUuid   UUID du dossier concerne.
     * @param relativePath Chemin relatif du fichier en conflit (version locale).
     * @param conflictPath Chemin relatif de la copie renommee (version recue).
     */
    void conflictDetected(const QString &folderUuid,
                          const QString &relativePath,
                          const QString &conflictPath);

    /// Emis apres chaque reindexation reussie (qu'elle soit declenchee par
    /// FolderWatcher ou par l'utilisateur via shareFolder()), avec le nombre
    /// de changements journalises dans SyncOperations.  L'UI (SharedFolderView
    /// QML) ecoute ce signal pour rafraichir automatiquement la liste des
    /// fichiers et le panneau d'historique sans que l'utilisateur ait a
    /// cliquer sur "Reindexer".
    void folderReindexed(qint64 folderId, int changeCount);

    /**
     * @brief Retransmis depuis FolderSyncService::fileIntegrated (Release 8).
     *
     * Émis à chaque fichier reçu du réseau et intégré dans un dossier
     * partagé (transfert de synchronisation, PAS une réindexation locale).
     * Sans ce relais, SharedFolderView.qml ne se rafraîchissait que sur
     * folderReindexed (déclenché uniquement par FolderWatcher côté
     * propriétaire) : côté destinataire, les fichiers reçus par le réseau
     * n'apparaissaient qu'après avoir quitté puis rouvert l'écran.
     */
    void fileReceived(const QString &folderUuid, const QString &relativePath);

private:
    SharedFolderManager *m_manager = nullptr;
    core::sync::SyncEngine *m_syncEngine = nullptr;
    UserManager *m_userManager = nullptr;
    core::sync::FolderSyncService *m_folderSyncService = nullptr;
    models::SharedFolderModel *m_folderModel = nullptr;
    QString m_lastErrorString;
};

} // namespace core

#endif // CORE_SHAREDFOLDERCONTEXT_H
