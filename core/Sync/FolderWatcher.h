#ifndef CORE_SYNC_FOLDERWATCHER_H
#define CORE_SYNC_FOLDERWATCHER_H

#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <QTimer>

class QFileSystemWatcher;

namespace core::sync {

/**
 * @brief Detecte les changements sur le systeme de fichiers d'un ou
 * plusieurs dossiers partages (Release 2 de la doc de conception --
 * "detection des changements", aucun reseau a ce stade).
 *
 * Enveloppe QFileSystemWatcher, qui a deux limites qu'il faut compenser :
 *  - directoryChanged() signale qu'UN dossier a change (fichier/sous-
 *    dossier ajoute/supprime/renomme) mais pas LEQUEL ni COMMENT ;
 *  - il ne signale JAMAIS une modification de contenu en place d'un
 *    fichier existant (seul fileChanged(), sur le chemin exact du
 *    fichier, le fait).
 *
 * FolderWatcher surveille donc a la fois la racine + tous les sous-
 * dossiers d'un dossier partage (pour les ajouts/suppressions/
 * renommages) ET chaque fichier actuellement connu (pour les
 * modifications de contenu), et regroupe les deux en un seul signal
 * debounce changesDetected(folderId) : un rescan complet (via
 * SyncEngine::reindexFolder()) est de toute facon necessaire pour savoir
 * PRECISEMENT ce qui a change (cf. SharedFolderManager::shareFolder()),
 * inutile de tenter de le determiner ici.
 */
class FolderWatcher : public QObject
{
    Q_OBJECT

public:
    explicit FolderWatcher(QObject *parent = nullptr);
    ~FolderWatcher() override;

    /// Commence a surveiller un dossier partage : sa racine, tous ses
    /// sous-dossiers, et chaque fichier de knownRelativePaths (chemins
    /// relatifs a rootPath). Remplace toute surveillance precedente pour
    /// ce folderId.
    void watchFolder(qint64 folderId, const QString &rootPath, const QStringList &knownRelativePaths);

    /// Arrete toute surveillance pour ce dossier (ex: dossier supprime).
    void unwatchFolder(qint64 folderId);

    /// A appeler apres chaque reindexation reussie : met a jour la liste
    /// des chemins de fichiers surveilles (nouveaux fichiers ajoutes,
    /// fichiers disparus retires) sans toucher aux dossiers surveilles.
    void refreshWatchedFiles(qint64 folderId, const QStringList &knownRelativePaths);

    /// Delai de regroupement (debounce) avant l'emission de
    /// changesDetected(), en millisecondes. Une rafale d'evenements
    /// rapproches (ex: copie de plusieurs fichiers) ne declenche ainsi
    /// qu'un seul rescan. Valeur par defaut : 500 ms.
    void setDebounceInterval(int milliseconds);

signals:
    /// Un ou plusieurs changements ont ete detectes sur ce dossier depuis
    /// le dernier signal. Le destinataire (SyncEngine) doit rescanner
    /// integralement le dossier (via SharedFolderManager::shareFolder())
    /// pour savoir precisement ce qui a change.
    void changesDetected(qint64 folderId);

private:
    void scheduleNotification(qint64 folderId);
    void onDirectoryChanged(const QString &path);
    void onFileChanged(const QString &path);

    struct WatchedFolder {
        QString rootPath;
        QSet<QString> watchedDirectories;   // chemins absolus
        QSet<QString> watchedFilePaths;     // chemins absolus
    };

    QFileSystemWatcher *m_watcher;
    QHash<qint64, WatchedFolder> m_folders;
    QHash<QString, qint64> m_directoryToFolderId; // chemin absolu -> folderId
    QHash<QString, qint64> m_fileToFolderId;      // chemin absolu -> folderId
    QHash<qint64, QTimer *> m_debounceTimers;
    int m_debounceIntervalMs = 500;
};

} // namespace core::sync

#endif // CORE_SYNC_FOLDERWATCHER_H
