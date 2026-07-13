#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QHostAddress>
#include <QFile>
#include <QFileInfo>
#include <QRandomGenerator>
#include <memory>

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
                QCOMPARE(entry.value(QStringLiteral("statusText")).toString(), QStringLiteral("Terminé"));
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

    // ------------------------------------------------------------------
    // Release 9 — chunking + curseur de reprise : un envoi interrompu par
    // la disparition du pair distant (le destinataire, pas l'expediteur --
    // c'est l'expediteur/context qui reste vivant tout le test, comme
    // dans l'application reelle) doit pouvoir etre relance manuellement
    // via retryTransfer(), et reprendre exactement ou il s'est arrete
    // (meme mecanisme de reprise par octet que network::TransferService,
    // voir test_transferresumeintegration.cpp pour la couche protocole).
    // ------------------------------------------------------------------
    void retryTransfer_resumesFailedOutgoingTransferAfterPeerReturns()
    {
        database::DatabaseManager dbManager(
            QStringLiteral("test_transfercontext_retry_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(dbManager.open(m_dbDir.filePath(QStringLiteral("db4.sqlite"))));

        // L'expediteur (service + manager + context) reste vivant tout le
        // test : seul le destinataire disparait puis revient, exactement
        // comme le vivrait l'application reelle (le pair distant se
        // deconnecte, pas nous).
        network::TransferService senderService;
        core::TransferManager manager(&dbManager);
        manager.setTransferService(&senderService);

        core::TransferContext context;
        context.setTransferManager(&manager);
        context.setTransferService(&senderService);

        const quint16 receiverPort = 23481;

        const QString sourcePath = m_sourceDir.filePath(QStringLiteral("resume.bin"));
        const qint64 fileSize = 2 * 1024 * 1024 + 123; // plusieurs blocs, taille non alignee
        QByteArray original;
        original.resize(static_cast<int>(fileSize));
        QRandomGenerator::global()->fillRange(reinterpret_cast<quint32*>(original.data()),
                                               static_cast<qsizetype>(original.size() / sizeof(quint32)));
        {
            QFile file(sourcePath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(original);
            file.close();
        }

        // --- Etape 1 : premier envoi, coupe cote destinataire en plein transfert ---
        auto receiver1 = std::make_unique<network::TransferService>();
        receiver1->setReceiveDirectory(m_destDir.path());
        QVERIFY(receiver1->start(receiverPort));

        QSignalSpy progress(&senderService, &network::TransferService::transferProgress);
        QSignalSpy rejected(&context, &core::TransferContext::transferRejected);

        QVERIFY(context.sendFile(sourcePath, QStringLiteral("127.0.0.1"), receiverPort));

        const qint64 cutThreshold = fileSize / 3;
        QVERIFY(QTest::qWaitFor([&]() {
            return !progress.isEmpty() && progress.last().at(1).toLongLong() >= cutThreshold;
        }, 10000));

        // Coupure reseau simulee : le destinataire disparait brutalement
        // (cable debranche / peer eteint), l'expediteur (senderService,
        // manager, context) reste lui intact.
        receiver1.reset();

        QVERIFY(QTest::qWaitFor([&]() {
            const QVariantList transfers = context.activeTransfers();
            for (const auto &item : transfers) {
                const QVariantMap entry = item.toMap();
                if (entry.value(QStringLiteral("fileName")).toString() == QStringLiteral("resume.bin")) {
                    return entry.value(QStringLiteral("statusText")).toString() == QStringLiteral("Échoué");
                }
            }
            return false;
        }, 5000));

        QString failedKey;
        for (const auto &item : context.activeTransfers()) {
            const QVariantMap entry = item.toMap();
            if (entry.value(QStringLiteral("fileName")).toString() == QStringLiteral("resume.bin")) {
                failedKey = entry.value(QStringLiteral("transferKey")).toString();
            }
        }
        QVERIFY(!failedKey.isEmpty());

        const QString partialPath = m_destDir.filePath(QStringLiteral("resume.bin.part"));
        QVERIFY(QFile::exists(partialPath));
        const qint64 partialSize = QFileInfo(partialPath).size();
        QVERIFY(partialSize > 0);
        QVERIFY(partialSize < fileSize);

        // --- Etape 2 : le destinataire revient (nouvelle instance, meme port) ---
        auto receiver2 = std::make_unique<network::TransferService>();
        receiver2->setReceiveDirectory(m_destDir.path());
        QVERIFY(receiver2->start(receiverPort));

        QSignalSpy receiver2Started(receiver2.get(), &network::TransferService::transferStarted);
        QSignalSpy senderCompleted(&senderService, &network::TransferService::transferCompleted);

        QVERIFY(context.retryTransfer(failedKey));
        QCOMPARE(rejected.count(), 0);

        QVERIFY(senderCompleted.wait(15000));

        // La reprise doit repartir de ce qui etait deja sur le disque au
        // moment de la coupure, pas de zero.
        QVERIFY(!receiver2Started.isEmpty());
        QCOMPARE(receiver2Started.first().at(4).toLongLong(), partialSize);

        const QString destPath = m_destDir.filePath(QStringLiteral("resume.bin"));
        QVERIFY(QFile::exists(destPath));
        QFile destFile(destPath);
        QVERIFY(destFile.open(QIODevice::ReadOnly));
        const QByteArray received = destFile.readAll();
        destFile.close();
        QCOMPARE(received, original);

        receiver2->stop();
    }
};

QTEST_MAIN(TestTransferContext)
#include "test_transfercontext.moc"
