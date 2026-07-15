#include <QtTest>
#include <QDateTime>
#include <QFile>
#include <QDir>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QRandomGenerator>
#include <QTemporaryDir>

#include "database/DatabaseManager.h"
#include "database/Repositories/SharedFileRepository.h"
#include "SharedFolderManager.h"

/*
 * Tests unitaires de core::SharedFolderManager (Release 2 -- doc de conception).
 * On verifie :
 *   - createFolder (chemin valide, chemin invalide)
 *   - shareFolder  (Create, Update, Delete, Rename detectes correctement)
 *   - removeFolder
 *
 * Aucun reseau implique : tout est local/SQLite, a la maniere des autres
 * tests de la base de code (test_messagingmanager, test_groupmanager...).
 *
 * Isolation : chaque test ouvre une base SQLite fraiche (nouvelle connexion,
 * nouveau fichier) et un nouveau QTemporaryDir independant pour les fichiers.
 * PRAGMA foreign_keys = ON est active par DatabaseManager ; on passe donc
 * ownerId = 0 (NULL en base) pour eviter une violation de cle etrangere vers
 * Users, qui est vide dans ces tests.
 */
class TestSharedFolderManager : public QObject
{
    Q_OBJECT

private:
    // m_dbDir est partage entre les tests pour conserver les fichiers SQLite
    // crees par chaque test (chacun a son propre fichier aleatoire dans ce
    // repertoire). Le repertoire des fichiers surveilles (m_folderDir) est
    // recree a chaque test via init() pour eviter toute contamination entre
    // tests (les fichiers restes d'un test precedent fausseraient les comptes
    // de changements).
    QTemporaryDir m_dbDir;
    std::unique_ptr<QTemporaryDir> m_folderDir;
    std::unique_ptr<QTemporaryDir> m_sharedFoldersBaseDir;
    QString m_dbPath;

private slots:
    void init()
    {
        QVERIFY(m_dbDir.isValid());
        m_dbPath = m_dbDir.filePath(
            QStringLiteral("sfm_%1.sqlite").arg(QRandomGenerator::global()->generate()));
        // Nouveau repertoire propre pour les fichiers de ce test
        m_folderDir = std::make_unique<QTemporaryDir>();
        QVERIFY(m_folderDir->isValid());
        // Nouveau repertoire isole pour previewDefaultLocalPath()/
        // provisionDefaultLocalPath() (cf. sharedFoldersBaseDirForTest()) :
        // jamais le vrai Documents/ de la machine.
        m_sharedFoldersBaseDir = std::make_unique<QTemporaryDir>();
        QVERIFY(m_sharedFoldersBaseDir->isValid());
    }

    // ------------------------------------------------------------------ helpers
    database::DatabaseManager *openDb(const QString &connectionName)
    {
        auto *db = new database::DatabaseManager(connectionName);
        if (!db->open(m_dbPath)) {
            delete db;
            return nullptr;
        }
        return db;
    }

    QString writeFile(const QString &relativePath, const QByteArray &content)
    {
        const QString absPath = m_folderDir->filePath(relativePath);
        QDir().mkpath(QFileInfo(absPath).absolutePath());
        QFile f(absPath);
        if (!f.open(QIODevice::WriteOnly))
            return {};
        f.write(content);
        return absPath;
    }

    // Insere une ligne minimale dans Users pour un id donne : necessaire
    // pour les tests qui exercent SharedFolderAccess.user_id, seule colonne
    // de ce module contrainte par une vraie FK NOT NULL vers Users (cf.
    // migration 022). Les autres tests de cette suite n'ont pas besoin de
    // Users car ownerId est passe a 0 (NULL en base, cf. commentaire en
    // tete de fichier) -- seul grantAccess() reference un user_id reel.
    bool insertStubUser(database::DatabaseManager *db, qint64 userId)
    {
        QSqlQuery query(db->database());
        query.prepare(QStringLiteral(
            "INSERT INTO Users (id, name) VALUES (:id, :name)"));
        query.bindValue(QStringLiteral(":id"), userId);
        query.bindValue(QStringLiteral(":name"), QStringLiteral("stub_user_%1").arg(userId));
        return query.exec();
    }

    // ------------------------------------------------------------------ tests
    void createFolderWithValidPath()
    {
        auto *db = openDb(QStringLiteral("sfm_create_valid_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        // ownerId = 0 -> NULL en base (SharedFolderRepository le mappe ainsi).
        // On evite ainsi une violation de FK vers Users (table vide).
        const auto folder = mgr.createFolder(QStringLiteral("MonDossier"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));
        QCOMPARE(folder->name(), QStringLiteral("MonDossier"));
        QVERIFY(folder->id() > 0);

        db->close();
        delete db;
    }

    void createFolderFailsOnMissingPath()
    {
        auto *db = openDb(QStringLiteral("sfm_create_missing_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        const auto folder = mgr.createFolder(QStringLiteral("X"), QStringLiteral("/inexistant/path/xyz"), 0);
        QVERIFY(!folder.has_value());
        QCOMPARE(mgr.lastError(), core::SharedFolderManagerError::InvalidPath);

        db->close();
        delete db;
    }

    void createFolderFailsOnEmptyName()
    {
        auto *db = openDb(QStringLiteral("sfm_create_emptyname_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        const auto folder = mgr.createFolder(QStringLiteral("   "), m_folderDir->path(), 0);
        QVERIFY(!folder.has_value());
        QCOMPARE(mgr.lastError(), core::SharedFolderManagerError::InvalidName);

        db->close();
        delete db;
    }

    void shareFolderDetectsNewFiles()
    {
        auto *db = openDb(QStringLiteral("sfm_create_new_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        // Ecrit deux fichiers avant de creer/partager le dossier
        writeFile(QStringLiteral("a.txt"), QByteArrayLiteral("hello"));
        writeFile(QStringLiteral("sub/b.txt"), QByteArrayLiteral("world"));

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        const auto changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(changes->size(), 2);

        for (const auto &ch : *changes) {
            QCOMPARE(ch.type(), models::SyncChangeType::Create);
        }

        db->close();
        delete db;
    }

    void shareFolderDetectsModifiedFile()
    {
        auto *db = openDb(QStringLiteral("sfm_update_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        writeFile(QStringLiteral("note.txt"), QByteArrayLiteral("version1"));

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        // Premier scan : Create
        auto changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(changes->size(), 1);
        QCOMPARE(changes->at(0).type(), models::SyncChangeType::Create);

        // Modifie le fichier, rescan : Update
        writeFile(QStringLiteral("note.txt"), QByteArrayLiteral("version2_different_content"));
        changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(changes->size(), 1);
        QCOMPARE(changes->at(0).type(), models::SyncChangeType::Update);

        db->close();
        delete db;
    }

    void shareFolderDetectsDeletedFile()
    {
        auto *db = openDb(QStringLiteral("sfm_delete_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        const QString absPath = writeFile(QStringLiteral("todelete.txt"), QByteArrayLiteral("bye"));
        QVERIFY(!absPath.isEmpty());

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        auto changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(changes->size(), 1);
        QCOMPARE(changes->at(0).type(), models::SyncChangeType::Create);

        // Supprime le fichier
        QVERIFY(QFile::remove(absPath));

        changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(changes->size(), 1);
        QCOMPARE(changes->at(0).type(), models::SyncChangeType::Delete);

        db->close();
        delete db;
    }

    // Regression : bug "tout le contenu est supprime au partage". Une
    // ligne SharedFiles encore a l'etat pending_download=true (placeholder
    // pose par FolderSyncService::registerCatchupPlaceholder() lors d'un
    // rattrapage, avant que le contenu reel n'ait ete telecharge) ne doit
    // JAMAIS etre tombstonee par shareFolder() simplement parce qu'elle
    // est absente du disque local -- son absence signifie "pas encore
    // recue", pas "supprimee". Avant correctif, ce cas produisait un
    // Delete diffuse a tous les pairs, qui l'appliquaient reellement et
    // supprimaient le fichier partout, y compris chez son proprietaire.
    void shareFolderIgnoresPendingDownloadPlaceholders()
    {
        auto *db = openDb(QStringLiteral("sfm_pending_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        // Simule registerCatchupPlaceholder() : une ligne "creuse" (taille
        // 0, pending_download=true) pour un fichier connu du reseau mais
        // dont le contenu n'a pas encore ete telecharge sur ce poste --
        // le dossier local est encore vide a ce stade.
        database::SharedFileRepository fileRepo(db->database());
        models::SharedFile placeholder(0, folder->id(), QStringLiteral("pas_encore_recu.txt"));
        placeholder.setHash(QStringLiteral("deadbeef"));
        placeholder.setVersion(1);
        placeholder.setDeleted(false);
        placeholder.setPendingDownload(true);
        // Indispensable : un QDateTime par defaut est invalide, et
        // QDateTime::toString() sur une date invalide renvoie une QString
        // NULLE -- que SharedFileRepository::upsert() lie alors comme NULL
        // SQL, ce qui viole la contrainte NOT NULL de last_modified et fait
        // echouer l'INSERT (cf. commentaire de registerCatchupPlaceholder(),
        // qui applique deja ce correctif en production).
        placeholder.setLastModified(QDateTime::currentDateTimeUtc());
        QVERIFY2(fileRepo.upsert(placeholder).has_value(), qPrintable(fileRepo.lastError()));

        // reindex sur le dossier local, physiquement vide : le placeholder
        // ne doit generer AUCUN changement (surtout pas un Delete), et ne
        // doit pas etre tombstone en base.
        const auto changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(changes->size(), 0);

        const auto stillKnown = fileRepo.findByRelativePath(folder->id(), QStringLiteral("pas_encore_recu.txt"));
        QVERIFY(stillKnown.has_value());
        QVERIFY(!stillKnown->deleted());
        QVERIFY(stillKnown->pendingDownload());

        db->close();
        delete db;
    }

    void shareFolderDetectsRename()
    {
        auto *db = openDb(QStringLiteral("sfm_rename_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        const QString oldAbs = writeFile(QStringLiteral("ancien.txt"), QByteArrayLiteral("same content"));
        QVERIFY(!oldAbs.isEmpty());

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        auto changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(changes->size(), 1);
        QCOMPARE(changes->at(0).type(), models::SyncChangeType::Create);

        // Renomme le fichier (meme contenu -> hash identique -> detecte comme Rename)
        const QString newAbs = m_folderDir->filePath(QStringLiteral("nouveau.txt"));
        QVERIFY(QFile::rename(oldAbs, newAbs));

        changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(changes->size(), 1);
        QCOMPARE(changes->at(0).type(), models::SyncChangeType::Rename);
        QCOMPARE(changes->at(0).oldRelativePath(), QStringLiteral("ancien.txt"));
        QCOMPARE(changes->at(0).file().relativePath(), QStringLiteral("nouveau.txt"));

        db->close();
        delete db;
    }

    void removeFolderDeletesRecord()
    {
        auto *db = openDb(QStringLiteral("sfm_remove_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        const auto folder = mgr.createFolder(QStringLiteral("ToRemove"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));
        QVERIFY(mgr.removeFolder(folder->id()));

        const auto fetched = mgr.getFolder(folder->id());
        QVERIFY(!fetched.has_value());

        db->close();
        delete db;
    }

    void getFilesReturnsIndexedFiles()
    {
        auto *db = openDb(QStringLiteral("sfm_getfiles_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        writeFile(QStringLiteral("x.txt"), QByteArrayLiteral("x"));
        writeFile(QStringLiteral("y.txt"), QByteArrayLiteral("y"));

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        mgr.shareFolder(folder->id());

        const auto files = mgr.getFiles(folder->id());
        QCOMPARE(files.size(), 2);

        db->close();
        delete db;
    }

    // ------------------------------------------------------------------
    // Release 9 (partielle) : fichiers techniques/temporaires exclus de
    // l'indexation (et donc de toute synchronisation reseau).
    // ------------------------------------------------------------------
    void shareFolderExcludesTechnicalAndTemporaryFiles()
    {
        auto *db = openDb(QStringLiteral("sfm_exclude_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        // Fichier legitime : doit etre indexe.
        writeFile(QStringLiteral("rapport.docx"), QByteArrayLiteral("contenu"));

        // Fichiers/dossiers a exclure.
        writeFile(QStringLiteral("scratch.tmp"), QByteArrayLiteral("temp"));
        writeFile(QStringLiteral("build/output.obj"), QByteArrayLiteral("obj"));
        writeFile(QStringLiteral("~$rapport.docx"), QByteArrayLiteral("lock office"));
        writeFile(QStringLiteral(".~lock.rapport.docx#"), QByteArrayLiteral("lock libreoffice"));
        writeFile(QStringLiteral(".git/HEAD"), QByteArrayLiteral("ref: refs/heads/main"));
        writeFile(QStringLiteral("Thumbs.db"), QByteArrayLiteral("thumb"));
        writeFile(QStringLiteral(".DS_Store"), QByteArrayLiteral("ds"));

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        const auto changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());

        // Seul rapport.docx doit avoir ete indexe.
        QCOMPARE(changes->size(), 1);
        QCOMPARE(changes->at(0).file().relativePath(), QStringLiteral("rapport.docx"));

        const auto files = mgr.getFiles(folder->id());
        QCOMPARE(files.size(), 1);
        QCOMPARE(files.at(0).relativePath(), QStringLiteral("rapport.docx"));

        db->close();
        delete db;
    }

    // -------------------------------------------------- exclude patterns (debrief #4)

    void createFolderAppliesUserExcludePatterns()
    {
        auto *db = openDb(QStringLiteral("sfm_userexclude_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        writeFile(QStringLiteral("rapport.docx"), QByteArrayLiteral("contenu"));
        writeFile(QStringLiteral("notes.log"), QByteArrayLiteral("log"));
        writeFile(QStringLiteral("drafts/idee.txt"), QByteArrayLiteral("draft"));
        writeFile(QStringLiteral("node_modules/pkg/index.js"), QByteArrayLiteral("js"));

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0, {},
                                              models::SharedFolderPermission::Write,
                                              QStringLiteral("*.log, node_modules, drafts/*"));
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));
        // Normalise (retrim + rejoint par ", ") par validateExcludePatterns().
        QCOMPARE(folder->excludePatterns(), QStringLiteral("*.log, node_modules, drafts/*"));

        const auto changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(changes->size(), 1);
        QCOMPARE(changes->at(0).file().relativePath(), QStringLiteral("rapport.docx"));

        const auto files = mgr.getFiles(folder->id());
        QCOMPARE(files.size(), 1);
        QCOMPARE(files.at(0).relativePath(), QStringLiteral("rapport.docx"));

        db->close();
        delete db;
    }

    void createFolderRejectsInvalidExcludePattern()
    {
        auto *db = openDb(QStringLiteral("sfm_badexclude_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        // Un crochet non ferme rend l'expression reguliere generee invalide.
        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0, {},
                                              models::SharedFolderPermission::Write,
                                              QStringLiteral("[abc"));
        QVERIFY(!folder.has_value());
        QCOMPARE(mgr.lastError(), core::SharedFolderManagerError::InvalidExcludePatterns);

        db->close();
        delete db;
    }

    void updateExcludePatternsTombstonesMatchingFilesOnNextShare()
    {
        auto *db = openDb(QStringLiteral("sfm_updateexclude_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        writeFile(QStringLiteral("rapport.docx"), QByteArrayLiteral("contenu"));
        writeFile(QStringLiteral("notes.log"), QByteArrayLiteral("log"));

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        // Pas encore de motif : les deux fichiers sont indexes.
        auto changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(mgr.getFiles(folder->id()).size(), 2);

        // On exclut desormais les .log -- n'affecte QUE la prochaine
        // indexation, cf. commentaire updateExcludePatterns().
        QVERIFY2(mgr.updateExcludePatterns(folder->id(), QStringLiteral("*.log")),
                  qPrintable(mgr.lastErrorString()));
        QCOMPARE(mgr.getFiles(folder->id()).size(), 2); // pas encore retroactif

        changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        const auto files = mgr.getFiles(folder->id());
        QCOMPARE(files.size(), 1);
        QCOMPARE(files.at(0).relativePath(), QStringLiteral("rapport.docx"));

        db->close();
        delete db;
    }

    void previewExcludePatternsImpactListsAlreadyIndexedMatches()
    {
        auto *db = openDb(QStringLiteral("sfm_previewexclude_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        writeFile(QStringLiteral("rapport.docx"), QByteArrayLiteral("contenu"));
        writeFile(QStringLiteral("notes.txt"), QByteArrayLiteral("notes"));
        writeFile(QStringLiteral("drafts/idee.txt"), QByteArrayLiteral("draft"));

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        const auto changes = mgr.shareFolder(folder->id());
        QVERIFY(changes.has_value());
        QCOMPARE(mgr.getFiles(folder->id()).size(), 3);

        // Un motif candidat pas encore enregistre ("*.txt") doit remonter
        // les fichiers DEJA indexes qui deviendraient exclus, SANS rien
        // ecrire en base (aucun appel a updateExcludePatterns()/shareFolder()
        // apres coup dans ce test).
        QStringList impacted = mgr.previewExcludePatternsImpact(folder->id(), QStringLiteral("*.txt"));
        impacted.sort();
        QCOMPARE(impacted, QStringList({QStringLiteral("drafts/idee.txt"), QStringLiteral("notes.txt")}));

        // Le dossier n'a pas ete modifie : toujours 3 fichiers indexes.
        QCOMPARE(mgr.getFiles(folder->id()).size(), 3);
        // Et le motif enregistre en base n'a pas change.
        const auto reloaded = mgr.getFolder(folder->id());
        QVERIFY(reloaded.has_value());
        QVERIFY(reloaded->excludePatterns().isEmpty());

        db->close();
        delete db;
    }

    void previewExcludePatternsImpactIsEmptyWhenNoMatchOrInvalidPattern()
    {
        auto *db = openDb(QStringLiteral("sfm_previewexclude2_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        writeFile(QStringLiteral("rapport.docx"), QByteArrayLiteral("contenu"));

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));
        QVERIFY(mgr.shareFolder(folder->id()).has_value());

        // Aucun motif ne correspond a rapport.docx.
        QVERIFY(mgr.previewExcludePatternsImpact(folder->id(), QStringLiteral("*.log")).isEmpty());

        // Motif malforme (crochet non ferme) : liste vide plutot qu'un crash
        // ou une exception -- la vraie erreur de validation n'apparait qu'a
        // l'enregistrement reel (updateExcludePatterns()).
        QVERIFY(mgr.previewExcludePatternsImpact(folder->id(), QStringLiteral("[abc")).isEmpty());

        // Dossier introuvable : liste vide, pas de crash.
        QVERIFY(mgr.previewExcludePatternsImpact(folder->id() + 999, QStringLiteral("*.docx")).isEmpty());

        db->close();
        delete db;
    }

    void isPathExcludedReflectsHardcodedAndUserPatterns()
    {
        auto *db = openDb(QStringLiteral("sfm_ispathexcluded_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0, {},
                                              models::SharedFolderPermission::Write,
                                              QStringLiteral("*.log, node_modules"));
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        // Motif utilisateur (segment de dossier).
        QVERIFY(mgr.isPathExcluded(folder->id(), QStringLiteral("node_modules/pkg/index.js")));
        // Motif utilisateur (extension).
        QVERIFY(mgr.isPathExcluded(folder->id(), QStringLiteral("notes.log")));
        // Aucun motif ne correspond.
        QVERIFY(!mgr.isPathExcluded(folder->id(), QStringLiteral("rapport.docx")));
        // Dossier introuvable : pas d'exclusion applicable (pas de crash).
        QVERIFY(!mgr.isPathExcluded(folder->id() + 999, QStringLiteral("rapport.docx")));

        db->close();
        delete db;
    }

    // -------------------------------------------------- auto-provisioning du chemin local (dossiers distants)

    // QStandardPaths::setTestModeOn() n'est pas disponible sur toutes les
    // configurations Qt/MSVC (echec de compilation constate avec Qt 6.11.1
    // MSVC2022 -- "n'est pas membre de QStandardPaths"). On utilise donc
    // SharedFolderManager::setSharedFoldersBaseDirOverrideForTests() pour
    // rediriger ces tests vers un QTemporaryDir isole, plutot que d'operer
    // (et de removeRecursively()!) sur le vrai Documents/CollabLAN Shared
    // Folders/ de la machine -- une precedente version de ces tests faisait
    // exactement ca et effacait les vrais dossiers/fichiers partages de
    // l'utilisateur a chaque execution de ctest. Le sous-dossier
    // "CollabLAN Shared Folders" est conserve dans le chemin pour que les
    // assertions QVERIFY(path->contains(...)) restent valides.
    QString sharedFoldersBaseDirForTest()
    {
        return m_sharedFoldersBaseDir->path() + QStringLiteral("/CollabLAN Shared Folders");
    }

    void provisionDefaultLocalPathCreatesDirectoryUnderDocuments()
    {
        auto *db = openDb(QStringLiteral("sfm_autopath_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);
        mgr.setSharedFoldersBaseDirOverrideForTests(sharedFoldersBaseDirForTest());

        const auto folder = mgr.registerRemoteFolder(
            QStringLiteral("uuid-autopath-1"), QStringLiteral("Projet"), 0, QStringLiteral("machine-distante"));
        QVERIFY(folder.has_value());
        QVERIFY(folder->localPath().isEmpty());

        const auto path = mgr.provisionDefaultLocalPath(folder->id());
        QVERIFY2(path.has_value(), qPrintable(mgr.lastErrorString()));
        QVERIFY(path->contains(QStringLiteral("CollabLAN Shared Folders")));
        QVERIFY(path->contains(QStringLiteral("Projet")));
        QVERIFY(QDir(*path).exists());

        const auto reloaded = mgr.getFolder(folder->id());
        QVERIFY(reloaded.has_value());
        QCOMPARE(reloaded->localPath(), *path);

        // Idempotent : un second appel ne change rien et renvoie le meme chemin.
        const auto second = mgr.provisionDefaultLocalPath(folder->id());
        QVERIFY(second.has_value());
        QCOMPARE(*second, *path);

        db->close();
        delete db;
    }

    void provisionDefaultLocalPathDisambiguatesNameCollisions()
    {
        auto *db = openDb(QStringLiteral("sfm_autopath_collision_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);
        mgr.setSharedFoldersBaseDirOverrideForTests(sharedFoldersBaseDirForTest());

        // Deux dossiers LOGIQUEMENT distincts (uuid different) partagés par
        // deux pairs différents mais portant le même nom "Projet".
        const auto folderA = mgr.registerRemoteFolder(
            QStringLiteral("uuid-collision-a"), QStringLiteral("Projet"), 0, QStringLiteral("machine-a"));
        const auto folderB = mgr.registerRemoteFolder(
            QStringLiteral("uuid-collision-b"), QStringLiteral("Projet"), 0, QStringLiteral("machine-b"));
        QVERIFY(folderA.has_value());
        QVERIFY(folderB.has_value());

        const auto pathA = mgr.provisionDefaultLocalPath(folderA->id());
        const auto pathB = mgr.provisionDefaultLocalPath(folderB->id());
        QVERIFY2(pathA.has_value(), qPrintable(mgr.lastErrorString()));
        QVERIFY2(pathB.has_value(), qPrintable(mgr.lastErrorString()));

        QVERIFY(*pathA != *pathB);
        QVERIFY(pathB->contains(QStringLiteral("Projet (2)")));
        QVERIFY(QDir(*pathA).exists());
        QVERIFY(QDir(*pathB).exists());

        db->close();
        delete db;
    }

    void provisionDefaultLocalPathSkipsLocalOriginFolders()
    {
        auto *db = openDb(QStringLiteral("sfm_autopath_local_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        // Un dossier créé localement a déjà un localPath (choisi à la
        // création) : provisionDefaultLocalPath() doit être un no-op qui
        // renvoie simplement ce chemin existant, jamais en écraser le
        // choix explicite de l'utilisateur.
        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        const auto path = mgr.provisionDefaultLocalPath(folder->id());
        QVERIFY(path.has_value());
        QCOMPARE(*path, m_folderDir->path());

        db->close();
        delete db;
    }

    void previewDefaultLocalPathHasNoSideEffects()
    {
        auto *db = openDb(QStringLiteral("sfm_preview_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);
        mgr.setSharedFoldersBaseDirOverrideForTests(sharedFoldersBaseDirForTest());

        const auto folder = mgr.registerRemoteFolder(
            QStringLiteral("uuid-preview-1"), QStringLiteral("Projet"), 0, QStringLiteral("machine-distante"));
        QVERIFY(folder.has_value());

        // previewDefaultLocalPath() doit renvoyer le meme chemin que
        // provisionDefaultLocalPath() aurait choisi, mais SANS creer le
        // dossier sur le disque ni toucher a la base : le dialogue de
        // confirmation de partage doit pouvoir etre ouvert/ferme plusieurs
        // fois sans laisser de dossiers vides orphelins.
        const auto preview = mgr.previewDefaultLocalPath(folder->id());
        QVERIFY(preview.has_value());
        QVERIFY(preview->contains(QStringLiteral("CollabLAN Shared Folders")));
        QVERIFY(preview->contains(QStringLiteral("Projet")));
        QVERIFY(!QDir(*preview).exists());

        const auto reloaded = mgr.getFolder(folder->id());
        QVERIFY(reloaded.has_value());
        QVERIFY(reloaded->localPath().isEmpty());

        // Appeler previewDefaultLocalPath() plusieurs fois de suite reste
        // stable (pas de desambiguisation "(2)", "(3)"... qui s'incrementerait
        // a chaque appel puisque rien n'est jamais reserve/cree).
        const auto secondPreview = mgr.previewDefaultLocalPath(folder->id());
        QVERIFY(secondPreview.has_value());
        QCOMPARE(*secondPreview, *preview);

        // provisionDefaultLocalPath() (l'acceptation reelle par l'utilisateur)
        // doit ensuite choisir exactement ce meme chemin previsualise.
        const auto provisioned = mgr.provisionDefaultLocalPath(folder->id());
        QVERIFY2(provisioned.has_value(), qPrintable(mgr.lastErrorString()));
        QCOMPARE(*provisioned, *preview);
        QVERIFY(QDir(*provisioned).exists());

        db->close();
        delete db;
    }

    void previewDefaultLocalPathSkipsLocalOriginFolders()
    {
        auto *db = openDb(QStringLiteral("sfm_preview_local_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        const auto preview = mgr.previewDefaultLocalPath(folder->id());
        QVERIFY(preview.has_value());
        QCOMPARE(*preview, m_folderDir->path());

        db->close();
        delete db;
    }

    void grantAccessMarksOnlyFirstGrantAsNew()
    {
        auto *db = openDb(QStringLiteral("sfm_grant_isnew_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db);
        core::SharedFolderManager mgr(db);

        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        // grantAccess() ecrit reellement user_id = 42 dans SharedFolderAccess,
        // dont la FK (migration 022) exige une ligne Users correspondante --
        // contrairement a ownerId (passe a 0/NULL ailleurs dans cette suite),
        // ce champ est ici exerce avec un id concret et doit donc exister.
        QVERIFY(insertStubUser(db, 42));

        QVector<bool> emittedIsNew;
        QObject::connect(&mgr, &core::SharedFolderManager::accessGrantedLocal,
                          [&emittedIsNew](qint64, qint64, bool isNew) { emittedIsNew.append(isNew); });

        // Premier grant (utilisateur 42, jamais vu sur ce dossier) : nouveau.
        QVERIFY(mgr.grantAccess(folder->id(), 42, 0, models::SharedFolderPermission::Read, false));
        // Ré-application idempotente du meme grant (ex: handleFolderAccessGranted()
        // rejoue le catchup a la reconnexion) : PAS nouveau, ne doit pas redeclencher
        // notification/dialogue cote appelant.
        QVERIFY(mgr.grantAccess(folder->id(), 42, 0, models::SharedFolderPermission::Read, false));
        // Un changement de permission reste tout de meme une re-application
        // de la MEME paire (folder, user) : toujours pas "nouveau" au sens
        // de ce test (l'acces existait deja).
        QVERIFY(mgr.grantAccess(folder->id(), 42, 0, models::SharedFolderPermission::Write, false));

        QCoreApplication::processEvents(); // les emit() passent par Qt::QueuedConnection

        QCOMPARE(emittedIsNew.size(), 3);
        QCOMPARE(emittedIsNew.at(0), true);
        QCOMPARE(emittedIsNew.at(1), false);
        QCOMPARE(emittedIsNew.at(2), false);

        db->close();
        delete db;
    }
};

QTEST_MAIN(TestSharedFolderManager)
#include "test_sharedfoldermanager.moc"