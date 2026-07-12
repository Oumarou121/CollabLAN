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

        QVERIFY(sender.sendFile(QHostAddress::LocalHost, 23461, sourcePath, /*senderUuid=*/QStringLiteral("1"), /*recipientUuid=*/QStringLiteral("2")));

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
                                  QStringLiteral("/path/does/not/exist.bin"),
                                  QStringLiteral("1"), QStringLiteral("2")));
    }

    /*
     * Issue #54 : "Un transfert coupe au milieu reprend sans repartir de
     * zero". On simule une interruption reseau en pre-remplissant le
     * fichier temporaire "<nom>.part" cote destinataire avec le debut du
     * fichier (comme le ferait un premier envoi interrompu en cours de
     * route), puis on relance un envoi complet du meme fichier : le
     * destinataire doit annoncer un resumeOffset correspondant a ce qui
     * est deja sur le disque, et le fichier final doit etre identique a
     * l'original (aucune donnee perdue ni dupliquee).
     */
    void resumeInterruptedTransferContinuesFromLastAck()
    {
        QTemporaryDir sourceDir;
        QTemporaryDir destDir;
        QVERIFY(sourceDir.isValid());
        QVERIFY(destDir.isValid());

        const QString sourcePath = sourceDir.filePath(QStringLiteral("archive.bin"));
        const qint64 fileSize = 3 * 1024 * 1024 + 777; // non aligne sur un bloc
        const QByteArray original = makeRandomFile(sourcePath, fileSize);
        QCOMPARE(original.size(), static_cast<int>(fileSize));

        // Simule un transfert precedent interrompu a mi-chemin : le
        // fichier ".part" cote destinataire contient deja la premiere
        // moitie du fichier.
        const qint64 alreadyReceived = fileSize / 2;
        QVERIFY(alreadyReceived > 0);
        const QString partialPath = destDir.filePath(QStringLiteral("archive.bin.part"));
        {
            QFile partial(partialPath);
            QVERIFY(partial.open(QIODevice::WriteOnly));
            QCOMPARE(partial.write(original.left(static_cast<int>(alreadyReceived))),
                      static_cast<qint64>(alreadyReceived));
            partial.close();
        }

        TransferService receiver;
        receiver.setReceiveDirectory(destDir.path());
        QVERIFY(receiver.start(23463));

        TransferService sender;

        QSignalSpy receiverStarted(&receiver, &TransferService::transferStarted);
        QSignalSpy receiverCompleted(&receiver, &TransferService::transferCompleted);
        QSignalSpy receiverFailed(&receiver, &TransferService::transferFailed);
        QSignalSpy senderCompleted(&sender, &TransferService::transferCompleted);
        QSignalSpy senderProgress(&sender, &TransferService::transferProgress);

        QVERIFY(sender.sendFile(QHostAddress::LocalHost, 23463, sourcePath, /*senderUuid=*/QStringLiteral("1"), /*recipientUuid=*/QStringLiteral("2")));

        QVERIFY(senderCompleted.wait(10000));
        if (receiverCompleted.isEmpty()) {
            QVERIFY(receiverCompleted.wait(5000));
        }
        QCOMPARE(receiverFailed.count(), 0);

        // Le destinataire doit avoir annonce une reprise (resumeOffset ==
        // taille deja recue), pas un transfert repartant de zero.
        QVERIFY(!receiverStarted.isEmpty());
        const qint64 announcedResumeOffset = receiverStarted.first().at(4).toLongLong();
        QCOMPARE(announcedResumeOffset, alreadyReceived);

        // La toute premiere progression cote expediteur doit refleter la
        // reprise (deja a alreadyReceived), pas repartir de 0.
        QVERIFY(!senderProgress.isEmpty());
        const qint64 firstReportedBytes = senderProgress.first().at(1).toLongLong();
        QCOMPARE(firstReportedBytes, alreadyReceived);

        // Le fichier final doit etre identique a l'original, sans perte
        // ni duplication de donnees autour du point de reprise.
        const QString destPath = receiverCompleted.first().at(1).toString();
        QFile destFile(destPath);
        QVERIFY(destFile.open(QIODevice::ReadOnly));
        const QByteArray received = destFile.readAll();
        destFile.close();

        QCOMPARE(received.size(), original.size());
        QCOMPARE(QCryptographicHash::hash(received, QCryptographicHash::Sha256),
                  QCryptographicHash::hash(original, QCryptographicHash::Sha256));

        receiver.stop();
    }
};

QTEST_MAIN(TestTransferService)
#include "test_transferservice.moc"
