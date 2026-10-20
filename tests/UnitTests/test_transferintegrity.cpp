// Lot 3 : reprise apres coupure, verification d'integrite, fichier existant preserve,
// limite de taille en reception.
#include <QtTest>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QDirIterator>
#include <QTemporaryDir>

#include "Security/SecurityService.h"
#include "Transfer/TransferService.h"

using network::SecurityService;
using network::TransferService;

class TestTransferIntegrity : public QObject
{
    Q_OBJECT

    QTemporaryDir m_source, m_dest, m_certA, m_certB;
    std::unique_ptr<SecurityService> m_securityA, m_securityB;

    // Les transferts passent par TLS : sans identite locale, configureTls() echoue et plus aucun
    // fichier ne part (cause des echecs des anciens tests de transfert).
    void wire(TransferService &sender, TransferService &receiver)
    {
        sender.setSecurityService(m_securityA.get());
        receiver.setSecurityService(m_securityB.get());
    }

    static quint16 nextPort()
    {
        static quint16 port = 24810;
        return ++port;
    }

    QString makeFile(const QString &name, qint64 size, char fill = 'a')
    {
        const QString path = m_source.filePath(name);
        QFile file(path);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(QByteArray(static_cast<int>(size), fill));
            file.close();
        }
        return path;
    }

    static QString sha256Of(const QString &path)
    {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
            return QString();
        QCryptographicHash hash(QCryptographicHash::Sha256);
        hash.addData(&file);
        return QString::fromLatin1(hash.result().toHex());
    }

    /// Chemin du fichier recu, quel que soit le sous-dossier par pair cree a la reception.
    QString findReceived(const QString &name) const
    {
        QDirIterator it(m_dest.path(), QStringList{name}, QDir::Files, QDirIterator::Subdirectories);
        return it.hasNext() ? it.next() : QString();
    }

private slots:
    void initTestCase()
    {
        QVERIFY(m_source.isValid() && m_dest.isValid() && m_certA.isValid() && m_certB.isValid());
        m_securityA = std::make_unique<SecurityService>(m_certA.path());
        m_securityB = std::make_unique<SecurityService>(m_certB.path());
        QVERIFY(m_securityA->initialize());
        QVERIFY(m_securityB->initialize());
    }

    // Reproduit le nom du fichier partiel calcule par TransferService (meme recette) : il doit
    // dependre du TRANSFERT LOGIQUE, pas de la connexion, sinon aucune reprise n'est possible.
    static QString partialNameFor(const QString &senderMachineId, const QString &senderUuid,
                                   const QString &recipientUuid, const QString &fileName, qint64 fileSize)
    {
        const QByteArray identity = senderMachineId.toUtf8() + '\0' + senderUuid.toUtf8() + '\0'
            + recipientUuid.toUtf8() + '\0' + fileName.toUtf8() + '\0' + QByteArray::number(fileSize);
        return fileName + QStringLiteral(".part-")
            + QString::fromLatin1(QCryptographicHash::hash(identity, QCryptographicHash::Sha256).toHex().left(16));
    }

    // Coupure simulee : des octets deja recus attendent dans le fichier partiel. Le transfert
    // doit repartir de la, pas de zero.
    void interruptedTransferResumesFromExistingPartialFile()
    {
        const quint16 port = nextPort();
        TransferService receiver;
        receiver.setReceiveDirectory(m_dest.path());
        QVERIFY(receiver.start(port));

        TransferService sender;
        wire(sender, receiver);

        const qint64 size = 1024 * 1024;
        const QString source = makeFile(QStringLiteral("reprise.bin"), size, 'r');
        const qint64 alreadyReceived = 300 * 1024;
        {
            // Debut de fichier deja recu lors d'une tentative precedente.
            QFile partial(m_dest.filePath(partialNameFor(QString(), QStringLiteral("exp"),
                                                          QStringLiteral("dest"),
                                                          QStringLiteral("reprise.bin"), size)));
            QVERIFY(partial.open(QIODevice::WriteOnly));
            partial.write(QByteArray(static_cast<int>(alreadyReceived), 'r'));
        }

        QSignalSpy started(&receiver, &TransferService::transferStarted);
        QSignalSpy completed(&receiver, &TransferService::transferCompleted);
        QVERIFY(sender.sendFile(QHostAddress::LocalHost, port, source,
                                 QStringLiteral("exp"), QStringLiteral("dest")));
        QVERIFY(completed.wait(20000));

        QVERIFY(!started.isEmpty());
        const qint64 resumeOffset = started.first().at(4).toLongLong();
        QCOMPARE(resumeOffset, alreadyReceived);
        QCOMPARE(sha256Of(findReceived(QStringLiteral("reprise.bin"))), sha256Of(source));
    }

    // Fichier partiel deja complet mais au contenu different : la verification d'integrite doit
    // le rejeter au lieu de le promouvoir comme fichier final.
    void corruptedPartialFileIsRejectedAndNotPromoted()
    {
        const quint16 port = nextPort();
        TransferService receiver;
        receiver.setReceiveDirectory(m_dest.path());
        QVERIFY(receiver.start(port));

        TransferService sender;
        wire(sender, receiver);

        const qint64 size = 64 * 1024;
        const QString source = makeFile(QStringLiteral("altere.bin"), size, 'b');
        {
            QFile partial(m_dest.filePath(partialNameFor(QString(), QStringLiteral("exp"),
                                                          QStringLiteral("dest"),
                                                          QStringLiteral("altere.bin"), size)));
            QVERIFY(partial.open(QIODevice::WriteOnly));
            partial.write(QByteArray(static_cast<int>(size), 'X')); // meme taille, contenu faux
        }

        QSignalSpy failed(&receiver, &TransferService::transferFailed);
        QSignalSpy completed(&receiver, &TransferService::transferCompleted);
        QVERIFY(sender.sendFile(QHostAddress::LocalHost, port, source,
                                 QStringLiteral("exp"), QStringLiteral("dest")));

        QVERIFY2(failed.wait(20000), "un contenu non conforme a l'empreinte doit etre refuse");
        QCOMPARE(completed.count(), 0);
        QVERIFY2(findReceived(QStringLiteral("altere.bin")).isEmpty(),
                 "le fichier altere ne doit jamais etre promu comme fichier final");
    }

    // Un fichier deja present ne doit plus etre ecrase en silence.
    void existingFileIsKeptAndNewOneIsRenamed()
    {
        const quint16 port = nextPort();
        TransferService receiver;
        receiver.setReceiveDirectory(m_dest.path());
        QVERIFY(receiver.start(port));

        TransferService sender;
        wire(sender, receiver);
        const QString source = makeFile(QStringLiteral("doublon.txt"), 2048, 'n');

        QSignalSpy completed(&receiver, &TransferService::transferCompleted);
        QVERIFY(sender.sendFile(QHostAddress::LocalHost, port, source, QStringLiteral("exp"), QStringLiteral("dest")));
        QVERIFY(completed.wait(20000));
        const QString first = findReceived(QStringLiteral("doublon.txt"));
        QVERIFY(!first.isEmpty());

        // On marque le premier fichier pour verifier qu'il n'est pas remplace.
        {
            QFile marker(first);
            QVERIFY(marker.open(QIODevice::WriteOnly | QIODevice::Truncate));
            marker.write(QByteArrayLiteral("original a conserver"));
        }

        TransferService sender2;
        wire(sender2, receiver);
        QSignalSpy completed2(&receiver, &TransferService::transferCompleted);
        QVERIFY(sender2.sendFile(QHostAddress::LocalHost, port, source, QStringLiteral("exp"), QStringLiteral("dest")));
        QVERIFY(completed2.wait(20000));

        QFile kept(first);
        QVERIFY(kept.open(QIODevice::ReadOnly));
        QCOMPARE(kept.readAll(), QByteArrayLiteral("original a conserver"));
        QVERIFY2(!findReceived(QStringLiteral("doublon (2).txt")).isEmpty(),
                 "le nouveau fichier doit etre depose a cote sous un nom libre");
    }

    void fileLargerThanLimitIsRefusedBeforeWriting()
    {
        const quint16 port = nextPort();
        TransferService receiver;
        receiver.setReceiveDirectory(m_dest.path());
        receiver.setMaxReceiveBytes(64 * 1024);
        QCOMPARE(receiver.maxReceiveBytes(), static_cast<qint64>(64 * 1024));
        QVERIFY(receiver.start(port));

        TransferService sender;
        wire(sender, receiver);
        QSignalSpy failed(&receiver, &TransferService::transferFailed);
        QSignalSpy completed(&receiver, &TransferService::transferCompleted);
        const QString source = makeFile(QStringLiteral("enorme.bin"), 256 * 1024, 'x');
        QVERIFY(sender.sendFile(QHostAddress::LocalHost, port, source, QStringLiteral("exp"), QStringLiteral("dest")));

        QVERIFY(failed.wait(20000));
        QCOMPARE(completed.count(), 0);
        QVERIFY2(findReceived(QStringLiteral("enorme.bin")).isEmpty(), "rien ne doit etre ecrit sur le disque");
    }
};

QTEST_GUILESS_MAIN(TestTransferIntegrity)
#include "test_transferintegrity.moc"
