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
    QString m_senderUuid;
    QString m_recipientUuid;

    models::Transfer makeTransfer(const QString &fileName, qint64 size) const
    {
        models::Transfer transfer;
        transfer.setSenderUuid(m_senderUuid);
        transfer.setRecipientUuid(m_recipientUuid);
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
        const int senderId = userRepo.create(sender);
        QVERIFY(senderId >= 0);
        m_senderUuid = userRepo.findById(senderId)->uuid();
        QVERIFY(!m_senderUuid.isEmpty());

        models::User recipient;
        recipient.setName(QStringLiteral("recipient"));
        recipient.setPasswordHash(QStringLiteral("hash"));
        recipient.setPasswordSalt(QStringLiteral("salt"));
        const int recipientId = userRepo.create(recipient);
        QVERIFY(recipientId >= 0);
        m_recipientUuid = userRepo.findById(recipientId)->uuid();
        QVERIFY(!m_recipientUuid.isEmpty());
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
        QCOMPARE(found->senderUuid(), m_senderUuid);
        QCOMPARE(found->recipientUuid(), m_recipientUuid);
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

        const auto senderTransfers = repo.findByUser(m_senderUuid);
        QCOMPARE(static_cast<int>(senderTransfers.size()), 2);

        const auto recipientTransfers = repo.findByUser(m_recipientUuid);
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

    void testCreateWithUnknownUserUuidsPersists()
    {
        // Migration #017 : un transfert vers/depuis un poste LAN sans
        // compte utilisateur associe (uuid inconnu, chaine vide) doit
        // pouvoir etre enregistre sans contrainte de cle etrangere
        // (c'etait le bug empechant tout historique reseau, migration #012).
        database::TransferRepository repo(m_dbManager->database());
        models::Transfer transfer;
        transfer.setFileName(QStringLiteral("depuis-le-lan.bin"));
        transfer.setFileSize(42);
        transfer.setStatus(models::TransferStatus::Completed);

        const int id = repo.create(transfer);
        QVERIFY2(id >= 0, qPrintable(repo.lastError()));

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QVERIFY(found->senderUuid().isEmpty());
        QVERIFY(found->recipientUuid().isEmpty());
    }

    void testUpdateFilePathPersists()
    {
        database::TransferRepository repo(m_dbManager->database());
        const int id = repo.create(makeTransfer(QStringLiteral("d.txt"), 40));
        QVERIFY(id >= 0);
        QVERIFY(repo.findById(id)->filePath().isEmpty());

        QVERIFY(repo.updateFilePath(id, QStringLiteral("/tmp/localink/d.txt")));

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QCOMPARE(found->filePath(), QStringLiteral("/tmp/localink/d.txt"));
    }

    void testCreatePersistsPeerAddressAndName()
    {
        // Migration #015 : permet de regrouper l'historique par
        // correspondant, independamment de tout compte utilisateur local.
        database::TransferRepository repo(m_dbManager->database());
        models::Transfer transfer = makeTransfer(QStringLiteral("photo.jpg"), 2048);
        transfer.setPeerAddress(QStringLiteral("192.168.1.50"));
        transfer.setPeerName(QStringLiteral("poste-cuisine"));

        const int id = repo.create(transfer);
        QVERIFY2(id >= 0, qPrintable(repo.lastError()));

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QCOMPARE(found->peerAddress(), QStringLiteral("192.168.1.50"));
        QCOMPARE(found->peerName(), QStringLiteral("poste-cuisine"));
    }

    void testCreateWithoutPeerInfoPersistsEmpty()
    {
        // Transferts enregistres avant la migration #015 (ou dont le
        // correspondant n'a pas pu etre resolu) : peer_address/peer_name
        // doivent rester vides plutot que provoquer un echec d'insertion.
        database::TransferRepository repo(m_dbManager->database());
        const int id = repo.create(makeTransfer(QStringLiteral("sans-pair.txt"), 5));
        QVERIFY2(id >= 0, qPrintable(repo.lastError()));

        const auto found = repo.findById(id);
        QVERIFY(found.has_value());
        QVERIFY(found->peerAddress().isEmpty());
        QVERIFY(found->peerName().isEmpty());
    }

    void testFindByUserGroupableByPeerAddress()
    {
        // Verifie que plusieurs transferts vers le meme correspondant
        // partagent bien la meme peer_address, condition necessaire au
        // regroupement cote UI (FileTransferView.qml::buildPeerGroups()).
        database::TransferRepository repo(m_dbManager->database());
        models::Transfer first = makeTransfer(QStringLiteral("un.txt"), 1);
        first.setPeerAddress(QStringLiteral("10.0.0.9"));
        first.setPeerName(QStringLiteral("laptop-marie"));
        QVERIFY(repo.create(first) >= 0);

        models::Transfer second = makeTransfer(QStringLiteral("deux.txt"), 2);
        second.setPeerAddress(QStringLiteral("10.0.0.9"));
        second.setPeerName(QStringLiteral("laptop-marie"));
        QVERIFY(repo.create(second) >= 0);

        const auto transfers = repo.findByUser(m_senderUuid);
        QCOMPARE(static_cast<int>(transfers.size()), 2);
        for (const auto &t : transfers) {
            QCOMPARE(t.peerAddress(), QStringLiteral("10.0.0.9"));
        }
    }
};

QTEST_MAIN(TestTransferRepository)
#include "test_transferrepository.moc"
