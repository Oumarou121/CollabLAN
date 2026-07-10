#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QFile>
#include <QFileInfo>
#include <QCryptographicHash>
#include <QRandomGenerator>
#include <memory>

#include "Transfer/TransferService.h"

using network::TransferService;

/*
 * Issue #59 : "Test d'integration de la reprise de transfert" -
 * simule une veritable coupure reseau EN PLEIN transfert (pas un fichier
 * ".part" pre-fabrique comme dans test_transferservice.cpp) puis verifie
 * que la reprise automatique (issue #54) aboutit a un fichier final
 * identique (checksum SHA-256) a l'original, malgre la coupure.
 *
 * Scenario :
 *  1. Un premier TransferService "sender1" envoie un fichier de
 *     plusieurs Mo vers un "receiver" en ecoute.
 *  2. Des qu'une partie significative du fichier a ete transferee
 *     (transferProgress), on simule une coupure reseau en detruisant
 *     sender1 en plein envoi (fermeture brutale de la connexion TCP,
 *     sans clore proprement le protocole applicatif) - equivalent a un
 *     cable reseau debranche ou un peer qui s'eteint brutalement.
 *  3. On verifie que le fichier temporaire ".part" cote destinataire
 *     existe et ne contient qu'une partie du fichier (transfert bien
 *     interrompu, pas termine).
 *  4. Un second TransferService "sender2" (nouvelle connexion, comme le
 *     ferait l'UI en relancant l'envoi apres une coupure) envoie a
 *     nouveau le meme fichier vers le meme destinataire : la reprise
 *     automatique doit repartir du dernier octet confirme, pas de zero.
 *  5. Le fichier final recu doit etre bit-a-bit identique (checksum
 *     SHA-256) au fichier original.
 */
class TestTransferResumeIntegration : public QObject
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

    static QByteArray sha256(const QByteArray &data)
    {
        return QCryptographicHash::hash(data, QCryptographicHash::Sha256);
    }

private slots:

    void transferResumesAfterSimulatedNetworkCutAndMatchesChecksum()
    {
        QTemporaryDir sourceDir;
        QTemporaryDir destDir;
        QVERIFY(sourceDir.isValid());
        QVERIFY(destDir.isValid());

        const QString sourcePath = sourceDir.filePath(QStringLiteral("gros_fichier.bin"));
        // ~8 Mo : suffisamment de blocs (64 Ko/bloc) pour pouvoir couper
        // la connexion nettement avant la fin, sans pour autant ralentir
        // excessivement le test.
        const qint64 fileSize = 8 * 1024 * 1024 + 421; // taille non alignee sur un bloc
        const QByteArray original = makeRandomFile(sourcePath, fileSize);
        QCOMPARE(original.size(), static_cast<int>(fileSize));
        const QByteArray originalChecksum = sha256(original);

        const quint16 receiverPort = 23470;

        auto receiver = std::make_unique<TransferService>();
        receiver->setReceiveDirectory(destDir.path());
        QVERIFY(receiver->start(receiverPort));

        QSignalSpy receiverStarted(receiver.get(), &TransferService::transferStarted);
        QSignalSpy receiverFailed(receiver.get(), &TransferService::transferFailed);
        QSignalSpy receiverCompleted(receiver.get(), &TransferService::transferCompleted);

        // --- Etape 1 : premier envoi, interrompu volontairement en cours ---
        auto sender1 = std::make_unique<TransferService>();
        QSignalSpy sender1Progress(sender1.get(), &TransferService::transferProgress);

        QVERIFY(sender1->sendFile(QHostAddress::LocalHost, receiverPort, sourcePath,
                                   /*senderId=*/1, /*recipientId=*/2));

        // Attend que le transfert ait progresse au-dela d'un tiers du
        // fichier avant de simuler la coupure, pour etre sur d'interrompre
        // un transfert reellement en cours (pas juste la connexion initiale).
        const qint64 cutThreshold = fileSize / 3;
        QVERIFY(QTest::qWaitFor([&]() {
            return !sender1Progress.isEmpty()
                && sender1Progress.last().at(1).toLongLong() >= cutThreshold;
        }, 10000));

        const qint64 bytesBeforeCut = sender1Progress.last().at(1).toLongLong();
        QVERIFY(bytesBeforeCut > 0);
        QVERIFY(bytesBeforeCut < fileSize);

        // Simule la coupure reseau : destruction brutale de l'expediteur
        // en plein transfert (le socket TCP sous-jacent est ferme sans
        // achever le protocole applicatif), exactement comme le vivrait
        // un cable debranche ou un processus qui crashe en cours d'envoi.
        sender1.reset();

        // Cote destinataire, la deconnexion prematuree doit etre detectee
        // comme un echec (pas un succes) : le transfert n'est pas termine.
        QVERIFY(receiverFailed.wait(5000));
        QCOMPARE(receiverCompleted.count(), 0);

        // Le fichier temporaire ".part" doit exister et ne contenir
        // qu'une partie du fichier (transfert bien interrompu).
        const QString partialPath = destDir.filePath(QStringLiteral("gros_fichier.bin.part"));
        QVERIFY(QFile::exists(partialPath));
        const qint64 partialSize = QFileInfo(partialPath).size();
        QVERIFY(partialSize > 0);
        QVERIFY(partialSize < fileSize);

        // --- Etape 2 : reprise automatique via un nouvel envoi ---
        receiverStarted.clear();
        receiverFailed.clear();
        receiverCompleted.clear();

        auto sender2 = std::make_unique<TransferService>();
        QSignalSpy sender2Completed(sender2.get(), &TransferService::transferCompleted);
        QSignalSpy sender2Failed(sender2.get(), &TransferService::transferFailed);
        QSignalSpy sender2Progress(sender2.get(), &TransferService::transferProgress);

        QVERIFY(sender2->sendFile(QHostAddress::LocalHost, receiverPort, sourcePath,
                                   /*senderId=*/1, /*recipientId=*/2));

        QVERIFY(sender2Completed.wait(15000));
        QCOMPARE(sender2Failed.count(), 0);

        if (receiverCompleted.isEmpty()) {
            QVERIFY(receiverCompleted.wait(5000));
        }
        QCOMPARE(receiverFailed.count(), 0);

        // La reprise doit repartir de ce qui etait deja sur le disque au
        // moment de la coupure, pas de zero (critere central de l'issue
        // #54, reverifie ici dans un scenario de coupure reelle).
        QVERIFY(!receiverStarted.isEmpty());
        const qint64 announcedResumeOffset = receiverStarted.first().at(4).toLongLong();
        QCOMPARE(announcedResumeOffset, partialSize);

        QVERIFY(!sender2Progress.isEmpty());
        const qint64 firstReportedBytes = sender2Progress.first().at(1).toLongLong();
        QCOMPARE(firstReportedBytes, partialSize);

        // --- Etape 3 : integrite du fichier final (critere d'acceptation) ---
        const QString destPath = receiverCompleted.first().at(1).toString();
        QVERIFY(QFile::exists(destPath));

        QFile destFile(destPath);
        QVERIFY(destFile.open(QIODevice::ReadOnly));
        const QByteArray received = destFile.readAll();
        destFile.close();

        QCOMPARE(received.size(), original.size());
        QCOMPARE(sha256(received), originalChecksum);

        receiver->stop();
    }
};

QTEST_MAIN(TestTransferResumeIntegration)
#include "test_transferresumeintegration.moc"
