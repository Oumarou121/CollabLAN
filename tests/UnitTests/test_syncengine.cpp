#include <QtTest>
#include <QSignalSpy>
#include <QFile>
#include <QDir>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "database/DatabaseManager.h"
#include "database/Repositories/SyncOperationRepository.h"
#include "SharedFolderManager.h"
#include "core/Sync/SyncEngine.h"
#include "models/SyncChangeType.h"

/*
 * Tests d'integration de core::sync::SyncEngine (Release 2/3 -- doc de
 * conception).
 *
 * On verifie le chemin complet :
 *   SharedFolderManager (indexation locale)
 *   → SyncEngine::reindexFolder()
 *   → SyncOperationRepository (journal persiste)
 *   → signal folderReindexed (compte de changements)
 *
 * Aucun reseau implique.  FolderWatcher n'est pas teste ici (cf.
 * test_folderwatcher.cpp) ; seul reindexFolder() est appele directement.
 *
 * Isolation : chaque test ouvre une base SQLite fraiche (fichier unique dans
 * m_dbDir) et un nouveau QTemporaryDir pour les fichiers surveilles.  Cela
 * empeche les fichiers laisses par un test precedent de fausser les comptes
 * de changements du test suivant.
 * PRAGMA foreign_keys = ON est active par DatabaseManager ; on passe donc
 * ownerId = 0 (NULL) pour eviter une violation de FK vers Users (table vide).
 */
class TestSyncEngine : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dbDir;
    // m_folderDir est recrée dans init() pour chaque test.
    std::unique_ptr<QTemporaryDir> m_folderDir;
    QString m_dbPath;

    bool writeFile(const QString &relativePath, const QByteArray &content)
    {
        const QString abs = m_folderDir->filePath(relativePath);
        QDir().mkpath(QFileInfo(abs).absolutePath());
        QFile f(abs);
        if (!f.open(QIODevice::WriteOnly))
            return false;
        f.write(content);
        return true;
    }

private slots:
    void init()
    {
        QVERIFY(m_dbDir.isValid());
        m_dbPath = m_dbDir.filePath(
            QStringLiteral("se_%1.sqlite").arg(QRandomGenerator::global()->generate()));
        // Nouveau repertoire propre pour ce test ; evite que les fichiers
        // du test precedent ne soient comptabilises comme des changements.
        m_folderDir = std::make_unique<QTemporaryDir>();
        QVERIFY(m_folderDir->isValid());
    }

    // reindexFolder() retourne 0 si aucun changement depuis la derniere indexation.
    void reindexReturnZeroWhenNoChange()
    {
        database::DatabaseManager db(
            QStringLiteral("se_nochange_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        writeFile(QStringLiteral("stable.txt"), QByteArrayLiteral("contenu stable"));

        core::SharedFolderManager mgr(&db);
        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        core::sync::SyncEngine engine(&mgr, &db, QStringLiteral("machine-test"));

        // Premier scan : 1 Create
        const int first = engine.reindexFolder(folder->id());
        QCOMPARE(first, 1);

        // Deuxieme scan sans changement : 0
        const int second = engine.reindexFolder(folder->id());
        QCOMPARE(second, 0);
    }

    // reindexFolder() journalise un Create pour chaque nouveau fichier.
    void reindexJournalsCreateOperations()
    {
        database::DatabaseManager db(
            QStringLiteral("se_create_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        writeFile(QStringLiteral("a.txt"), QByteArrayLiteral("alpha"));
        writeFile(QStringLiteral("b.txt"), QByteArrayLiteral("beta"));

        core::SharedFolderManager mgr(&db);
        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        core::sync::SyncEngine engine(&mgr, &db, QStringLiteral("machine-test"));
        const int count = engine.reindexFolder(folder->id());
        QCOMPARE(count, 2);

        // Verifie que les operations sont bien en base
        database::SyncOperationRepository repo(db.database());
        const auto ops = repo.getByFolderId(folder->id());
        QCOMPARE(ops.size(), 2);
        for (const auto &op : ops) {
            QCOMPARE(op.type(), models::SyncChangeType::Create);
            QCOMPARE(op.machineId(), QStringLiteral("machine-test"));
            QVERIFY(!op.relativePath().isEmpty());
        }
    }

    // reindexFolder() journalise un Update apres modification d'un fichier.
    void reindexJournalsUpdateOperation()
    {
        database::DatabaseManager db(
            QStringLiteral("se_update_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        QVERIFY(writeFile(QStringLiteral("note.txt"), QByteArrayLiteral("v1")));

        core::SharedFolderManager mgr(&db);
        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        core::sync::SyncEngine engine(&mgr, &db, QStringLiteral("machine-test"));
        QCOMPARE(engine.reindexFolder(folder->id()), 1); // Create

        QVERIFY(writeFile(QStringLiteral("note.txt"), QByteArrayLiteral("v2_different")));
        QCOMPARE(engine.reindexFolder(folder->id()), 1); // Update

        database::SyncOperationRepository repo(db.database());
        const auto ops = repo.getByFolderId(folder->id(), 10);
        // 2 operations au total (Create + Update), la plus recente en premier
        QCOMPARE(ops.size(), 2);
        QCOMPARE(ops.at(0).type(), models::SyncChangeType::Update);
        QCOMPARE(ops.at(1).type(), models::SyncChangeType::Create);
    }

    // reindexFolder() journalise un Delete quand un fichier disparait.
    void reindexJournalsDeleteOperation()
    {
        database::DatabaseManager db(
            QStringLiteral("se_delete_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        const QString absPath = m_folderDir->filePath(QStringLiteral("bye.txt"));
        QVERIFY(writeFile(QStringLiteral("bye.txt"), QByteArrayLiteral("farewell")));

        core::SharedFolderManager mgr(&db);
        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        core::sync::SyncEngine engine(&mgr, &db, QStringLiteral("machine-test"));
        QCOMPARE(engine.reindexFolder(folder->id()), 1); // Create

        QVERIFY(QFile::remove(absPath));
        QCOMPARE(engine.reindexFolder(folder->id()), 1); // Delete

        database::SyncOperationRepository repo(db.database());
        const auto ops = repo.getByFolderId(folder->id(), 10);
        QCOMPARE(ops.size(), 2);
        QCOMPARE(ops.at(0).type(), models::SyncChangeType::Delete);
    }

    // folderReindexed est emis avec le bon compte de changements.
    void folderReindexedSignalIsEmittedWithCorrectCount()
    {
        database::DatabaseManager db(
            QStringLiteral("se_signal_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        QVERIFY(writeFile(QStringLiteral("sig1.txt"), QByteArrayLiteral("a")));
        QVERIFY(writeFile(QStringLiteral("sig2.txt"), QByteArrayLiteral("b")));

        core::SharedFolderManager mgr(&db);
        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        core::sync::SyncEngine engine(&mgr, &db, QStringLiteral("machine-test"));

        QSignalSpy spy(&engine, &core::sync::SyncEngine::folderReindexed);
        engine.reindexFolder(folder->id());

        QCOMPARE(spy.count(), 1);
        const QList<QVariant> args = spy.takeFirst();
        QCOMPARE(args.at(0).toLongLong(), folder->id());
        QCOMPARE(args.at(1).toInt(), 2); // 2 fichiers crees

        // Deuxieme reindex sans changement : signal toujours emis, count = 0
        engine.reindexFolder(folder->id());
        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.takeFirst().at(1).toInt(), 0);
    }

    // historyForFolder() retourne les operations persistees, les plus recentes
    // en premier.
    void historyForFolderReturnsOperationsLatestFirst()
    {
        database::DatabaseManager db(
            QStringLiteral("se_history_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        QVERIFY(writeFile(QStringLiteral("h.txt"), QByteArrayLiteral("v1")));

        core::SharedFolderManager mgr(&db);
        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        core::sync::SyncEngine engine(&mgr, &db, QStringLiteral("machine-test"));
        engine.reindexFolder(folder->id()); // Create

        QVERIFY(writeFile(QStringLiteral("h.txt"), QByteArrayLiteral("v2_different")));
        engine.reindexFolder(folder->id()); // Update

        const auto history = engine.historyForFolder(folder->id(), 10);
        QCOMPARE(history.size(), 2);
        QCOMPARE(history.at(0).type(), models::SyncChangeType::Update);
        QCOMPARE(history.at(1).type(), models::SyncChangeType::Create);
    }

    // start() ne plante pas meme avec des dossiers deja enregistres.
    void startWatchesPreviouslyKnownFolders()
    {
        database::DatabaseManager db(
            QStringLiteral("se_start_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        core::SharedFolderManager mgr(&db);
        const auto folder = mgr.createFolder(QStringLiteral("F"), m_folderDir->path(), 0);
        QVERIFY2(folder.has_value(), qPrintable(mgr.lastErrorString()));

        core::sync::SyncEngine engine(&mgr, &db, QStringLiteral("machine-test"));
        engine.start(); // ne doit pas planter
    }
};

QTEST_MAIN(TestSyncEngine)
#include "test_syncengine.moc"
