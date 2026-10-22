#include "SyncEngine.h"

#include "database/DatabaseManager.h"
#include <QDateTime>
#include <QDebug>
#include <QMetaObject>

namespace core::sync {

namespace {
// QVector<models::SharedFileChange> traverse une connexion inter-thread
// (SharedFolderIndexWorker::finished() est livre via une file d'attente
// automatique, le worker vivant sur un QThread distinct) : Qt a besoin
// que le type soit enregistre au meta-systeme pour pouvoir le copier dans
// la queue d'evenements. models::SharedFolder l'est deja implicitement
// via les connexions directes existantes (meme thread), mais jamais eu
// besoin d'etre enregistre au meta-type avant -- premiere connexion
// reellement inter-thread du projet.
void registerIndexWorkerMetaTypes()
{
    static const bool registered = [] {
        qRegisterMetaType<QVector<models::SharedFileChange>>("QVector<models::SharedFileChange>");
        return true;
    }();
    Q_UNUSED(registered);
}
}

SyncEngine::SyncEngine(core::SharedFolderManager *folderManager,
                        database::DatabaseManager *dbManager,
                        QString machineId,
                        QObject *parent)
    : QObject(parent)
    , m_folderManager(folderManager)
    , m_operationRepository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_accessRepository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_userRepository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_machineId(std::move(machineId))
{
    connect(&m_watcher, &FolderWatcher::changesDetected, this, &SyncEngine::onWatcherChangesDetected);

    if (m_folderManager) {
        connect(m_folderManager, &core::SharedFolderManager::folderCreated, this, &SyncEngine::onFolderCreated);
        connect(m_folderManager, &core::SharedFolderManager::folderRemoved, this, &SyncEngine::onFolderRemoved);
        connect(m_folderManager, &core::SharedFolderManager::folderLocalPathProvisioned,
                this, &SyncEngine::onFolderLocalPathProvisioned);
    }

    // Thread + worker d'indexation asynchrone (reindexFolderAsync()).
    // Cree meme si dbManager est nul (ex: certains tests) -- dans ce cas
    // le worker echouera simplement a ouvrir sa connexion et
    // reindexFolderAsync() rapportera l'echec via finished(ok=false),
    // sans jamais planter.
    registerIndexWorkerMetaTypes();
    const QString dbFilePath = dbManager ? dbManager->databaseFilePath() : QString();
    m_indexThread = new QThread(this);
    m_indexThread->setObjectName(QStringLiteral("SharedFolderIndexWorkerThread"));
    m_indexWorker = new SharedFolderIndexWorker(dbFilePath);
    m_indexWorker->moveToThread(m_indexThread);
    connect(m_indexThread, &QThread::finished, m_indexWorker, &QObject::deleteLater);
    connect(m_indexWorker, &SharedFolderIndexWorker::finished, this, &SyncEngine::onIndexWorkerFinished);
    m_indexThread->start();
}

SyncEngine::~SyncEngine()
{
    if (m_indexThread) {
        m_indexThread->quit();
        m_indexThread->wait();
    }
}

void SyncEngine::setLocalUserId(qint64 userId)
{
    m_localUserId = userId;
    // CORRECTIF : voir commentaire de setLocalUserId() dans SyncEngine.h --
    // un dossier replique (Write, pas isLocalOrigin()) evalue par start()
    // avant la fin du login restait sinon jamais surveille de la session.
    refreshWatchedFolders();
}

void SyncEngine::refreshWatchedFolders()
{
    if (!m_folderManager) {
        return;
    }
    for (const models::SharedFolder &folder : m_folderManager->getFolders()) {
        watchFolder(folder.id());
    }
}

void SyncEngine::suppressWatcherChanges(qint64 folderId, int durationMs)
{
    if (folderId <= 0)
        return;
    const qint64 until = QDateTime::currentMSecsSinceEpoch() + qMax(0, durationMs);
    m_ignoreWatcherUntilMs[folderId] = qMax(m_ignoreWatcherUntilMs.value(folderId), until);
}

bool SyncEngine::canWatchFolder(const models::SharedFolder &folder) const
{
    if (folder.localPath().isEmpty()) {
        return false;
    }
    // Proprietaire (origine locale) : toujours Write, meme sans
    // m_localUserId resolu (compte non encore connecte au demarrage).
    if (folder.isLocalOrigin()) {
        return true;
    }
    // Dossier replique : sans identifiant utilisateur local connu, on ne
    // peut pas confirmer la permission -- politique fail-closed ici
    // (contrairement a FolderSyncService::effectivePermission() qui est
    // fail-open pour un PAIR distant inconnu ; ici c'est NOUS qui
    // decidons de surveiller ou non NOTRE propre disque, une decision
    // locale qui n'a pas besoin d'etre permissive).
    if (m_localUserId < 0) {
        return false;
    }
    const auto permission = m_accessRepository.permissionFor(folder.id(), m_localUserId);
    return permission == models::SharedFolderPermission::Write;
}

void SyncEngine::start()
{
    if (!m_folderManager) {
        return;
    }
    for (const models::SharedFolder &folder : m_folderManager->getFolders()) {
        watchFolder(folder.id());
    }
}

void SyncEngine::watchFolder(qint64 folderId)
{
    if (!m_folderManager) {
        return;
    }
    const auto folder = m_folderManager->getFolder(folderId);
    if (!folder.has_value()) {
        return;
    }
    // Un dossier n'est surveille que s'il a un contenu local reel
    // (localPath non vide) ET si le poste local a la permission Write
    // dessus -- proprietaire (isLocalOrigin()) ou membre Write d'un
    // dossier replique (cf. canWatchFolder()). Un membre Read recoit les
    // mises a jour mais ne doit ni surveiller son disque, ni rediffuser
    // ses propres modifications (plan de synchronisation, points 1 et 3).
    if (!canWatchFolder(*folder)) {
        return;
    }

    QStringList relativePaths;
    for (const models::SharedFile &file : m_folderManager->getFiles(folderId)) {
        relativePaths.append(file.relativePath());
    }
    m_watcher.watchFolder(folderId, folder->localPath(), relativePaths);
}

void SyncEngine::onFolderCreated(const models::SharedFolder &folder)
{
    // Un dossier distant (replique depuis un autre poste, cf. migration 020
    // et SharedFolderManager::registerRemoteFolder()) n'a pas encore de
    // contenu reel sur CE disque au moment de sa creation : son local_path
    // est une chaine vide tant qu'il n'a pas ete provisionne (cf.
    // onFolderLocalPathProvisioned()). Tenter de le surveiller
    // (QFileSystemWatcher::addPath("")) produit l'avertissement Qt "Empty
    // filename passed to function" et ne sert a rien.
    if (!canWatchFolder(folder)) {
        return;
    }

    // CORRECTIF (bug "l'emetteur doit reindexer manuellement à chaque
    // modification, contrairement au destinataire") : ce cas (creation
    // LOCALE d'un dossier partage par son proprietaire, localPath deja
    // renseigne des l'appel) est le SEUL endroit ou canWatchFolder() peut
    // renvoyer true ici -- pour un dossier distant, localPath est vide et
    // canWatchFolder() a deja renvoye false ci-dessus (la surveillance
    // reelle demarrera plus tard, dans onFolderLocalPathProvisioned(), une
    // fois le contenu recu). watchFolder() DOIT donc etre appele ici avant
    // reindexFolder() : reindexFolder() n'appelle en interne que
    // m_watcher.refreshWatchedFiles(), qui est un no-op silencieux tant que
    // watchFolder() n'a pas d'abord enregistre la racine + les
    // sous-dossiers dans QFileSystemWatcher (cf. FolderWatcher::
    // refreshWatchedFiles(), qui retourne immediatement si m_folders ne
    // contient pas encore ce folderId). Sans cet appel, le dossier
    // nouvellement partage n'etait JAMAIS surveille : ses modifications
    // ulterieures passaient inapercues, obligeant un reindex manuel a
    // chaque fois -- alors que onFolderLocalPathProvisioned() (chemin
    // destinataire) appelle deja watchFolder() puis reindexFolder(), d'ou
    // l'asymetrie observee.
    watchFolder(folder.id());

    // Indexer le contenu initial du dossier pour que les fichiers soient
    // disponibles pour le resync (folder_resync_request)
    reindexFolder(folder.id());
}

void SyncEngine::onFolderLocalPathProvisioned(qint64 folderId, const QString &localPath)
{
    Q_UNUSED(localPath);
    if (!m_folderManager) {
        return;
    }
    const auto folder = m_folderManager->getFolder(folderId);
    if (!folder.has_value() || !canWatchFolder(*folder)) {
        // Dossier replique sans permission Write (membre Read) : ne pas
        // surveiller ni rediffuser -- les mises a jour continueront
        // d'arriver via le reseau et d'etre appliquees directement sur
        // disque sans passer par reindexFolder() (cf. plan, point 3).
        return;
    }
    // Contenu recu via provisionDefaultLocalPath()/setFolderLocalPath()
    // (pas via reindexFolder(), donc pas encore journalise localement) :
    // watchFolder() demarre la surveillance ; reindexFolder() journalise
    // l'etat initial pour un futur resync et rafraichit les fichiers
    // surveilles.
    watchFolder(folderId);
    reindexFolder(folderId);
}

void SyncEngine::onFolderRemoved(qint64 folderId)
{
    m_watcher.unwatchFolder(folderId);
}

void SyncEngine::onWatcherChangesDetected(qint64 folderId)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const qint64 until = m_ignoreWatcherUntilMs.value(folderId);
    if (now < until) {
        // Juste apres une integration distante : la notification vient le plus
        // souvent de notre propre ecriture, mais peut aussi couvrir une vraie
        // modification locale. On reindexe donc a la fin de la fenetre (les
        // fichiers integres, deja a jour en base, ne produisent alors rien).
        QTimer *timer = m_deferredReindex.value(folderId, nullptr);
        if (!timer) {
            timer = new QTimer(this);
            timer->setSingleShot(true);
            connect(timer, &QTimer::timeout, this, [this, folderId]() { requestReindex(folderId); });
            m_deferredReindex.insert(folderId, timer);
        }
        timer->start(static_cast<int>(until - now) + 50);
        return;
    }
    m_ignoreWatcherUntilMs.remove(folderId);
    requestReindex(folderId);
}

void SyncEngine::requestReindex(qint64 folderId)
{
    // Parcours + empreintes sur le fil d'indexation (auparavant sur le fil
    // principal : l'interface gelait a chaque changement d'un gros dossier).
    if (m_indexInFlight.contains(folderId)) {
        m_indexDirty.insert(folderId);
        return;
    }
    if (!m_indexWorker) {
        reindexFolder(folderId);
        return;
    }
    reindexFolderAsync(folderId);
}

int SyncEngine::reindexFolder(qint64 folderId)
{
    if (!m_folderManager) {
        return -1;
    }

    const auto folder = m_folderManager->getFolder(folderId);
    if (!folder.has_value()) {
        return -1;
    }

    // Un dossier distant (localPath vide) ne peut pas être réindexé
    // car il n'y a pas de contenu local à scanner. Un dossier répliqué
    // avec localPath mais sans permission Write (membre Read) ne doit
    // jamais journaliser/diffuser ses propres opérations -- ses mises à
    // jour arrivent uniquement via le réseau (cf. plan de synchronisation,
    // point 3).
    if (!canWatchFolder(*folder)) {
        qDebug() << "[SyncEngine] reindexFolder ignoré : pas de localPath ou pas de permission Write" << folder->name();
        return 0;
    }

    const auto changes = m_folderManager->shareFolder(folderId);
    if (!changes.has_value()) {
        return -1;
    }

    const int persistedCount = persistIndexChanges(folderId, *changes);
    emit folderReindexed(folderId, persistedCount);
    return persistedCount;
}

void SyncEngine::reindexFolderAsync(qint64 folderId)
{
    if (!m_folderManager || !m_indexWorker) {
        return;
    }

    const auto folder = m_folderManager->getFolder(folderId);
    if (!folder.has_value() || !canWatchFolder(*folder)) {
        // Memes conditions de garde que reindexFolder() : pas de contenu
        // local, ou membre Read seul -- rien a indexer/journaliser.
        qDebug() << "[SyncEngine] reindexFolderAsync ignoré : pas de localPath ou pas de permission Write";
        return;
    }

    m_indexInFlight.insert(folderId);
    emit reindexingStarted(folderId);
    // QueuedConnection implicite : m_indexWorker vit sur m_indexThread,
    // pas sur le thread appelant. L'appel retourne immediatement --
    // c'est tout le point de cette methode.
    QMetaObject::invokeMethod(m_indexWorker, "indexFolder", Qt::QueuedConnection, Q_ARG(qint64, folderId));
}

void SyncEngine::onIndexWorkerFinished(qint64 folderId, bool ok, QVector<models::SharedFileChange> changes,
                                        QString errorString)
{
    m_indexInFlight.remove(folderId);
    // Changements survenus pendant le parcours : un nouveau passage les prendra.
    if (m_indexDirty.remove(folderId))
        QTimer::singleShot(0, this, [this, folderId]() { requestReindex(folderId); });
    if (!ok) {
        qWarning() << "[SyncEngine] Indexation asynchrone échouée pour le dossier" << folderId << ":" << errorString;
        emit folderReindexed(folderId, -1);
        return;
    }

    // Le folderManager du thread UI (m_folderManager) n'a pas vu les
    // ecritures faites par le worker sur SA propre connexion SQLite --
    // rien a refaire ici cote lecture, SQLite persistant deja tout sur
    // disque des le COMMIT de l'upsert (chaque upsert() est sa propre
    // transaction implicite) : un getFiles()/getFolder() ulterieur sur la
    // connexion du thread UI relit donc bien l'etat a jour.
    const int persistedCount = persistIndexChanges(folderId, changes);
    emit folderReindexed(folderId, persistedCount);
}

int SyncEngine::persistIndexChanges(qint64 folderId, const QVector<models::SharedFileChange> &changes)
{
    int persistedCount = 0;
    for (const models::SharedFileChange &change : changes) {
        models::FileSyncOperation operation;
        operation.setType(change.type());
        operation.setFileId(change.file().id());
        operation.setOldRelativePath(change.oldRelativePath());
        operation.setVersion(change.file().version());
        operation.setMachineId(m_machineId);
        operation.setBaseHash(change.previousHash());
        if (m_localUserId > 0) {
            if (const auto author = m_userRepository.findById(static_cast<int>(m_localUserId)); author.has_value())
                operation.setAuthorUuid(author->uuid());
        }

        if (m_operationRepository.insert(operation).has_value()) {
            ++persistedCount;
        } else {
            qWarning() << "[SyncEngine] SyncOperations insert échoué pour" << change.file().relativePath()
                       << "-- erreur SQL:" << m_operationRepository.lastError();
        }
    }

    // Rafraichit la surveillance (nouveaux fichiers a surveiller pour
    // leurs futures modifications de contenu, fichiers disparus a ne
    // plus surveiller) ; watchFolder() est appele en filet de securite
    // si le dossier n'etait pas encore surveille (ex: tout premier
    // reindexFolder() suivant onFolderCreated()).
    if (const auto folder = m_folderManager->getFolder(folderId); folder.has_value()) {
        QStringList relativePaths;
        for (const models::SharedFile &file : m_folderManager->getFiles(folderId)) {
            relativePaths.append(file.relativePath());
        }
        m_watcher.refreshWatchedFiles(folderId, relativePaths);
    }

    return persistedCount;
}

QVector<models::FileSyncOperation> SyncEngine::historyForFolder(qint64 folderId, int limit) const
{
    return m_operationRepository.getByFolderId(folderId, limit);
}

} // namespace core::sync
