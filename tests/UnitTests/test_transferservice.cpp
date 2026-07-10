#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QFile>
#include <QCryptographicHash>
#include <QRandomGenerator>

#include "Transfer/TransferService.h"

using network::TransferService;

/*
 * Verifie le critere d'acceptation de l'issue #53 :
 * "Un fichier de plusieurs centaines de Mo est transfere sans corruption".
 *
 * Pour garder le test rapide, on transfere un fichier de quelques
 * megaoctets (plusieurs dizaines de blocs, blockSize() == 64 Ko), ce qui
 * exerce le meme chemin de code (decoupage + envoi sequentiel + accuses
 * de reception + reconstruction) qu'un transfert de plusieurs centaines
 * de Mo, sans ralentir la suite de tests.
 */
class TestTransferService : public QObject
{
    Q_OBJECT

private:
    static QByteArray makeRandomFile(const QString &path, qint64 size)
    {
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly)) {
            return QByteArray();
        }
        QByteArray data;
        data.resize(static_cast<int>(size));
        QRandomGenerator::global()->fillRange(reinterpret_cast<quint32*>(data.data()),
                                               static_cast<qsizetype>(data.size() / sizeof(quint32)));
        file.write(data);
        file.close();
        return data;
    }

private slots:
    void startAndStop()
    {
        TransferService service;
        QVERIFY(service.start(23460));
        QVERIFY(service.isRunning());
        QCOMPARE(service.port(), static_cast<quint16>(23460));
        service.stop();
        QVERIFY(!service.isRunning());
    }

    void transferSmallFileWithoutCorruption()
    {
        QTemporaryDir sourceDir;
        QTemporaryDir destDir;
        QVERIFY(sourceDir.isValid());
        QVERIFY(destDir.isValid());

        const QString sourcePath = sourceDir.filePath(QStringLiteral("photo.bin"));
        // ~5 Mo : plusieurs dizaines de blocs de 64 Ko, sans ralentir le test.
        const qint64 fileSize = 5 * 1024 * 1024 + 137; // taille non alignee sur un bloc
        const QByteArray original = makeRandomFile(sourcePath, fileSize);
        QCOMPARE(original.size(), static_cast<int>(fileSize));

        TransferService receiver;
        receiver.setReceiveDirectory(destDir.path());
        QVERIFY(receiver.start(23461));

        TransferService sender;

        QSignalSpy receiverStarted(&receiver, &TransferService::transferStarted);
        QSignalSpy receiverCompleted(&receiver, &TransferService::transferCompleted);
        QSignalSpy receiverFailed(&receiver, &TransferService::transferFailed);
        QSignalSpy senderCompleted(&sender, &TransferService::transferCompleted);
        QSignalSpy senderFailed(&sender, &TransferService::transferFailed);

        QVERIFY(sender.sendFile(QHostAddress::LocalHost, 23461, sourcePath));

        QVERIFY(senderCompleted.wait(10000));
        QCOMPARE(senderFailed.count(), 0);

        if (receiverCompleted.isEmpty()) {
            QVERIFY(receiverCompleted.wait(5000));
        }
        QCOMPARE(receiverFailed.count(), 0);
        QVERIFY(!receiverStarted.isEmpty());

        const QString destPath = receiverCompleted.first().at(1).toString();
        QVERIFY(QFile::exists(destPath));

        QFile destFile(destPath);
        QVERIFY(destFile.open(QIODevice::ReadOnly));
        const QByteArray received = destFile.readAll();
        destFile.close();

        QCOMPARE(received.size(), original.size());
        QCOMPARE(QCryptographicHash::hash(received, QCryptographicHash::Sha256),
                  QCryptographicHash::hash(original, QCryptographicHash::Sha256));

        receiver.stop();
    }

    void sendMissingFileFails()
    {
        TransferService sender;
        QVERIFY(!sender.sendFile(QHostAddress::LocalHost, 23462,
                                  QStringLiteral("/path/does/not/exist.bin")));
    }
};

QTEST_MAIN(TestTransferService)
#include "test_transferservice.moc"
