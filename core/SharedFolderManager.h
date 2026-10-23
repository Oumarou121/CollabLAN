#ifndef CORE_SHAREDFOLDERMANAGER_H
#define CORE_SHAREDFOLDERMANAGER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QHash>
#include <QVector>
#include <optional>

#include "database/Repositories/SharedFolderRepository.h"
#include "database/Repositories/SharedFileRepository.h"
#include "database/Repositories/SharedFolderAccessRepository.h"
#include "models/SharedFolder.h"
#include "models/SharedFile.h"
#include "models/SharedFileChange.h"
#include "models/SharedFolderAccess.h"
#include "models/SharedFolderPermission.h"

namespace database {
class DatabaseManager;
}

namespace core {

enum class SharedFolderManagerError {
    None,
    InvalidName,
    InvalidPath,
    PathNotDirectory,
    InvalidFolder,
    DatabaseError,
    InvalidExcludePatterns
};

/**
 * @brief Gestionnaire des dossiers partages (module "Shared Folder").
 *
 * Responsabilites, volontairement limitees au "metier" (cf. doc de
 * conception, section reorganisation) : creer/supprimer/lister des
 * dossiers partages et les indexer localement. Aucune logique reseau ni
 * de journal de synchronisation ici -- la surveillance du systeme de
 * fichiers (core::sync::FolderWatcher) et l'orchestration (creation de
 * SyncOperation, future synchronisation reseau) sont la responsabilite de
 * core::sync::SyncEngine, qui appelle shareFolder() et transforme son
 * resultat (QVector<models::SharedFileChange>) en journal persiste.
 *
 * shareFolder() effectue une indexation locale du contenu du dossier
 * (parcours recursif + hash SHA-256 de chaque fichier) et RAPPORTE ce qui
 * a change (nouveau fichier, modification, suppression, renommage) sans
 * jamais ecrire dans SyncOperations lui-meme : cette etape reste purement
 * locale (aucun octet n'est envoye sur le reseau).
 */
class SharedFolderManager : public QObject
{
    Q_OBJECT

public:
    explicit SharedFolderManager(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~SharedFolderManager() override;

    /// Cree un nouveau dossier partage a partir d'un chemin local existant.
    /// Echoue si le chemin n'existe pas ou n'est pas un dossier.
    ///
    /// authorizedUserIds (optionnel) : utilisateurs LOCAUX autres que le
    /// proprietaire a qui accorder immediatement un acces (SharedFolderAccess,
    /// migration #020) -- ex: les autres comptes de ce meme poste dans le cas
    /// "plusieurs utilisateurs, une seule machine". permission s'applique a
    /// tous les utilisateurs de la liste (pas de granularite par utilisateur
    /// pour cette 1ere version, cf. doc de conception). Chaque acces accorde
    /// emet accessGranted(), ecoute par core::sync::FolderSyncService pour
    /// diffuser la creation aux autres machines du reseau (cas "plusieurs
    /// machines LAN").
    /// excludePatterns (optionnel, debrief point #4) : motifs glob separes
    /// par des virgules (ex: "*.log,build,drafts/*") a exclure de
    /// l'indexation/sync pour CE dossier, en plus des exclusions codees
    /// en dur (isExcludedRelativePath()). Voir setExcludePatterns() pour
    /// le detail du format et validate/normalizeExcludePatterns() pour la
    /// validation appliquee.
    std::optional<models::SharedFolder> createFolder(const QString &name, const QString &localPath, qint64 ownerId,
                                                       const QVector<qint64> &authorizedUserIds = {},
                                                       models::SharedFolderPermission permission = models::SharedFolderPermission::Write,
                                                       const QString &excludePatterns = QString());

    /// Supprime un dossier partage (et son historique de fichiers, cascade
    /// SQL). Ne touche jamais aux fichiers reels sur le disque.
    bool removeFolder(qint64 folderId);

    /// Recupere tous les dossiers partages connus localement.
    QVector<models::SharedFolder> getFolders() const;

    /// Recupere les dossiers partages appartenant a un utilisateur donne.
    QVector<models::SharedFolder> getFolders(qint64 ownerId) const;

    std::optional<models::SharedFolder> getFolder(qint64 folderId) const;

    /// Parcourt recursivement localPath() et indexe (upsert) chaque
    /// fichier trouve dans SharedFiles (hash SHA-256, taille, date de
    /// derniere modification). Les entrees precedemment indexees dont le
    /// fichier n'existe plus sur le disque sont marquees supprimees
    /// (tombstone), sauf si un fichier de meme hash est apparu ailleurs
    /// sous un autre chemin relatif : ce cas est alors rapporte comme un
    /// Rename plutot qu'un Delete+Create.
    ///
    /// Retourne la liste des changements detectes (vide si le dossier
    /// n'a pas change depuis la derniere indexation), ou std::nullopt en
    /// cas d'erreur (dossier introuvable/inaccessible, voir lastError()).
    std::optional<QVector<models::SharedFileChange>> shareFolder(qint64 folderId);

    /// Fichiers actuellement connus (non supprimes) d'un dossier partage.
    QVector<models::SharedFile> getFiles(qint64 folderId) const;

    /// Nombre de fichiers (non supprimes) par dossier, en une requete.
    QHash<qint64, int> fileCountsByFolder() const;

    /// Copies de conflit possibles (nom "x (y).ext") ; folderId <= 0 : tous.
    QVector<models::SharedFile> conflictCandidates(qint64 folderId) const;

    /// Vrai si le fichier existe (non supprime) dans le dossier.
    bool hasActiveFile(qint64 folderId, const QString &relativePath) const;

    /// Recupere un dossier partage par son uuid stable (independant de
    /// l'id local), utilise notamment par core::sync::FolderSyncService
    /// pour retrouver/creer la replique locale d'un dossier annonce par
    /// un autre poste.
    std::optional<models::SharedFolder> getFolderByUuid(const QString &uuid) const;

    /// Dossiers visibles par un utilisateur donne : ceux dont il est
    /// proprietaire + ceux pour lesquels un acces explicite lui a ete
    /// accorde (SharedFolderAccess, migration #020). Remplace getFolders()
    /// (qui retournait TOUS les dossiers a TOUT utilisateur local, sans
    /// aucune restriction) comme source de la liste affichee dans
    /// SharedFolderView.qml.
    QVector<models::SharedFolder> getAccessibleFolders(qint64 userId) const;

    /// Accorde (ou met a jour) l'acces d'un utilisateur a un dossier partage.
    /// Emet toujours accessGranted() pour le rafraîchissement UI.
    /// broadcastNetwork contrôle si FolderSyncService doit diffuser l'annonce
    /// reseau (pour éviter les boucles quand l'accès est accordé suite à un message réseau).
    bool grantAccess(qint64 folderId, qint64 userId, qint64 grantedBy,
                      models::SharedFolderPermission permission = models::SharedFolderPermission::Write,
                      bool broadcastNetwork = true);

    /// Revoque l'acces d'un utilisateur a un dossier partage (no-op si
    /// aucun acces n'existait -- idempotent, cf. SharedFolderAccessRepository::revoke()).
    /// broadcastNetwork=false doit etre utilise quand la revocation provient
    /// deja d'un message reseau (cf. FolderSyncService::handleFolderAccessRevoked()),
    /// pour eviter de rediffuser indefiniment le meme evenement entre pairs.
    bool revokeAccess(qint64 folderId, qint64 userId, bool broadcastNetwork = true);

    /// Liste des acces explicitement accordes sur un dossier (n'inclut PAS
    /// le proprietaire, qui a un acces implicite total).
    QVector<models::SharedFolderAccess> accessForFolder(qint64 folderId) const;

    /// Enregistre localement les METADONNEES d'un dossier partage cree sur
    /// un AUTRE poste (reception reseau, cf. core::sync::FolderSyncService::
    /// handleFolderAccessGranted()). Ne touche jamais au disque : localPath
    /// reste vide, seul un futur transfert de fichiers donnera un contenu
    /// reel a ce dossier sur ce poste. Idempotent (no-op si l'uuid existe
    /// deja localement -- retourne alors le dossier existant).
    std::optional<models::SharedFolder> registerRemoteFolder(const QString &uuid, const QString &name,
                                                               qint64 ownerId, const QString &originMachineId);

    /// Corrige l'origin_machine_id d'un dossier DEJA enregistre localement
    /// (registerRemoteFolder() ne le fait qu'a la creation -- cf. son
    /// commentaire "idempotent"). A appeler quand FolderSyncService::
    /// handleFolderAccessGranted() recoit, pour un uuid deja connu ici,
    /// un origin_machine_id different de celui stocke localement : sans
    /// cette correction le dossier reste bloque isLocalOrigin()==true (ou
    /// pointe vers un poste qui n'est plus le veritable proprietaire) et
    /// aucun resync n'est plus jamais demande pour lui.
    bool reconcileFolderOrigin(qint64 folderId, const QString &originMachineId);

    /// Met à jour le chemin local d'un dossier distant pour permettre la réception
    /// des fichiers. Nécessaire avant de pouvoir synchroniser le contenu d'un
    /// dossier partagé reçu d'un autre poste.
    bool updateFolderLocalPath(qint64 folderId, const QString &localPath);

    /// Assigne automatiquement un chemin local par défaut à un dossier
    /// partagé DISTANT qui n'en a pas encore (registerRemoteFolder() laisse
    /// localPath vide, cf. son commentaire) : Documents/LocaLink Shared
    /// Folders/<nom du dossier>, désambiguïsé ("<nom> (2)", "<nom> (3)"...)
    /// si ce nom est déjà pris sur le disque OU par un autre SharedFolder
    /// connu -- au lieu d'attendre que l'utilisateur choisisse lui-même un
    /// chemin via setFolderLocalPath()/updateFolderLocalPath() avant que la
    /// moindre synchronisation ne puisse démarrer.
    ///
    /// No-op (retourne le chemin existant) si le dossier a déjà un
    /// localPath, ou std::nullopt si le dossier est introuvable, est
    /// d'origine LOCALE (isLocalOrigin(), n'a jamais de sens à
    /// auto-provisionner : son localPath a été choisi explicitement à la
    /// création), ou si la création du dossier sur le disque a échoué (voir
    /// lastErrorString()).
    ///
    /// N'effectue AUCUNE demande réseau (pas de resync) : c'est à
    /// l'appelant (cf. app/Application.cpp, connecté sur
    /// folderLocalPathProvisioned()) de déclencher
    /// core::sync::FolderSyncService::requestFolderResync() une fois le
    /// chemin assigné, comme le fait déjà setFolderLocalPath() côté UI.
    ///
    /// Émet folderLocalPathProvisioned() en cas de succès -- ne PAS appeler
    /// automatiquement à la réception d'un accès (cf. commentaire ci-dessus
    /// sur le consentement implicite) : c'est désormais à l'utilisateur de
    /// déclencher cet appel explicitement en acceptant le dialogue de
    /// confirmation (core::SharedFolderContext::acceptFolderShare()).
    std::optional<QString> provisionDefaultLocalPath(qint64 folderId);

    /// Aperçu, SANS AUCUN EFFET DE BORD (ni création de dossier sur le
    /// disque, ni écriture en base), du chemin que provisionDefaultLocalPath()
    /// choisirait pour ce dossier -- même logique de désambiguïsation
    /// ("<nom> (2)", ...), mais purement en lecture. Utilisé par le
    /// dialogue de confirmation de partage (SharedFolderContext) pour
    /// montrer à l'utilisateur OÙ le contenu serait placé AVANT qu'il
    /// n'accepte, sans jamais créer quoi que ce soit tant qu'il n'a pas
    /// validé -- rouvrir/fermer le dialogue plusieurs fois ne doit pas
    /// laisser de dossiers vides orphelins sur le disque.
    ///
    /// Mêmes conditions de retour std::nullopt que provisionDefaultLocalPath()
    /// (dossier introuvable ou d'origine locale), sauf qu'aucune erreur
    /// d'écriture disque n'est possible ici puisque rien n'est écrit.
    std::optional<QString> previewDefaultLocalPath(qint64 folderId) const;

    /// Permet de substituer le dossier de base "Documents/LocaLink Shared
    /// Folders" utilisé par previewDefaultLocalPath()/provisionDefaultLocalPath()
    /// -- EXCLUSIVEMENT destiné aux tests automatisés (QStandardPaths::
    /// setTestModeOn() n'étant pas disponible avec cette configuration Qt/
    /// MSVC). Ne JAMAIS appeler en production : sans ceci, les tests
    /// devaient nettoyer le vrai dossier Documents de la machine avant/après
    /// chaque exécution, ce qui supprimait les vrais dossiers/fichiers
    /// partagés de l'utilisateur à chaque `ctest`. Chaîne vide (défaut) =
    /// comportement normal (vrai ~/LocaLink/Dossiers partagés).
    void setSharedFoldersBaseDirOverrideForTests(const QString &baseDir);

    /// Met a jour les motifs d'exclusion (debrief point #4, sync
    /// selective) d'un dossier partage deja cree. N'affecte que la
    /// PROCHAINE indexation (shareFolder()) : les fichiers deja indexes
    /// qui correspondent desormais a un motif ne sont pas retires
    /// retroactivement -- ils seront tombstones (marques supprimes) au
    /// prochain shareFolder(), comme tout fichier disparu du disque.
    /// @return true si la mise a jour a reussi (voir lastErrorString() sinon,
    /// notamment InvalidExcludePatterns si un motif est vide/mal forme).
    bool updateExcludePatterns(qint64 folderId, const QString &excludePatterns);

    /// Previsualise l'impact d'un jeu de motifs candidat (pas forcement
    /// encore enregistre, cf. updateExcludePatterns()) sur le contenu
    /// DEJA indexe d'un dossier partage : renvoie les chemins relatifs des
    /// fichiers actuellement connus (non supprimes) qui deviendraient
    /// exclus si candidateExcludePatterns etait applique puis le dossier
    /// reindexe. Utilise par le dialogue "Exclusions" (SharedFolderView.qml)
    /// pour avertir l'utilisateur AVANT qu'il valide -- sans cela, un motif
    /// trop large ("*.md" au lieu de "*.tmp") tombstone silencieusement des
    /// fichiers deja partages des la sauvegarde, sans avertissement prealable.
    ///
    /// N'effectue AUCUNE ecriture (ni en base, ni sur le disque) : lecture
    /// seule sur l'etat deja indexe. Methode const, ne modifie donc PAS
    /// lastError()/lastErrorString() -- retourne simplement une liste vide
    /// si le dossier est introuvable, si candidateExcludePatterns est
    /// invalide (motif malforme), ou si aucun fichier indexe ne correspond.
    QStringList previewExcludePatternsImpact(qint64 folderId, const QString &candidateExcludePatterns) const;

    /// Indique si relativePath serait exclu de l'indexation/sync de folderId,
    /// compte tenu des exclusions codees en dur (isExcludedRelativePath())
    /// ET des motifs propres a ce dossier (excludePatterns()). Utilise cote
    /// RECEPTION (core::sync::FolderSyncService::handleFolderOp() /
    /// handleFolderCatchupBatch()) pour refuser une annonce/un transfert
    /// entrant qui matche NOS PROPRES motifs locaux -- sans ce garde-fou,
    /// exclure "node_modules" localement n'empeche pas de recevoir quand
    /// meme "node_modules" pousse par un pair qui n'a pas ce motif de son
    /// cote (excludePatterns est une colonne LOCALE, non synchronisee entre
    /// pairs, cf. migration #022). false si le dossier est introuvable
    /// (aucune exclusion applicable, l'appelant gere ce cas autrement).
    bool isPathExcluded(qint64 folderId, const QString &relativePath) const;

    /// Exclusions toujours actives (dossiers de versionnage, fichiers
    /// systeme, verrous d'editeurs, fichiers temporaires), sous forme de
    /// motifs lisibles pour l'interface.
    static QStringList builtinExcludePatterns();

    SharedFolderManagerError lastError() const { return m_lastError; }
    QString lastErrorString() const { return m_lastErrorString; }

signals:
    void folderCreated(const models::SharedFolder &folder);
    void folderRemoved(qint64 folderId);
    /// fileCount = nombre de fichiers non supprimes APRES l'indexation
    /// (utilise par l'UI, cf. models::SharedFolderModel::FileCountRole).
    /// Emis meme si changes() (shareFolder()) est vide.
    void folderShared(qint64 folderId, int fileCount);
    /// Emis a chaque acces accorde (creation ou grantAccess() explicite).
    /// core::sync::FolderSyncService y est connecte (cf. app/Application.cpp)
    /// pour diffuser l'annonce "folder_access_granted" aux autres machines.
    void accessGranted(qint64 folderId, qint64 userId, models::SharedFolderPermission permission);
    /// Emis a chaque acces accorde pour le rafraîchissement UI local.
    /// Toujours émis, même quand broadcastNetwork est false (accès accordé via réseau).
    /// isNewGrant = false si cette paire (folderId, userId) avait déjà une
    /// ligne SharedFolderAccess AVANT cet appel (ré-application idempotente
    /// d'un grant déjà connu -- notamment à chaque reconnexion/catchup hors
    /// ligne, cf. core::sync::FolderSyncService::handleFolderAccessGranted(),
    /// rejoué sans condition sur folder_hello/catchup). Les abonnés qui
    /// déclenchent une action visible pour l'utilisateur UNE SEULE FOIS par
    /// partage (notification "dossier partagé avec vous", demande de
    /// confirmation d'auto-provisionnement dans SharedFolderContext) doivent
    /// se filtrer sur isNewGrant == true ; ceux qui font un simple
    /// rafraîchissement idempotent de l'UI (refresh()) peuvent l'ignorer.
    void accessGrantedLocal(qint64 folderId, qint64 userId, bool isNewGrant);

    /// Emis a chaque acces revoque (revokeAccess()). core::sync::FolderSyncService
    /// y est connecte pour diffuser "folder_access_revoked" aux autres machines
    /// (contrairement aux grants, les revocations ne sont PAS rattrapees hors-ligne :
    /// si le destinataire etait deconnecte au moment de la revocation, il ne le
    /// saura qu'a la prochaine action de partage sur ce dossier -- limitation
    /// acceptee pour borner la portee de cette 1ere version).
    void accessRevoked(qint64 folderId, qint64 userId);
    /// Emis a chaque acces revoque pour le rafraîchissement UI local.
    /// Toujours émis, même quand l'accès est révoqué suite à un message réseau.
    void accessRevokedLocal(qint64 folderId, qint64 userId);

    /// Émis par provisionDefaultLocalPath() en cas de succès : un chemin
    /// local par défaut vient d'être assigné à un dossier partagé DISTANT
    /// (que ce soit suite à acceptFolderShare() côté utilisateur, ou tout
    /// autre appelant futur). app/Application.cpp y est connecté pour
    /// déclencher le resync réseau (FolderSyncService::requestFolderResync())
    /// et la notification "synchronisation démarrée dans ..." -- centralise
    /// ce qui était auparavant fait en ligne dans le handler
    /// accessGrantedLocal() de Application.cpp.
    void folderLocalPathProvisioned(qint64 folderId, const QString &localPath);

private:
    database::DatabaseManager *m_dbManager = nullptr;
    QString m_sharedFoldersBaseDirOverride; // tests only, cf. setSharedFoldersBaseDirOverrideForTests()
    database::SharedFolderRepository m_folderRepository;
    database::SharedFileRepository m_fileRepository;
    database::SharedFolderAccessRepository m_accessRepository;
    SharedFolderManagerError m_lastError = SharedFolderManagerError::None;
    QString m_lastErrorString;
};

} // namespace core

#endif // CORE_SHAREDFOLDERMANAGER_H