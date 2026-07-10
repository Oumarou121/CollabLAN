#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QHostAddress>
#include <QFile>
#include <QRandomGenerator>

#include "database/DatabaseManager.h"
#include "network/Transfer/TransferService.h"
#include "TransferManager.h"
#include "TransferContext.h"

/*
 * Issue #57 : "FileTransferView.qml - selection fichier + progression".
 *
 * Verifie la partie C++ (core::TransferContext) qui alimente la vue QML :
 * un transfert TCP reel (boucle locale) doit se traduire par des entrees
 * de activeTransfers() dont le pourcentage progresse de 0 a 100, ce qui
 * est le critere d'acceptation de l'issue ("L'utilisateur voit la
 * progression exacte d'un transfert en cours").
 */
class TestTransferContext : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dbDir;
    QTemporaryDir m_sourceDir;
    QTemporaryDir m_destDir;

private slots:
    void init()
    {
        QVERIFY(m_dbDir.isValid());
        QVERIFY(m_sourceDir.isValid());
        QVERIFY(m_destDir.isValid());
    }

    void sendFile_rejectsUnreadableFile()
    {
        database::DatabaseManager dbManager(
            QStringLiteral("test_transfercontext_unreadable_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(dbManager.open(m_dbDir.filePath(QStringLiteral("db1.sqlite"))));

        network::TransferService transferService;
        core::TransferManager manager(&dbManager);
        manager.setTransferService(&transferService);

        core::TransferContext context;
        context.setTransferManager(&manager);
        context.setTransferService(&transferService);

        QSignalSpy rejected(&context, &core::TransferContext::transferRejected);

        QVERIFY(!context.sendFile(m_sourceDir.filePath(QStringLiteral("does-not-exist.bin")),
                                   QStringLiteral("127.0.0.1")));
        QCOMPARE(rejected.count(), 1);
    }

    void sendFile_rejectsInvalidAddress()
    {
        database::DatabaseManager dbManager(
            QStringLiteral("test_transfercontext_badaddr_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(dbManager.open(m_dbDir.filePath(QStringLiteral("db2.sqlite"))));

        network::TransferService transferService;
        core::TransferManager manager(&dbManager);
        manager.setTransferService(&transferService);

        core::TransferContext context;
        context.setTransferManager(&manager);
        context.setTransferService(&transferService);

        const QString sourcePath = m_sourceDir.filePath(QStringLiteral("payload.bin"));
        QFile file(sourcePath);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(QByteArrayLiteral("hello"));
        file.close();

        QSignalSpy rejected(&context, &core::TransferContext::transferRejected);

        QVERIFY(!context.sendFile(sourcePath, QStringLiteral("not-an-address")));
        QCOMPARE(rejected.count(), 1);
    }

    void activeTransfers_tracksProgressToCompletion()
    {
        database::DatabaseManager dbManager(
            QStringLiteral("test_transfercontext_progress_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(dbManager.open(m_dbDir.filePath(QStringLiteral("db3.sqlite"))));

        network::TransferService transferService;
        transferService.setReceiveDirectory(m_destDir.path());
        QVERIFY(transferService.start(23480));

        core::TransferManager manager(&dbManager);
        manager.setTransferService(&transferService);

        core::TransferContext context;
        context.setTransferManager(&manager);
        context.setTransferService(&transferService);

        // Fichier assez gros pour generer plusieurs blocs (kBlockSize =
        // 64 Ko), donc plusieurs transferProgress() intermediaires plutot
        // qu'un seul saut direct de 0% a 100%.
        const QString sourcePath = m_sourceDir.filePath(QStringLiteral("big.bin"));
        {
            QFile file(sourcePath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            QByteArray chunk(64 * 1024, 'x');
            for (int i = 0; i < 3; ++i) {
                file.write(chunk);
            }
            file.close();
        }

        QSignalSpy activeTransfersChanged(&context, &core::TransferContext::activeTransfersChanged);
        QSignalSpy completed(&transferService, &network::TransferService::transferCompleted);

        QVERIFY(context.sendFile(sourcePath, QStringLiteral("127.0.0.1"), 23480));

        // Deux transferCompleted (expediteur + destinataire, meme
        // instance en boucle locale), comme dans test_transfermanager.
        QVERIFY(completed.wait(5000));
        if (completed.count() < 2) {
            QVERIFY(completed.wait(5000));
        }
        QCOMPARE(completed.count(), 2);

        QVERIFY(activeTransfersChanged.count() > 0);

        const QVariantList transfers = context.activeTransfers();
        QVERIFY(!transfers.isEmpty());

        bool foundCompleted = false;
        for (const auto &item : transfers) {
            const QVariantMap entry = item.toMap();
            if (entry.value(QStringLiteral("fileName")).toString() == QStringLiteral("big.bin")) {
                QCOMPARE(entry.value(QStringLiteral("statusText")).toString(), QStringLiteral("Termine"));
                QCOMPARE(entry.value(QStringLiteral("percent")).toInt(), 100);
                QCOMPARE(entry.value(QStringLiteral("bytesTransferred")).toLongLong(),
                         entry.value(QStringLiteral("totalBytes")).toLongLong());
                foundCompleted = true;
            }
        }
        QVERIFY(foundCompleted);

        transferService.stop();
        dbManager.close();
    }
};

QTEST_MAIN(TestTransferContext)
#include "test_transfercontext.moc"
