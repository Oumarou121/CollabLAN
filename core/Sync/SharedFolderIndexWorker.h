#ifndef CORE_SYNC_SHAREDFOLDERINDEXWORKER_H
#define CORE_SYNC_SHAREDFOLDERINDEXWORKER_H

#include <QObject>
#include <QString>
#include <QVector>
#include <memory>

#include "core/SharedFolderManager.h"
#include "database/DatabaseManager.h"
#include "models/SharedFileChange.h"

namespace core::sync {

/**
 * @brief Execute SharedFolderManager::shareFolder() (parcours recursif +
 * hash SHA-256 + upserts SQLite) sur un QThread dedie, pour ne plus jamais
 * bloquer la boucle d'evenements Qt du thread UI pendant l'indexation
 * (cf. debrief perf : "l'app ne repond plus" sur un poste peu performant
 * lors du partage d'un dossier).
 *
 * Cette instance possede SA PROPRE connexion SQLite (nom de connexion
 * unique, cf. database::DatabaseManager) ouverte sur le MEME fichier que
 * la connexion "principale" du thread UI : les connexions Qt SQL ne sont
 * pas partageables entre threads, donc reutiliser le DatabaseManager du
 * thread UI depuis ce worker provoquerait des acces concurrents non
 * proteges sur le meme QSqlDatabase. Chaque connexion SQLite obtient son
 * propre verrou de fichier via SQLite (mode par defaut, pas de WAL
 * necessaire ici : les ecritures restent courtes et sequentielles).
 *
 * Cycle de vie : cree par SyncEngine, deplace (moveToThread) vers un
 * QThread qu'il possede, et vit jusqu'a la destruction de SyncEngine.
 * La connexion SQLite (m_dbManager) est ouverte paresseusement au premier
 * indexFolder() traite -- QSqlDatabase::addDatabase()/open() doivent etre
 * appeles depuis le thread qui utilisera la connexion, donc pas dans le
 * constructeur (execute sur le thread UI avant le moveToThread()).
 */
class SharedFolderIndexWorker : public QObject
{
    Q_OBJECT

public:
    /// dbFilePath : chemin du fichier SQLite principal (cf.
    /// DatabaseManager::databaseFilePath()) sur lequel ouvrir la
    /// connexion dediee de ce worker.
    explicit SharedFolderIndexWorker(QString dbFilePath, QObject *parent = nullptr);
    ~SharedFolderIndexWorker() override;

public slots:
    /// Effectue l'indexation (SharedFolderManager::shareFolder()) pour
    /// folderId sur SA propre connexion SQLite, puis emet finished().
    /// A invoquer uniquement via QMetaObject::invokeMethod(..., Qt::
    /// QueuedConnection) depuis le thread UI (jamais d'appel direct) --
    /// c'est ce qui garantit l'execution sur le thread de ce worker.
    void indexFolder(qint64 folderId);

signals:
    /// ok=false si l'indexation a echoue (dossier introuvable, chemin
    /// disparu, connexion SQLite du worker non disponible...) --
    /// errorString donne alors le detail (cf. SharedFolderManager::
    /// lastErrorString()). changes est vide (mais ok=true) si le dossier
    /// n'a pas change depuis la derniere indexation.
    void finished(qint64 folderId, bool ok, QVector<models::SharedFileChange> changes, QString errorString);

private:
    bool ensureDatabaseOpen();

    QString m_dbFilePath;
    std::unique_ptr<database::DatabaseManager> m_dbManager;
    std::unique_ptr<core::SharedFolderManager> m_folderManager;
};

} // namespace core::sync

#endif // CORE_SYNC_SHAREDFOLDERINDEXWORKER_H
