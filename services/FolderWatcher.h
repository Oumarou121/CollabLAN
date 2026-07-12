#ifndef SERVICES_FOLDERWATCHER_H
#define SERVICES_FOLDERWATCHER_H

#include <QDateTime>
#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QString>

namespace services {

/**
 * @brief Surveille un dossier (et ses sous-dossiers) sur le disque et
 * emet des evenements de changement (Phase 3 de "Shared Folder").
 *
 * S'appuie sur QFileSystemWatcher, qui ne notifie qu'au niveau
 * repertoire (un fichier cree/supprime/renomme dans un dossier surveille
 * declenche directoryChanged() sur ce dossier, pas un signal par
 * fichier). FolderWatcher se charge donc de :
 *  - surveiller recursivement tous les sous-dossiers existants ;
 *  - a chaque directoryChanged(), comparer l'etat courant du dossier a
 *    l'etat precedent (cache interne) pour en deduire quels fichiers ont
 *    ete crees / modifies / supprimes, et quels sous-dossiers sont
 *    apparus (et les surveiller a leur tour).
 *
 * FolderWatcher n'effectue aucun transfert ni aucune ecriture en base :
 * il ne fait qu'emettre des evenements, consommes par core::SyncEngine.
 *
 * Limite connue (assumee pour cette premiere version, cf. spec Phase 9
 * "plus tard tu pourras faire mieux") : un renommage est detecte comme
 * une suppression suivie d'une creation, faute de distinction native
 * dans QFileSystemWatcher entre "supprime" et "renomme".
 */
class FolderWatcher : public QObject {
    Q_OBJECT

public:
    explicit FolderWatcher(QObject *parent = nullptr);
    ~FolderWatcher() override;

    // Demarre la surveillance de rootPath (chemin absolu). Fait un scan
    // initial silencieux (aucun signal emis pour les fichiers deja
    // presents) puis surveille tous les changements ulterieurs.
    bool watch(const QString &rootPath);

    void unwatch();

    QString rootPath() const;
    bool isWatching() const;

signals:
    // relativePath est toujours relatif a rootPath (separateurs '/').
    void fileCreated(const QString &relativePath);
    void fileChanged(const QString &relativePath);
    void fileDeleted(const QString &relativePath);
    void directoryCreated(const QString &relativePath);

private slots:
    void onDirectoryChanged(const QString &path);

private:
    struct FileState {
        qint64 size = 0;
        QDateTime lastModified;
    };

    void watchDirectoryRecursive(const QString &absoluteDirPath, bool emitSignals);
    void scanDirectory(const QString &absoluteDirPath, bool emitSignals);
    QString toRelativePath(const QString &absolutePath) const;

    QFileSystemWatcher *m_watcher = nullptr;
    QString m_rootPath;
    QHash<QString, FileState> m_knownFiles; // cle = chemin relatif
};

} // namespace services

#endif // SERVICES_FOLDERWATCHER_H
