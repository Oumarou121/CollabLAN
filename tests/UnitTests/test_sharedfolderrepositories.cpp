#include <QtTest>
#include <QRandomGenerator>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QTemporaryDir>

#include "Repositories/SharedFileRepository.h"
#include "Repositories/SharedFolderRepository.h"
#include "Repositories/SyncOperationRepository.h"

// Ces tests ouvrent directement une base SQLite temporaire et y appliquent
// le schema de la migration 003 a la main (plutot que de passer par
// DatabaseManager::open(), dont la recherche de fichiers de migration est
// connue pour echouer dans certains environnements de build -- cf.
// replit.md). Cela permet de valider les repositories du "Shared Folder"
// independamment de ce probleme, deja documente separement.
class TestSharedFolderRepositories : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_tempDir;
    QString m_connectionName;

    QSqlDatabase openSchema()
    {
        m_connectionName = QStringLiteral("test_sharedfolder_%1").arg(QRandomGenerator::global()->generate());
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), m_connectionName);
        db.setDatabaseName(m_tempDir.filePath(QStringLiteral("test_%1.sqlite").arg(QRandomGenerator::global()->generate())));
        if (!db.open()) {
            return db;
        }

        QSqlQuery query(db);
        query.exec(QStringLiteral("PRAGMA foreign_keys = ON"));
        query.exec(QStringLiteral(
            "CREATE TABLE Users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)"));
        query.exec(QStringLiteral("INSERT INTO Users (id, name) VALUES (1, 'admin')"));

        query.exec(QStringLiteral(
            "CREATE TABLE SharedFolders ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT,"
            "name TEXT NOT NULL,"
            "local_path TEXT NOT NULL,"
            "owner_id INTEGER NOT NULL REFERENCES Users(id),"
            "created_at TEXT NOT NULL DEFAULT (datetime('now')),"
            "is_active INTEGER NOT NULL DEFAULT 1)"));

        query.exec(QStringLiteral(
            "CREATE TABLE SharedFiles ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT,"
            "folder_id INTEGER NOT NULL REFERENCES SharedFolders(id),"
            "relative_path TEXT NOT NULL,"
            "hash TEXT NOT NULL DEFAULT '',"
            "size INTEGER NOT NULL DEFAULT 0,"
            "last_modified TEXT NOT NULL DEFAULT (datetime('now')),"
            "version INTEGER NOT NULL DEFAULT 1,"
            "deleted INTEGER NOT NULL DEFAULT 0)"));
        query.exec(QStringLiteral(
            "CREATE UNIQUE INDEX idx_sharedfiles_folder_path ON SharedFiles(folder_id, relative_path)"));

        query.exec(QStringLiteral(
            "CREATE TABLE SyncOperations ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT,"
            "type TEXT NOT NULL,"
            "file_id INTEGER NOT NULL REFERENCES SharedFiles(id),"
            "version INTEGER NOT NULL,"
            "machine_id TEXT NOT NULL,"
            "created_at TEXT NOT NULL DEFAULT (datetime('now')))"));

        return db;
    }

private slots:
    void cleanup()
    {
        if (!m_connectionName.isEmpty()) {
            QSqlDatabase::removeDatabase(m_connectionName);
            m_connectionName.clear();
        }
    }

    void folderRepositoryCrudRoundTrips()
    {
        QSqlDatabase db = openSchema();
        QVERIFY(db.isOpen());
        database::SharedFolderRepository repo(db);

        models::SharedFolder folder;
        folder.setName(QStringLiteral("Projet"));
        folder.setLocalPath(QStringLiteral("/tmp/projet"));
        folder.setOwnerId(1);

        const int id = repo.create(folder);
        QVERIFY2(id >= 0, qPrintable(repo.lastError()));

        auto fetched = repo.findById(id);
        QVERIFY(fetched.has_value());
        QCOMPARE(fetched->name(), QStringLiteral("Projet"));
        QVERIFY(fetched->isActive());
        QVERIFY(repo.existsByLocalPath(QStringLiteral("/tmp/projet")));

        fetched->setIsActive(false);
        QVERIFY(repo.update(*fetched));
        QCOMPARE(repo.findActive().size(), size_t(0));
        QCOMPARE(repo.findAll().size(), size_t(1));

        QVERIFY(repo.remove(id));
        QVERIFY(!repo.findById(id).has_value());
    }

    void fileRepositoryTracksVersionsAndDeletion()
    {
        QSqlDatabase db = openSchema();
        QVERIFY(db.isOpen());
        database::SharedFolderRepository folderRepo(db);
        database::SharedFileRepository fileRepo(db);

        models::SharedFolder folder;
        folder.setName(QStringLiteral("Projet"));
        folder.setLocalPath(QStringLiteral("/tmp/projet"));
        folder.setOwnerId(1);
        const int folderId = folderRepo.create(folder);
        QVERIFY(folderId >= 0);

        models::SharedFile file;
        file.setFolderId(folderId);
        file.setRelativePath(QStringLiteral("Docs/rapport.docx"));
        file.setHash(QStringLiteral("abc123"));
        file.setSize(4096);
        file.setVersion(1);

        const int fileId = fileRepo.create(file);
        QVERIFY2(fileId >= 0, qPrintable(fileRepo.lastError()));
        QCOMPARE(fileRepo.countActiveByFolder(folderId), 1);

        auto fetched = fileRepo.findByFolderAndPath(folderId, QStringLiteral("Docs/rapport.docx"));
        QVERIFY(fetched.has_value());
        fetched->setVersion(2);
        fetched->setHash(QStringLiteral("def456"));
        QVERIFY(fileRepo.update(*fetched));

        auto updated = fileRepo.findById(fileId);
        QVERIFY(updated.has_value());
        QCOMPARE(updated->version(), 2);

        updated->setDeleted(true);
        QVERIFY(fileRepo.update(*updated));
        QCOMPARE(fileRepo.countActiveByFolder(folderId), 0);
        QCOMPARE(fileRepo.findByFolder(folderId, /*includeDeleted=*/false).size(), size_t(0));
        QCOMPARE(fileRepo.findByFolder(folderId, /*includeDeleted=*/true).size(), size_t(1));
    }

    void syncOperationRepositoryRecordsHistory()
    {
        QSqlDatabase db = openSchema();
        QVERIFY(db.isOpen());
        database::SharedFolderRepository folderRepo(db);
        database::SharedFileRepository fileRepo(db);
        database::SyncOperationRepository operationRepo(db);

        models::SharedFolder folder;
        folder.setName(QStringLiteral("Projet"));
        folder.setLocalPath(QStringLiteral("/tmp/projet"));
        folder.setOwnerId(1);
        const int folderId = folderRepo.create(folder);
        QVERIFY2(folderId >= 0, qPrintable(folderRepo.lastError()));

        models::SharedFile file;
        file.setFolderId(folderId);
        file.setRelativePath(QStringLiteral("a.txt"));
        file.setVersion(1);
        const int fileId = fileRepo.create(file);
        QVERIFY2(fileId >= 0, qPrintable(fileRepo.lastError()));

        models::SyncOperation createOp;
        createOp.setFileId(fileId);
        createOp.setType(models::SyncOperationType::Create);
        createOp.setVersion(1);
        createOp.setMachineId(QStringLiteral("machine-a"));
        QVERIFY(operationRepo.create(createOp) >= 0);

        models::SyncOperation updateOp;
        updateOp.setFileId(fileId);
        updateOp.setType(models::SyncOperationType::Update);
        updateOp.setVersion(2);
        updateOp.setMachineId(QStringLiteral("machine-b"));
        QVERIFY(operationRepo.create(updateOp) >= 0);

        const auto history = operationRepo.findByFile(fileId);
        QCOMPARE(history.size(), size_t(2));
        QCOMPARE(history.front().type(), models::SyncOperationType::Create);
        QCOMPARE(history.back().type(), models::SyncOperationType::Update);

        const auto recent = operationRepo.findRecentByFolder(folderId, 10);
        QCOMPARE(recent.size(), size_t(2));
    }
};

QTEST_MAIN(TestSharedFolderRepositories)
#include "test_sharedfolderrepositories.moc"
