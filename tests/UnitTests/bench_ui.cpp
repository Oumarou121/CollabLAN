// Banc d'essai (hors ctest) : temps des appels que l'interface fait sur le fil
// principal, sur une base remplie a des volumes realistes. Lancer :
//   bench_ui.exe            (affiche une ligne "BENCH <appel> <ms>" par mesure)
#include <QtTest>
#include <QElapsedTimer>
#include <QRandomGenerator>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QUuid>

#include "Application.h"
#include "AuditLogModel.h"
#include "CallHistoryModel.h"
#include "MessagingContext.h"
#include "SharedFolderContext.h"
#include "SharedFolderManager.h"
#include "UserManager.h"
#include "Election/ElectionService.h"


class BenchUi : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;
    std::unique_ptr<Application> m_app;
    qint64 m_bigConversation = 0;
    qint64 m_firstFolder = 0;

    template <typename F>
    static double time(const char *what, F &&f, int repeat = 3)
    {
        double best = 1e9;
        for (int i = 0; i < repeat; ++i) {
            QElapsedTimer t;
            t.start();
            f();
            best = qMin(best, t.nsecsElapsed() / 1e6);
        }
        qInfo().noquote() << QStringLiteral("BENCH %1 %2 ms").arg(QString::fromLatin1(what)).arg(best, 0, 'f', 1);
        return best;
    }

    void populate(const QString &dbPath, int adminId)
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), QStringLiteral("bench"));
        db.setDatabaseName(dbPath);
        QVERIFY(db.open());
        QSqlQuery q(db);
        QVERIFY(db.transaction());

        // 39 correspondants, une conversation chacun ; 40 000 messages dont
        // 10 000 dans une seule conversation.
        QVector<qint64> convs;
        for (int u = 1; u <= 39; ++u) {
            q.prepare(QStringLiteral("INSERT INTO Users(name, uuid, role) VALUES(:n, :u, 'user')"));
            q.bindValue(QStringLiteral(":n"), QStringLiteral("poste%1").arg(u));
            q.bindValue(QStringLiteral(":u"), QUuid::createUuid().toString(QUuid::WithoutBraces));
            QVERIFY2(q.exec(), qPrintable(q.lastError().text()));
            const qint64 uid = q.lastInsertId().toLongLong();
            q.prepare(QStringLiteral("INSERT INTO Conversations(type, name, participant1_id, participant2_id, uuid) "
                                     "VALUES('individual', '', :a, :b, :u)"));
            q.bindValue(QStringLiteral(":a"), adminId);
            q.bindValue(QStringLiteral(":b"), uid);
            q.bindValue(QStringLiteral(":u"), QUuid::createUuid().toString(QUuid::WithoutBraces));
            QVERIFY2(q.exec(), qPrintable(q.lastError().text()));
            convs << q.lastInsertId().toLongLong();
        }
        m_bigConversation = convs.first();
        q.prepare(QStringLiteral("INSERT INTO Messages(conversationId, senderId, content, timestamp, is_read, uuid, delivery_status) "
                                 "VALUES(:c, :s, :t, :ts, :r, :u, 'read')"));
        QDateTime ts = QDateTime::currentDateTimeUtc().addDays(-200);
        for (int i = 0; i < 40000; ++i) {
            const qint64 conv = i < 10000 ? convs.first() : convs.at(1 + (i % (convs.size() - 1)));
            q.bindValue(QStringLiteral(":c"), conv);
            q.bindValue(QStringLiteral(":s"), adminId);
            q.bindValue(QStringLiteral(":t"), QStringLiteral("Message numero %1 avec un peu de texte pour la forme.").arg(i));
            q.bindValue(QStringLiteral(":ts"), ts.addSecs(i * 60).toString(Qt::ISODate));
            q.bindValue(QStringLiteral(":r"), i % 50 == 0 ? 0 : 1);
            q.bindValue(QStringLiteral(":u"), QUuid::createUuid().toString(QUuid::WithoutBraces));
            QVERIFY2(q.exec(), qPrintable(q.lastError().text()));
        }

        // 5 dossiers de 2 000 fichiers.
        for (int f = 0; f < 5; ++f) {
            q.prepare(QStringLiteral("INSERT INTO SharedFolders(uuid, name, local_path, owner_id) VALUES(:u, :n, :p, :o)"));
            q.bindValue(QStringLiteral(":u"), QUuid::createUuid().toString(QUuid::WithoutBraces));
            q.bindValue(QStringLiteral(":n"), QStringLiteral("Dossier %1").arg(f));
            q.bindValue(QStringLiteral(":p"), m_dir.filePath(QStringLiteral("d%1").arg(f)));
            q.bindValue(QStringLiteral(":o"), adminId);
            QVERIFY2(q.exec(), qPrintable(q.lastError().text()));
            const qint64 folderId = q.lastInsertId().toLongLong();
            if (f == 0) m_firstFolder = folderId;
            q.prepare(QStringLiteral("INSERT INTO SharedFiles(folder_id, relative_path, hash, size) VALUES(:f, :p, :h, 1000)"));
            for (int i = 0; i < 2000; ++i) {
                q.bindValue(QStringLiteral(":f"), folderId);
                q.bindValue(QStringLiteral(":p"), QStringLiteral("sous%1/fichier-%2.docx").arg(i % 40).arg(i));
                q.bindValue(QStringLiteral(":h"), QStringLiteral("%1").arg(i, 64, 16, QLatin1Char('0')));
                QVERIFY2(q.exec(), qPrintable(q.lastError().text()));
            }
        }

        // 30 000 entrees de journal, 2 000 appels.
        q.prepare(QStringLiteral("INSERT INTO AuditLogs(created_at, event_type, description, user_id, actor_label) "
                                 "VALUES(:ts, :e, :d, :u, '192.168.1.20')"));
        const QStringList types = {QStringLiteral("connection"), QStringLiteral("message"), QStringLiteral("transfer"), QStringLiteral("call")};
        for (int i = 0; i < 30000; ++i) {
            q.bindValue(QStringLiteral(":ts"), ts.addSecs(i * 300).toString(QStringLiteral("yyyy-MM-dd HH:mm:ss")));
            q.bindValue(QStringLiteral(":e"), types.at(i % types.size()));
            q.bindValue(QStringLiteral(":d"), QStringLiteral("Evenement %1").arg(i));
            q.bindValue(QStringLiteral(":u"), adminId);
            QVERIFY2(q.exec(), qPrintable(q.lastError().text()));
        }
        q.prepare(QStringLiteral("INSERT INTO CallHistory(call_uuid, local_user_id, direction, peer_address, status, started_at, duration_seconds) "
                                 "VALUES(:c, :u, 'incoming', '192.168.1.20', 'completed', :ts, 60)"));
        for (int i = 0; i < 2000; ++i) {
            q.bindValue(QStringLiteral(":c"), QUuid::createUuid().toString(QUuid::WithoutBraces));
            q.bindValue(QStringLiteral(":u"), adminId);
            q.bindValue(QStringLiteral(":ts"), ts.addSecs(i * 3600).toString(QStringLiteral("yyyy-MM-dd HH:mm:ss")));
            QVERIFY2(q.exec(), qPrintable(q.lastError().text()));
        }
        QVERIFY(db.commit());
        db.close();
    }

private slots:
    void run()
    {
        QVERIFY(m_dir.isValid());
        const quint16 base = static_cast<quint16>(47000 + QRandomGenerator::global()->bounded(400) * 10);
        const QString dbPath = m_dir.filePath(QStringLiteral("bench.db"));
        m_app = std::make_unique<Application>();
        m_app->setDiscoveryPort(static_cast<quint16>(base + 5));
        m_app->initialize(base, dbPath, QStringLiteral("SERVER"), -1, static_cast<quint16>(base + 9));
        const auto admin = m_app->userManager()->createUser(QStringLiteral("admin"), QStringLiteral("motdepasse"));
        QVERIFY(admin.has_value());
        populate(dbPath, admin->id());
        QVERIFY(m_app->userManager()->login(QStringLiteral("admin"), QStringLiteral("motdepasse")));

        core::MessagingContext messaging;
        messaging.setMessagingManager(m_app->messagingManager());
        messaging.setGroupManager(m_app->groupManager());
        messaging.setUserManager(m_app->userManager());
        time("messaging.conversationsList (sans cache)", [&] { emit messaging.conversationsChanged(); QVERIFY(messaging.conversationsList().size() == 39); });
        time("messaging.conversationsList (cache)", [&] { QVERIFY(messaging.conversationsList().size() == 39); });
        time("messaging.totalUnreadCount (sans cache)", [&] { emit messaging.conversationsChanged(); messaging.totalUnreadCount(); });
        time("messaging.setConversation(10k)", [&] { messaging.setConversation(m_bigConversation); }, 2);

        core::SharedFolderContext folders;
        folders.setSharedFolderManager(m_app->sharedFolderManager());
        folders.setUserManager(m_app->userManager());
        time("folders.refresh", [&] { folders.refresh(); });
        time("folders.filesForFolder(2k)", [&] { QVERIFY(folders.filesForFolder(m_firstFolder).size() == 2000); });
        time("folders.getConflicts(2k)", [&] { folders.getConflicts(m_firstFolder); });
        time("folders.syncHistoryForFolder", [&] { folders.syncHistoryForFolder(m_firstFolder, 50); });

        core::AuditLogModel audit;
        audit.setAuditManager(reinterpret_cast<QObject *>(m_app->auditManager()));
        time("audit.refresh", [&] { audit.refresh(); });
        time("audit.setEventTypeFilter", [&] { audit.setEventTypeFilter(QStringLiteral("call")); });
        audit.clearFilters();

        core::CallHistoryModel calls;
        calls.setUserManager(m_app->userManager());
        calls.setCallHistoryManager(reinterpret_cast<QObject *>(m_app->callHistoryManager()));
        time("calls.refresh", [&] { calls.refresh(); });
    }
};

QTEST_MAIN(BenchUi)
#include "bench_ui.moc"
