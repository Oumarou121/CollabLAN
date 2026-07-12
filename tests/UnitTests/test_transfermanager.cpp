#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QHostAddress>
#include <QFile>
#include <QRandomGenerator>

#include "database/DatabaseManager.h"
#include "database/Repositories/TransferRepository.h"
#include "database/Repositories/UserRepository.h"
#include "network/Transfer/TransferService.h"
#include "TransferManager.h"

/*
 * Issue #55 : "Enregistrement d'un transfert (fichier, expediteur,
 * destinataire, statut)" + "Mise a jour du statut (en cours / termine /
 * echoue)", avec comme critere d'acceptation que "L'historique des
 * transferts est consultable apres redemarrage".
 *
 * On fait realiser un transfert TCP complet (TransferService en boucle
 * locale, a la fois expediteur et destinataire) pilote par un
 * core::TransferManager, puis on "redemarre" en rouvrant une toute
 * nouvelle database::DatabaseManager sur le meme fichier .sqlite pour
 * verifier que l'historique persiste bel et bien sur disque.
 */
class TestTransferManager : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dbDir;
    QTemporaryDir m_sourceDir;
    QTemporaryDir m_destDir;
    QString m_dbPath;
    int m_senderId = -1;
    int m_recipientId = -1;

private slots:
    void init()
    {
        QVERIFY(m_dbDir.isValid());
        QVERIFY(m_sourceDir.isValid());
        QVERIFY(m_destDir.isValid());
        m_dbPath = m_dbDir.filePath(
            QStringLiteral("test_%1.sqlite").arg(QRandomGenerator::global()->generate()));

        database::DatabaseManager setup(
            QStringLiteral("test_transfermanager_setup_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(setup.open(m_dbPath));

        database::UserRepository userRepo(setup.database());
        models::User sender;
        sender.setName(QStringLiteral("alice"));
        sender.setPasswordHash(QStringLiteral("hash"));
        sender.setPasswordSalt(QStringLiteral("salt"));
        m_senderId = userRepo.create(sender);
        QVERIFY(m_senderId >= 0);

        models::User recipient;
        recipient.setName(QStringLiteral("bob"));
        recipient.setPasswordHash(QStringLiteral("hash"));
        recipient.setPasswordSalt(QStringLiteral("salt"));
        m_recipientId = userRepo.create(recipient);
        QVERIFY(m_recipientId >= 0);

        setup.close();
    }

    void completedTransferIsRecordedAndSurvivesRestart()
    {
        const QString sourcePath = m_sourceDir.filePath(QStringLiteral("note.txt"));
        {
            QFile file(sourcePath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(QByteArrayLiteral("contenu du transfert de test"));
            file.close();
        }

        // --- Session 1 : realise le transfert (avant "redemarrage") ---
        int recordedIncomingId = -1;
        {
            database::DatabaseManager dbManager(
                QStringLiteral("test_transfermanager_session1_%1").arg(QRandomGenerator::global()->generate()));
            QVERIFY(dbManager.open(m_dbPath));

            network::TransferService transferService;
            transferService.setReceiveDirectory(m_destDir.path());
            QVERIFY(transferService.start(23470));

            core::TransferManager manager(&dbManager);
            manager.setTransferService(&transferService);

            QSignalSpy recorded(&manager, &core::TransferManager::transferRecorded);
            QSignalSpy statusChanged(&manager, &core::TransferManager::transferStatusChanged);
            QSignalSpy completed(&transferService, &network::TransferService::transferCompleted);

            QVERIFY(manager.sendFile(QHostAddress::LocalHost, 23470, sourcePath, m_senderId, m_recipientId));

            // Deux transferCompleted attendus : le socket expediteur ET le
            // socket destinataire (TransferService envoie et recoit ici
            // via la meme instance, en boucle locale).
            QVERIFY(completed.wait(5000));
            if (completed.count() < 2) {
                QVERIFY(completed.wait(5000));
            }
            QCOMPARE(completed.count(), 2);

            // Laisse le temps aux deux transferStatusChanged(Completed)
            // de se propager (traitement asynchrone des deux sockets).
            QTRY_COMPARE(statusChanged.count(), 2);

            QCOMPARE(recorded.count(), 2); // un enregistrement sortant + un entrant
            for (const auto &args : statusChanged) {
                QCOMPARE(args.at(1).value<models::TransferStatus>(), models::TransferStatus::Completed);
            }

            const auto history = manager.userTransfers(m_recipientId);
            QVERIFY(!history.empty());
            for (const auto &t : history) {
                if (t.recipientId() == m_recipientId && t.senderId() == m_senderId) {
                    recordedIncomingId = t.id();
                }
            }
            QVERIFY(recordedIncomingId >= 0);

            const auto found = manager.transfer(recordedIncomingId);
            QVERIFY(found.has_value());
            QCOMPARE(found->status(), models::TransferStatus::Completed);
            QCOMPARE(found->fileName(), QStringLiteral("note.txt"));
            // Le chemin de destination (dossier de reception + nom de
            // fichier) n'est connu qu'a la fin du transfert : verifie qu'il
            // a bien ete renseigne en base (issue "ouvrir l'emplacement").
            QVERIFY(!found->filePath().isEmpty());
            QVERIFY(found->filePath().startsWith(m_destDir.path()));

            transferService.stop();
            dbManager.close();
        }
        // dbManager et transferService detruits ici : simule la fermeture
        // complete de l'application.

        // --- Session 2 : "redemarrage" de l'application ---
        {
            database::DatabaseManager dbManager(
                QStringLiteral("test_transfermanager_session2_%1").arg(QRandomGenerator::global()->generate()));
            QVERIFY(dbManager.open(m_dbPath));

            database::TransferRepository repoAfterRestart(dbManager.database());
            const auto reloaded = repoAfterRestart.findById(recordedIncomingId);
            QVERIFY(reloaded.has_value());
            QCOMPARE(reloaded->fileName(), QStringLiteral("note.txt"));
            QCOMPARE(reloaded->status(), models::TransferStatus::Completed);
            QCOMPARE(reloaded->senderId(), m_senderId);
            QCOMPARE(reloaded->recipientId(), m_recipientId);
            QVERIFY(!reloaded->filePath().isEmpty());

            const auto userHistory = repoAfterRestart.findByUser(m_recipientId);
            QVERIFY(!userHistory.empty());

            dbManager.close();
        }
    }

    void transferWithoutValidUserIdsIsStillPersisted()
    {
        // Avant la migration #012, sender_id/recipient_id etaient NOT NULL
        // REFERENCES Users(id) : un id inconnu (-1, cas courant d'un envoi
        // vers un poste LAN sans compte utilisateur associe) violait la
        // contrainte de cle etrangere et l'INSERT echouait silencieusement,
        // privant l'utilisateur de tout historique pour ce transfert. Ces
        // colonnes sont desormais nullables : le transfert doit toujours
        // apparaitre dans l'historique, avec un id "inconnu" represente
        // par -1 (voir TransferRepository::transferFromQuery()).
        const QString sourcePath = m_sourceDir.filePath(QStringLiteral("anonymous.txt"));
        {
            QFile file(sourcePath);
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.write(QByteArrayLiteral("x"));
            file.close();
        }

        database::DatabaseManager dbManager(
            QStringLiteral("test_transfermanager_novalid_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(dbManager.open(m_dbPath));

        network::TransferService transferService;
        transferService.setReceiveDirectory(m_destDir.path());
        QVERIFY(transferService.start(23471));

        core::TransferManager manager(&dbManager);
        manager.setTransferService(&transferService);

        QSignalSpy completed(&transferService, &network::TransferService::transferCompleted);
        QVERIFY(manager.sendFile(QHostAddress::LocalHost, 23471, sourcePath, /*senderId=*/-1, /*recipientId=*/-1));
        QVERIFY(completed.wait(5000));
        if (completed.count() < 2) {
            QVERIFY(completed.wait(5000));
        }

        const auto history = manager.allTransfers();
        bool found = false;
        for (const auto &t : history) {
            if (t.fileName() == QStringLiteral("anonymous.txt")) {
                QCOMPARE(t.senderId(), -1);
                QCOMPARE(t.recipientId(), -1);
                found = true;
            }
        }
        QVERIFY(found);

        transferService.stop();
        dbManager.close();
    }
};

QTEST_MAIN(TestTransferManager)
#include "test_transfermanager.moc"
