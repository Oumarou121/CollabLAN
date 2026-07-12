#include <QtTest>
#include <QFile>
#include <QDir>
#include <QRandomGenerator>
#include <QTemporaryDir>

#include "database/DatabaseManager.h"
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
};

QTEST_MAIN(TestSharedFolderManager)
#include "test_sharedfoldermanager.moc"
