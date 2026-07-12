#include <QtTest>
#include <QDateTime>
#include <QRandomGenerator>
#include <QTemporaryDir>

#include "database/DatabaseManager.h"
#include "database/Repositories/SyncOperationRepository.h"
#include "database/Repositories/SharedFolderRepository.h"
#include "database/Repositories/SharedFileRepository.h"
#include "models/SharedFolder.h"
#include "models/SharedFile.h"
#include "models/FileSyncOperation.h"
#include "models/SyncChangeType.h"

/*
 * Tests unitaires de database::SyncOperationRepository (Release 3 -- doc de
 * conception : "journal de synchronisation"). On verifie :
 *   - insert()         : l'operation persistee a un id > 0 et ses champs sont conserves
 *   - getByFolderId()  : filtrage correct par dossier + jointure relativePath
 *   - getSinceId()     : pagination pour la reprise apres deconnexion (Release 7)
 *   - latestId()       : curseur de synchronisation
 */
class TestSyncOperationRepository : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;
    QString m_dbPath;

    // Helper : cree un SharedFile persiste et retourne son id.
    qint64 insertFile(database::SharedFileRepository &repo,
                      qint64 folderId, const QString &relativePath,
                      const QString &hash = QStringLiteral("abc123"))
    {
        models::SharedFile f;
        f.setFolderId(folderId);
        f.setRelativePath(relativePath);
        f.setHash(hash);
        f.setSize(100);
        // last_modified est NOT NULL dans SharedFiles ; on doit passer un
        // QDateTime valide sinon Qt QSQLITE lie NULL et la contrainte echoue.
        f.setLastModified(QDateTime::currentDateTimeUtc());
        const auto upserted = repo.upsert(f);
        return upserted.has_value() ? upserted->id() : -1;
    }

    // Helper : cree un SharedFolder persiste et retourne son id.
    qint64 insertFolder(database::SharedFolderRepository &repo,
                        const QString &name = QStringLiteral("Dossier"))
    {
        models::SharedFolder folder(0, name, QStringLiteral("/tmp/test"));
        folder.setIsActive(true);
        const auto inserted = repo.insert(folder);
        return inserted.has_value() ? inserted->id() : -1;
    }

private slots:
    void init()
    {
        QVERIFY(m_dir.isValid());
        m_dbPath = m_dir.filePath(
            QStringLiteral("syncop_%1.sqlite").arg(QRandomGenerator::global()->generate()));
    }

    void insertPersistsOperation()
    {
        database::DatabaseManager db(
            QStringLiteral("syncop_insert_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        database::SharedFolderRepository folderRepo(db.database());
        database::SharedFileRepository fileRepo(db.database());
        database::SyncOperationRepository syncRepo(db.database());

        const qint64 folderId = insertFolder(folderRepo);
        QVERIFY2(folderId > 0, qPrintable(folderRepo.lastError()));
        const qint64 fileId = insertFile(fileRepo, folderId, QStringLiteral("rapport.docx"));
        QVERIFY2(fileId > 0, qPrintable(fileRepo.lastError()));

        models::FileSyncOperation op;
        op.setType(models::SyncChangeType::Create);
        op.setFileId(fileId);
        op.setVersion(1);
        op.setMachineId(QStringLiteral("machine-alice"));

        const auto inserted = syncRepo.insert(op);
        QVERIFY(inserted.has_value());
        QVERIFY(inserted->id() > 0);
        QCOMPARE(inserted->type(), models::SyncChangeType::Create);
        QCOMPARE(inserted->fileId(), fileId);
        QCOMPARE(inserted->machineId(), QStringLiteral("machine-alice"));
    }

    void insertRenamePreservesOldPath()
    {
        database::DatabaseManager db(
            QStringLiteral("syncop_rename_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        database::SharedFolderRepository folderRepo(db.database());
        database::SharedFileRepository fileRepo(db.database());
        database::SyncOperationRepository syncRepo(db.database());

        const qint64 folderId = insertFolder(folderRepo);
        QVERIFY(folderId > 0);
        const qint64 fileId = insertFile(fileRepo, folderId, QStringLiteral("nouveau.docx"));
        QVERIFY(fileId > 0);

        models::FileSyncOperation op;
        op.setType(models::SyncChangeType::Rename);
        op.setFileId(fileId);
        op.setOldRelativePath(QStringLiteral("ancien.docx"));
        op.setVersion(2);
        op.setMachineId(QStringLiteral("machine-bob"));

        const auto inserted = syncRepo.insert(op);
        QVERIFY(inserted.has_value());
        QCOMPARE(inserted->type(), models::SyncChangeType::Rename);
        QCOMPARE(inserted->oldRelativePath(), QStringLiteral("ancien.docx"));
    }

    void getByFolderIdReturnsOnlyThatFolder()
    {
        database::DatabaseManager db(
            QStringLiteral("syncop_byfolder_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        database::SharedFolderRepository folderRepo(db.database());
        database::SharedFileRepository fileRepo(db.database());
        database::SyncOperationRepository syncRepo(db.database());

        const qint64 f1 = insertFolder(folderRepo, QStringLiteral("Dossier1"));
        const qint64 f2 = insertFolder(folderRepo, QStringLiteral("Dossier2"));
        QVERIFY(f1 > 0 && f2 > 0);

        const qint64 file1 = insertFile(fileRepo, f1, QStringLiteral("a.txt"));
        const qint64 file2 = insertFile(fileRepo, f2, QStringLiteral("b.txt"));
        QVERIFY(file1 > 0 && file2 > 0);

        auto makeOp = [](qint64 fileId) {
            models::FileSyncOperation op;
            op.setType(models::SyncChangeType::Create);
            op.setFileId(fileId);
            op.setVersion(1);
            op.setMachineId(QStringLiteral("m"));
            return op;
        };
        QVERIFY(syncRepo.insert(makeOp(file1)).has_value());
        QVERIFY(syncRepo.insert(makeOp(file1)).has_value()); // 2 ops sur f1
        QVERIFY(syncRepo.insert(makeOp(file2)).has_value()); // 1 op  sur f2

        const auto ops1 = syncRepo.getByFolderId(f1);
        const auto ops2 = syncRepo.getByFolderId(f2);
        QCOMPARE(ops1.size(), 2);
        QCOMPARE(ops2.size(), 1);
        // Jointure : relativePath doit etre renseigne
        QCOMPARE(ops1.at(0).relativePath(), QStringLiteral("a.txt"));
        QCOMPARE(ops2.at(0).relativePath(), QStringLiteral("b.txt"));
    }

    void getSinceIdReturnsPaginatedResults()
    {
        database::DatabaseManager db(
            QStringLiteral("syncop_sinceid_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        database::SharedFolderRepository folderRepo(db.database());
        database::SharedFileRepository fileRepo(db.database());
        database::SyncOperationRepository syncRepo(db.database());

        const qint64 folderId = insertFolder(folderRepo);
        QVERIFY(folderId > 0);
        const qint64 fileId = insertFile(fileRepo, folderId, QStringLiteral("f.txt"));
        QVERIFY(fileId > 0);

        auto makeOp = [&]() {
            models::FileSyncOperation op;
            op.setType(models::SyncChangeType::Update);
            op.setFileId(fileId);
            op.setVersion(1);
            op.setMachineId(QStringLiteral("m"));
            return op;
        };

        // Insere 4 operations et recupere l'id de la premiere
        const auto op1 = syncRepo.insert(makeOp());
        QVERIFY(op1.has_value());
        QVERIFY(syncRepo.insert(makeOp()).has_value());
        QVERIFY(syncRepo.insert(makeOp()).has_value());
        QVERIFY(syncRepo.insert(makeOp()).has_value());

        // getSinceId(op1->id()) doit retourner les 3 operations suivantes
        const auto since = syncRepo.getSinceId(op1->id());
        QCOMPARE(since.size(), 3);
        // Triees par id croissant
        QVERIFY(since.at(0).id() > op1->id());
        QVERIFY(since.at(1).id() > since.at(0).id());
        QVERIFY(since.at(2).id() > since.at(1).id());
    }

    void latestIdReturnsMaxId()
    {
        database::DatabaseManager db(
            QStringLiteral("syncop_latestid_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(db.open(m_dbPath));

        database::SharedFolderRepository folderRepo(db.database());
        database::SharedFileRepository fileRepo(db.database());
        database::SyncOperationRepository syncRepo(db.database());

        // Sur une base vide : 0
        QCOMPARE(syncRepo.latestId(), qint64(0));

        const qint64 folderId = insertFolder(folderRepo);
        QVERIFY(folderId > 0);
        const qint64 fileId = insertFile(fileRepo, folderId, QStringLiteral("f.txt"));
        QVERIFY(fileId > 0);

        auto makeOp = [&]() {
            models::FileSyncOperation op;
            op.setType(models::SyncChangeType::Create);
            op.setFileId(fileId);
            op.setVersion(1);
            op.setMachineId(QStringLiteral("m"));
            return op;
        };

        const auto first  = syncRepo.insert(makeOp());
        const auto second = syncRepo.insert(makeOp());
        QVERIFY(first.has_value() && second.has_value());

        QCOMPARE(syncRepo.latestId(), second->id());
    }
};

QTEST_MAIN(TestSyncOperationRepository)
#include "test_syncoperationrepository.moc"
