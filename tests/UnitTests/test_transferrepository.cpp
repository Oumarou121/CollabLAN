#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "database/DatabaseManager.h"
#include "database/Repositories/TransferRepository.h"
#include "database/Repositories/UserRepository.h"

class TestTransferRepository : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_tempDir;
    database::DatabaseManager *m_dbManager = nullptr;
    int m_senderId = -1;
    int m_recipientId = -1;

    models::Transfer makeTransfer(const QString &fileName, qint64 size) const
    {
        models::Transfer transfer;
        transfer.setSenderId(m_senderId);
        transfer.setRecipientId(m_recipientId);
        transfer.setFileName(fileName);
        transfer.setFileSize(size);
        transfer.setStatus(models::TransferStatus::Pending);
        return transfer;
    }

private slots:
    void init()
    {
        QVERIFY(m_tempDir.isValid());
        const QString dbPath = m_tempDir.filePath(
            QStringLiteral("test_%1.sqlite").arg(QRandomGenerator::global()->generate()));
        m_dbManager = new database::DatabaseManager(
            QStringLiteral("test_transferrepo_connection_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(m_dbManager->open(dbPath));

        database::UserRepository userRepo(m_dbManager->database());
        models::User sender;
        sender.setName(QStringLiteral("sender"));
        sender.setPasswordHash(QStringLiteral("hash"));
        sender.setPasswordSalt(QStringLiteral("salt"));
        m_senderId = userRepo.create(sender);
        QVERIFY(m_senderId >= 0);

        models::User recipient;
        recipient.setName(QStringLiteral("recipient"));
        recipient.setPasswordHash(QStringLiteral("hash"));
        recipient.setPasswordSalt(QStringLiteral("salt"));
        m_recipientId = userRepo.create(recipient);
        QVERIFY(m_recipientId >= 0);
    }

    void cleanup()
    {
        delete m_dbManager;
        m_dbManager = nullptr;
    }

    void testCreateReturnsGeneratedIdWithPendingStatus()
    {
        database::TransferRepository repo(m_dbManager->database());

        const int id = repo.create(makeTransfer(QStringLiteral("rapport.pdf"), 123456));
        QVERIFY(id >= 0);

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QCOMPARE(found->fileName(), QStringLiteral("rapport.pdf"));
        QCOMPARE(found->fileSize(), static_cast<qint64>(123456));
        QCOMPARE(found->status(), models::TransferStatus::Pending);
        QCOMPARE(found->senderId(), m_senderId);
        QCOMPARE(found->recipientId(), m_recipientId);
    }

    void testFindByIdMissingReturnsNullopt()
    {
        database::TransferRepository repo(m_dbManager->database());
        QVERIFY(!repo.findById(9999).has_value());
    }

    void testUpdateStatusPersists()
    {
        database::TransferRepository repo(m_dbManager->database());
        const int id = repo.create(makeTransfer(QStringLiteral("video.mp4"), 999));
        QVERIFY(id >= 0);

        QVERIFY(repo.updateStatus(id, models::TransferStatus::Completed));

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QCOMPARE(found->status(), models::TransferStatus::Completed);
    }

    void testFindByUserReturnsSenderAndRecipientTransfers()
    {
        database::TransferRepository repo(m_dbManager->database());
        QVERIFY(repo.create(makeTransfer(QStringLiteral("a.txt"), 10)) >= 0);
        QVERIFY(repo.create(makeTransfer(QStringLiteral("b.txt"), 20)) >= 0);

        const auto senderTransfers = repo.findByUser(m_senderId);
        QCOMPARE(static_cast<int>(senderTransfers.size()), 2);

        const auto recipientTransfers = repo.findByUser(m_recipientId);
        QCOMPARE(static_cast<int>(recipientTransfers.size()), 2);
    }

    void testRemoveDeletesTransfer()
    {
        database::TransferRepository repo(m_dbManager->database());
        const int id = repo.create(makeTransfer(QStringLiteral("c.txt"), 30));
        QVERIFY(id >= 0);

        QVERIFY(repo.remove(id));
        QVERIFY(!repo.findById(id).has_value());
    }
};

QTEST_MAIN(TestTransferRepository)
#include "test_transferrepository.moc"
