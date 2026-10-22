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
#include "models/SharedFolderFilterProxy.h"

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
    Q_PROPERTY(models::SharedFolderFilterProxy* folderFilterProxy READ folderFilterProxy CONSTANT)
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

    /// Vue filtrée (mode + recherche) de folderModel, utilisée par
    /// SharedFolderView.qml pour GridView/ListView : contrairement a un
    /// filtrage par `visible` dans le delegate, les lignes exclues sont
    /// réellement retirées du modèle exposé, donc une GridView se
    /// recompacte correctement (pas de cellule vide laissée par un
    /// dossier masqué). Propriétés filterMode/searchText à synchroniser
    /// depuis QML avec root.activeFilter/root.searchText.
    models::SharedFolderFilterProxy* folderFilterProxy() const { return m_folderFilterProxy; }

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
    /// modification manuelle des fichiers hors LocaLink).
    Q_INVOKABLE bool shareFolder(qint64 folderId);

    /// Ouvre le dossier local (localPath()) d'un dossier partage dans
    /// l'explorateur de fichiers du systeme (Explorateur Windows, Finder,
    /// Nautilus...), meme principe que TransferContext::openFileLocation()
    /// deja utilise dans FileTransferView -- absent jusqu'ici de l'ecran
    /// "Dossiers partages", qui n'offrait aucun moyen d'acceder rapidement
    /// au contenu reel sur le disque.
    ///
    /// Retourne false (et emet errorOccurred()) si le dossier est
    /// introuvable, si c'est un dossier distant pas encore provisionne
    /// (localPath() vide -- rien a montrer avant que l'utilisateur
    /// n'accepte le partage, cf. acceptFolderShare()), ou si le chemin
    /// n'existe plus sur le disque (deplace/supprime manuellement).
    Q_INVOKABLE bool openFolderLocation(qint64 folderId);

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

    /// Accepte un partage de dossier distant en attente de confirmation
    /// (cf. folderShareConfirmationRequested()) : assigne le chemin local
    /// par défaut sous Documents/LocaLink Shared Folders/<nom>
    /// (SharedFolderManager::provisionDefaultLocalPath()) et déclenche un
    /// resync auprès du propriétaire pour récupérer le contenu (via le
    /// signal SharedFolderManager::folderLocalPathProvisioned, câblé dans
    /// app/Application.cpp).
    /// @return true si l'assignation a réussi (voir lastErrorString() sinon).
    Q_INVOKABLE bool acceptFolderShare(qint64 folderId);

    /// Décline (pour l'instant) un partage de dossier distant en attente de
    /// confirmation : ne fait RIEN de destructif -- le dossier reste dans la
    /// liste avec un localPath vide, sans qu'aucune synchronisation ne
    /// démarre. L'utilisateur pourra assigner un chemin plus tard via le
    /// dialogue existant ("Définir le dossier local", cf.
    /// setFolderLocalPath()). Un no-op explicite plutôt qu'une révocation
    /// d'accès : refuser l'auto-provisionnement ne signifie pas refuser le
    /// partage lui-même.
    Q_INVOKABLE void declineFolderShare(qint64 folderId);

    /// Récupère la liste des conflits du dossier sous forme de QVariantList de QVariantMap.
    Q_INVOKABLE QVariantList getConflicts(qint64 folderId) const;

    /// Indique si le dossier contient des conflits actifs.
    Q_INVOKABLE bool hasConflicts(qint64 folderId) const;

    /// Résout un conflit pour un dossier donné selon la stratégie choisie.
    Q_INVOKABLE bool resolveConflict(qint64 folderId, const QString &relativePath, const QString &conflictPath, const QString &resolution);

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

    /// Exclusions toujours actives, affichees dans la feuille des exclusions.
    Q_INVOKABLE QStringList builtinExcludePatterns() const;

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

    /// Retransmis depuis FolderSyncService::syncNotice.
    void syncNotice(const QString &folderUuid, const QString &relativePath, const QString &kind);

    /// Emis apres chaque reindexation reussie (qu'elle soit declenchee par
    /// FolderWatcher ou par l'utilisateur via shareFolder()), avec le nombre
    /// de changements journalises dans SyncOperations.  L'UI (SharedFolderView
    /// QML) ecoute ce signal pour rafraichir automatiquement la liste des
    /// fichiers et le panneau d'historique sans que l'utilisateur ait a
    /// cliquer sur "Reindexer".
    void folderReindexed(qint64 folderId, int changeCount);

    /// Retransmis depuis SyncEngine::reindexingStarted() : emis des que
    /// shareFolder() lance l'indexation en arriere-plan (sur le thread
    /// dedie, cf. core::sync::SharedFolderIndexWorker), AVANT que le
    /// resultat ne soit connu -- permet a SharedFolderView.qml d'afficher
    /// un indicateur "indexation en cours..." pendant que l'appli reste
    /// pleinement reactive (bouton, clics, redraws), au lieu du "ne
    /// repond plus" observe auparavant sur un poste peu performant.
    void indexingStarted(qint64 folderId);

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

    /**
     * @brief Un dossier partagé DISTANT vient d'être reçu pour la première
     * fois (accessGrantedLocal, isNewGrant == true) sans localPath assigné :
     * demande à l'UI (SharedFolderView.qml) d'afficher un dialogue de
     * confirmation avant de commencer quoi que ce soit sur le disque de
     * l'utilisateur, plutôt que d'auto-provisionner silencieusement.
     *
     * L'utilisateur répond en appelant acceptFolderShare(folderId) ou
     * declineFolderShare(folderId).
     *
     * @param folderId      Identifiant local du dossier partagé.
     * @param folderName    Nom du dossier tel que partagé.
     * @param ownerName     Nom d'utilisateur du propriétaire du dossier.
     * @param suggestedPath Aperçu (previewDefaultLocalPath(), sans effet de
     *                      bord) du chemin qui serait utilisé en cas
     *                      d'acceptation.
     * @param allowWrite    Permission accordée par le propriétaire (lecture
     *                      seule si false), affichée sous forme de badge
     *                      dans la boîte de confirmation.
     */
    void folderShareConfirmationRequested(qint64 folderId, const QString &folderName,
                                           const QString &ownerName, const QString &suggestedPath,
                                           bool allowWrite);

    /**
     * @brief Retransmis depuis FolderSyncService::folderTransferProgress
     *        (Release "barre de progression globale" du partage de dossier).
     *
     * Permet à l'UI (SharedFolderView.qml / un composant global type
     * ToastHost) d'afficher UNE SEULE barre de progression pour toute une
     * rafale de fichiers synchronisés, plutôt qu'une notification par
     * fichier -- voir la doc de FolderSyncService::folderTransferProgress
     * pour le détail des paramètres.
     */
    void folderTransferProgress(const QString &folderUuid, const QString &folderName,
                                 bool incoming, int filesCompleted, int filesTotal,
                                 qint64 bytesTransferred, qint64 bytesTotal);

    /**
     * @brief Retransmis (sous forme unifiée) depuis FolderSyncService::
     *        folderFilesReceived (incoming=true) ou folderFilesSent
     *        (incoming=false) : signale la fin d'une rafale, càd le moment
     *        où l'UI doit masquer la barre de progression correspondante
     *        (la notification finale "N fichiers reçus/envoyés" est
     *        affichée séparément par ToastHost).
     */
    void folderTransferComplete(const QString &folderUuid, const QString &folderName,
                                bool incoming, int fileCount);

private:
    models::SharedFolderModel *m_folderModel = nullptr;
    models::SharedFolderFilterProxy *m_folderFilterProxy = nullptr;
    SharedFolderManager *m_manager = nullptr;
    core::sync::SyncEngine *m_syncEngine = nullptr;
    UserManager *m_userManager = nullptr;
    core::sync::FolderSyncService *m_folderSyncService = nullptr;
    QString m_lastErrorString;
};

} // namespace core

#endif // CORE_SHAREDFOLDERCONTEXT_H