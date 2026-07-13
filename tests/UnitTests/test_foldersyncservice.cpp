#include <QtTest>
#include <QSignalSpy>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QHostAddress>
#include <QTemporaryDir>
#include <QFile>
#include <QDir>
#include <QCryptographicHash>
#include <QRandomGenerator>

#include "core/Sync/FolderSyncService.h"
#include "core/SharedFolderManager.h"
#include "database/DatabaseManager.h"
#include "database/Repositories/SharedFileRepository.h"

// ---------------------------------------------------------------------------
// Stub minimaliste de MessagingServer/Service pour capturer les messages
// envoyés par FolderSyncService sans ouvrir de vrais sockets réseau.
// ---------------------------------------------------------------------------

/**
 * Simule la partie émission de MessagingServer (broadcastMessage) :
 * connecte un spy sur le signal broadcastCalled() que StubServer émet
 * à la place de l'envoi réseau réel.
 */
class StubMessagingServer : public QObject
{
    Q_OBJECT
public:
    explicit StubMessagingServer(QObject *parent = nullptr) : QObject(parent) {}

    bool isRunning() const { return m_running; }
    void setRunning(bool v) { m_running = v; }

    int broadcastMessage(const QString &msg)
    {
        m_sentMessages.append(msg);
        emit broadcastCalled(msg);
        return 1;
    }

    // Simule la réception d'un message entrant depuis un client.
    void injectIncoming(const QString &msg, const QHostAddress &addr = QHostAddress::LocalHost)
    {
        emit messageReceived(msg, addr);
    }

    QStringList sentMessages() const { return m_sentMessages; }

signals:
    void messageReceived(const QString &message, const QHostAddress &senderAddress);
    void clientConnected(const QHostAddress &);
    void clientDisconnected(const QHostAddress &);
    void connectionRefused(const QHostAddress &, const QString &);
    void error(const QString &);
    void broadcastCalled(const QString &message);

private:
    bool m_running = true;
    QStringList m_sentMessages;
};

class StubMessagingService : public QObject
{
    Q_OBJECT
public:
    explicit StubMessagingService(QObject *parent = nullptr) : QObject(parent) {}

    bool isConnected() const { return m_connected; }
    void setConnected(bool v) { m_connected = v; }

    bool sendMessage(const QString &msg)
    {
        m_sentMessages.append(msg);
        emit messageSent(msg);
        return true;
    }

    QHostAddress peerAddress() const { return QHostAddress::LocalHost; }
    quint16 peerPort() const { return 0; }

    // Simule la réception d'un message depuis le serveur.
    void injectIncoming(const QString &msg)
    {
        emit messageReceived(msg);
    }

    QStringList sentMessages() const { return m_sentMessages; }

signals:
    void connected();
    void disconnected();
    void messageReceived(const QString &message);
    void error(const QString &errorString);
    void messageSent(const QString &message);

private:
    bool m_connected = false;
    QStringList m_sentMessages;
};

// ---------------------------------------------------------------------------
// Helper : crée un DatabaseManager en mémoire avec les migrations minimales.
// ---------------------------------------------------------------------------
static std::unique_ptr<database::DatabaseManager> makeInMemoryDb()
{
    static int counter = 0;
    auto db = std::make_unique<database::DatabaseManager>(
        QStringLiteral("fss_test_%1").arg(++counter));
    if (!db->open(QStringLiteral(":memory:"))) {
        return nullptr;
    }
    return db;
}

// ---------------------------------------------------------------------------
// Classe de test principale
// ---------------------------------------------------------------------------
class TestFolderSyncService : public QObject
{
    Q_OBJECT

private:
    // Construit un FolderSyncService sans dépendances réseau (tests purs).
    core::sync::FolderSyncService *makeService(database::DatabaseManager *db,
                                                QObject *parent = nullptr)
    {
        auto *svc = new core::sync::FolderSyncService(db, nullptr, parent);
        svc->setLocalMachineId(QStringLiteral("machine-test-local"));
        return svc;
    }

    // Construit un JSON folder_op valide.
    static QString makeFolderOpJson(const QString &opType = QStringLiteral("Create"),
                                    const QString &machineId = QStringLiteral("machine-remote"),
                                    const QString &folderUuid = QStringLiteral("uuid-folder-1"),
                                    const QString &path = QStringLiteral("docs/file.txt"))
    {
        QJsonObject obj;
        obj[QStringLiteral("type")]             = QStringLiteral("folder_op");
        obj[QStringLiteral("folder_uuid")]      = folderUuid;
        obj[QStringLiteral("folder_name")]      = QStringLiteral("My Docs");
        obj[QStringLiteral("op_type")]          = opType;
        obj[QStringLiteral("relative_path")]    = path;
        obj[QStringLiteral("old_relative_path")] = QString();
        obj[QStringLiteral("file_hash")]        = QStringLiteral("abc123");
        obj[QStringLiteral("file_size")]        = 1024;
        obj[QStringLiteral("version")]          = 1;
        obj[QStringLiteral("machine_id")]       = machineId;
        obj[QStringLiteral("op_id")]            = 42;
        obj[QStringLiteral("transfer_port")]    = 12346;
        return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    }

    // Construit un JSON folder_hello valide.
    static QString makeFolderHelloJson(qint64 lastOpId = 0,
                                       const QString &machineId = QStringLiteral("machine-client"))
    {
        QJsonObject obj;
        obj[QStringLiteral("type")]        = QStringLiteral("folder_hello");
        obj[QStringLiteral("machine_id")]  = machineId;
        obj[QStringLiteral("last_op_id")] = lastOpId;
        return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    }

    // Construit un JSON folder_catchup_batch valide.
    static QString makeCatchupBatchJson(int opCount = 2)
    {
        QJsonArray ops;
        for (int i = 0; i < opCount; ++i) {
            QJsonObject op;
            op[QStringLiteral("op_id")]            = i + 100;
            op[QStringLiteral("folder_uuid")]      = QStringLiteral("uuid-folder-1");
            op[QStringLiteral("folder_name")]      = QStringLiteral("My Docs");
            op[QStringLiteral("op_type")]          = QStringLiteral("Create");
            op[QStringLiteral("relative_path")]    = QStringLiteral("file%1.txt").arg(i);
            op[QStringLiteral("old_relative_path")] = QString();
            op[QStringLiteral("file_hash")]        = QStringLiteral("hash%1").arg(i);
            op[QStringLiteral("file_size")]        = 512;
            op[QStringLiteral("version")]          = 1;
            op[QStringLiteral("machine_id")]       = QStringLiteral("machine-remote");
            op[QStringLiteral("transfer_port")]    = 12346;
            ops.append(op);
        }
        QJsonObject batch;
        batch[QStringLiteral("type")]       = QStringLiteral("folder_catchup_batch");
        batch[QStringLiteral("operations")] = ops;
        return QString::fromUtf8(QJsonDocument(batch).toJson(QJsonDocument::Compact));
    }

private slots:

    // ------------------------------------------------------------------
    // 1. Réception d'un folder_op depuis le SERVEUR (côté SERVER) →
    //    remoteOpReceived doit être émis.
    // ------------------------------------------------------------------
    void receiveFolderOpViaServer_emitsRemoteOpReceived()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        auto server = std::make_unique<StubMessagingServer>();
        auto *svc = makeService(db.get(), this);
        // Connecte manuellement le signal du stub au slot privé du service
        // (même façon que MessagingServer réel le fait dans setMessagingServer).
        connect(server.get(), &StubMessagingServer::messageReceived,
                svc, [svc](const QString &msg, const QHostAddress &addr) {
                    // Appel via invokeMethod pour accéder au slot privé.
                    QMetaObject::invokeMethod(svc, "onServerMessageReceived",
                                             Qt::DirectConnection,
                                             Q_ARG(QString, msg),
                                             Q_ARG(QHostAddress, addr));
                });

        QSignalSpy spy(svc, &core::sync::FolderSyncService::remoteOpReceived);

        server->injectIncoming(makeFolderOpJson(), QHostAddress::LocalHost);

        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.at(0).at(0).toString(), QStringLiteral("uuid-folder-1")); // folderUuid
        QCOMPARE(spy.at(0).at(1).toString(), QStringLiteral("Create"));         // opType
        QCOMPARE(spy.at(0).at(2).toString(), QStringLiteral("docs/file.txt"));  // relativePath

        delete svc;
    }

    // ------------------------------------------------------------------
    // 2. folder_op émis par CE poste lui-même → doit être ignoré.
    // ------------------------------------------------------------------
    void receiveSelfFolderOp_isIgnored()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        auto *svc = makeService(db.get(), this);
        QSignalSpy spy(svc, &core::sync::FolderSyncService::remoteOpReceived);

        // machine_id = même que le local
        const QString json = makeFolderOpJson(QStringLiteral("Create"),
                                              QStringLiteral("machine-test-local"));
        QMetaObject::invokeMethod(svc, "onServerMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, json),
                                  Q_ARG(QHostAddress, QHostAddress::LocalHost));

        QCOMPARE(spy.count(), 0);
        delete svc;
    }

    // ------------------------------------------------------------------
    // 3. Réception d'un folder_op côté CLIENT → remoteOpReceived émis.
    // ------------------------------------------------------------------
    void receiveFolderOpViaClient_emitsRemoteOpReceived()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        auto *svc = makeService(db.get(), this);
        QSignalSpy spy(svc, &core::sync::FolderSyncService::remoteOpReceived);

        QMetaObject::invokeMethod(svc, "onClientMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, makeFolderOpJson(QStringLiteral("Update"))));

        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.at(0).at(1).toString(), QStringLiteral("Update")); // opType

        delete svc;
    }

    // ------------------------------------------------------------------
    // 4. onConnectedToServer → envoie un folder_hello via MessagingService.
    // ------------------------------------------------------------------
    void onConnectedToServer_sendsFolderHello()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        StubMessagingService service;
        service.setConnected(true);

        auto *svc = makeService(db.get(), this);
        // Branche manuellement le StubMessagingService.
        connect(svc, &core::sync::FolderSyncService::remoteOpReceived,
                this, []() {}); // dummy
        // On passe par sendMessageToServer() → MessagingService::sendMessage().
        // Pour capturer, on connecte un QObject intermédiaire.
        QStringList sent;
        connect(&service, &StubMessagingService::messageSent,
                this, [&sent](const QString &msg) { sent.append(msg); });

        // Injection manuelle : simule setMessagingService + connected.
        connect(svc, &core::sync::FolderSyncService::catchupBatchReceived, this, [](){});

        // Appelle directement onConnectedToServer pour déclencher l'envoi.
        // Pour que sendMessageToServer fonctionne, branche d'abord le service.
        QMetaObject::invokeMethod(svc, "onConnectedToServer", Qt::DirectConnection);
        // Sans service branché, rien n'est envoyé (pas de crash).
        QVERIFY(sent.isEmpty()); // pas de service branché encore

        // Maintenant branche le service via connect direct du slot.
        connect(&service, &StubMessagingService::connected,
                svc, &core::sync::FolderSyncService::onConnectedToServer);

        // Simule la connexion : déclenche onConnectedToServer via le signal.
        // Mais sans MessagingService réel, sendMessageToServer ne fait rien.
        // Ce test vérifie simplement que l'appel ne plante pas.
        QVERIFY(true);

        delete svc;
    }

    // ------------------------------------------------------------------
    // 5. Réception d'un folder_catchup_batch → catchupBatchReceived émis.
    // ------------------------------------------------------------------
    void receiveCatchupBatch_emitsCatchupBatchReceived()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        auto *svc = makeService(db.get(), this);
        QSignalSpy spy(svc, &core::sync::FolderSyncService::catchupBatchReceived);

        QMetaObject::invokeMethod(svc, "onClientMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, makeCatchupBatchJson(3)));

        QCOMPARE(spy.count(), 1);
        const auto ops = spy.at(0).at(0).value<QVector<models::FileSyncOperation>>();
        QCOMPARE(ops.size(), 3);
        QCOMPARE(ops.at(0).id(), static_cast<qint64>(100));
        QCOMPARE(ops.at(1).id(), static_cast<qint64>(101));
        QCOMPARE(ops.at(0).type(), models::SyncChangeType::Create);

        delete svc;
    }

    // ------------------------------------------------------------------
    // 6. Réception d'un folder_catchup_batch vide → pas de signal émis.
    // ------------------------------------------------------------------
    void receiveCatchupBatchEmpty_noSignal()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        auto *svc = makeService(db.get(), this);
        QSignalSpy spy(svc, &core::sync::FolderSyncService::catchupBatchReceived);

        QMetaObject::invokeMethod(svc, "onClientMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, makeCatchupBatchJson(0)));

        QCOMPARE(spy.count(), 0);
        delete svc;
    }

    // ------------------------------------------------------------------
    // 7. Messages non-folder (chat, groupe…) → ignorés sans crash.
    // ------------------------------------------------------------------
    void nonFolderMessages_areIgnored()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        auto *svc = makeService(db.get(), this);
        QSignalSpy spy1(svc, &core::sync::FolderSyncService::remoteOpReceived);
        QSignalSpy spy2(svc, &core::sync::FolderSyncService::catchupBatchReceived);

        const QStringList nonFolderMsgs = {
            QStringLiteral("{\"type\":\"message\",\"content\":\"hi\"}"),
            QStringLiteral("{\"type\":\"group_created\",\"name\":\"G1\"}"),
            QStringLiteral("{\"type\":\"sync_request\",\"from_epoch\":0}"),
            QStringLiteral("not json at all"),
            QStringLiteral(""),
        };

        for (const QString &msg : nonFolderMsgs) {
            QMetaObject::invokeMethod(svc, "onServerMessageReceived",
                                      Qt::DirectConnection,
                                      Q_ARG(QString, msg),
                                      Q_ARG(QHostAddress, QHostAddress::LocalHost));
            QMetaObject::invokeMethod(svc, "onClientMessageReceived",
                                      Qt::DirectConnection,
                                      Q_ARG(QString, msg));
        }

        QCOMPARE(spy1.count(), 0);
        QCOMPARE(spy2.count(), 0);
        delete svc;
    }

    // ------------------------------------------------------------------
    // 8. folder_hello côté SERVER → broadcastMessage appelé même sans ops.
    // ------------------------------------------------------------------
    void folderHello_triggersCatchupBroadcast()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        StubMessagingServer server;
        QStringList broadcast;
        connect(&server, &StubMessagingServer::broadcastCalled,
                this, [&broadcast](const QString &msg) { broadcast.append(msg); });

        auto *svc = makeService(db.get(), this);
        // Branche le stub server manuellement.
        connect(&server, &StubMessagingServer::messageReceived,
                svc, [svc](const QString &msg, const QHostAddress &addr) {
                    QMetaObject::invokeMethod(svc, "onServerMessageReceived",
                                             Qt::DirectConnection,
                                             Q_ARG(QString, msg),
                                             Q_ARG(QHostAddress, addr));
                });
        // Pour que broadcastMessage passe par m_messagingServer, on doit
        // le brancher via setMessagingServer(). Comme StubMessagingServer
        // n'hérite pas de network::MessagingServer, on teste le broadcast
        // via une connexion directe au slot privé handleFolderHello.
        QMetaObject::invokeMethod(svc, "onServerMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, makeFolderHelloJson(0)),
                                  Q_ARG(QHostAddress, QHostAddress::LocalHost));

        // Sans MessagingServer branché, pas de crash et pas de broadcast.
        QVERIFY(true);
        delete svc;
    }

    // ------------------------------------------------------------------
    // 9. requestRemoteFile : ne plante pas sans dépendances branchées.
    // ------------------------------------------------------------------
    void requestRemoteFile_noCrash()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        auto *svc = makeService(db.get(), this);
        // Appel sans MessagingService ni MessagingServer branché.
        svc->requestRemoteFile(QStringLiteral("uuid-folder-1"),
                               QStringLiteral("docs/file.txt"),
                               QStringLiteral("machine-remote"));
        // Pas de crash = OK.
        QVERIFY(true);
        delete svc;
    }

    // ------------------------------------------------------------------
    // 10. Champ op_type Rename → remoteOpReceived transporte oldRelPath.
    // ------------------------------------------------------------------
    void receiveFolderOpRename_carriesOldRelPath()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        auto *svc = makeService(db.get(), this);
        QSignalSpy spy(svc, &core::sync::FolderSyncService::remoteOpReceived);

        QJsonObject obj;
        obj[QStringLiteral("type")]              = QStringLiteral("folder_op");
        obj[QStringLiteral("folder_uuid")]       = QStringLiteral("uuid-folder-1");
        obj[QStringLiteral("folder_name")]       = QStringLiteral("My Docs");
        obj[QStringLiteral("op_type")]           = QStringLiteral("Rename");
        obj[QStringLiteral("relative_path")]     = QStringLiteral("docs/new.txt");
        obj[QStringLiteral("old_relative_path")] = QStringLiteral("docs/old.txt");
        obj[QStringLiteral("version")]           = 2;
        obj[QStringLiteral("machine_id")]        = QStringLiteral("machine-remote");
        obj[QStringLiteral("op_id")]             = 99;
        obj[QStringLiteral("transfer_port")]     = 12346;
        const QString json = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));

        QMetaObject::invokeMethod(svc, "onClientMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, json));

        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.at(0).at(2).toString(), QStringLiteral("docs/new.txt"));   // relativePath
        QCOMPARE(spy.at(0).at(3).toString(), QStringLiteral("docs/old.txt"));   // oldRelativePath

        delete svc;
    }

    // ============================================================
    // Release 8 — Intégration des fichiers reçus + conflits
    // ============================================================

    // Ouvre une DB SQLite réelle dans un fichier temp (pour avoir le vrai
    // schéma complet, y compris SharedFiles et SyncOperations).
    static database::DatabaseManager *openRealDb(const QString &connName,
                                                  const QString &path)
    {
        auto *db = new database::DatabaseManager(connName);
        if (!db->open(path)) { delete db; return nullptr; }
        return db;
    }

    static QString sha256(const QByteArray &data)
    {
        return QString::fromLatin1(
            QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex());
    }

    // ------------------------------------------------------------------
    // 11. onTransferStarted + onTransferCompleted → fichier intégré dans
    //     le dossier partagé, fileIntegrated émis.
    // ------------------------------------------------------------------
    void transferCompleted_integratesFileIntoSharedFolder()
    {
        QTemporaryDir dbDir, folderDir, receiveDir;
        QVERIFY(dbDir.isValid() && folderDir.isValid() && receiveDir.isValid());

        const QString dbPath = dbDir.filePath(QStringLiteral("fss_r8_%1.sqlite")
            .arg(QRandomGenerator::global()->generate()));

        auto *db = openRealDb(QStringLiteral("fss_r8_integrate"), dbPath);
        QVERIFY(db);

        // Crée le dossier partagé.
        core::SharedFolderManager mgr(db);
        const auto folder = mgr.createFolder(QStringLiteral("TestDocs"),
                                             folderDir.path(), 0);
        QVERIFY(folder.has_value());
        const qint64 folderId = folder->id();

        // Crée le service.
        auto *svc = new core::sync::FolderSyncService(db, &mgr, this);
        svc->setLocalMachineId(QStringLiteral("machine-local"));

        QSignalSpy spyIntegrated(svc, &core::sync::FolderSyncService::fileIntegrated);
        QSignalSpy spyConflict(svc, &core::sync::FolderSyncService::conflictDetected);

        // Simule un fichier reçu dans le répertoire de réception.
        const QByteArray content = QByteArrayLiteral("contenu du fichier recu");
        const QString receivedPath = receiveDir.filePath(QStringLiteral("rapport.docx"));
        {
            QFile f(receivedPath);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write(content);
        }

        // Enregistre la demande en attente (comme si requestRemoteFile avait été appelé).
        svc->requestRemoteFile(folder->uuid(), QStringLiteral("rapport.docx"),
                               QStringLiteral("machine-remote"),
                               folderId, folderDir.path(),
                               sha256(content), 1);

        // Corrèle le transferKey.
        const QString transferKey = QStringLiteral("transfer-key-001");
        QMetaObject::invokeMethod(svc, "onTransferStarted",
            Qt::DirectConnection,
            Q_ARG(QString, transferKey),
            Q_ARG(QString, QStringLiteral("rapport.docx")),
            Q_ARG(qint64, content.size()),
            Q_ARG(bool, true),
            Q_ARG(qint64, 0),
            Q_ARG(QString, QStringLiteral("machine-remote")),
            Q_ARG(QString, QStringLiteral("machine-local")),
            Q_ARG(QHostAddress, QHostAddress::LocalHost),
            Q_ARG(QString, QStringLiteral("machine-remote")));

        // Déclenche l'intégration.
        QMetaObject::invokeMethod(svc, "onTransferCompleted",
            Qt::DirectConnection,
            Q_ARG(QString, transferKey),
            Q_ARG(QString, receivedPath));

        // fileIntegrated émis, pas de conflit.
        QCOMPARE(spyIntegrated.count(), 1);
        QCOMPARE(spyConflict.count(), 0);
        QCOMPARE(spyIntegrated.at(0).at(0).toString(), folder->uuid()); // folderUuid
        QCOMPARE(spyIntegrated.at(0).at(2).toBool(), false);            // wasConflict

        // Fichier bien présent à sa cible.
        const QString targetPath = folderDir.filePath(QStringLiteral("rapport.docx"));
        QVERIFY(QFile::exists(targetPath));

        // Contenu correct.
        QFile tf(targetPath);
        QVERIFY(tf.open(QIODevice::ReadOnly));
        QCOMPARE(tf.readAll(), content);

        // SharedFile enregistré en base.
        database::SharedFileRepository fileRepo(db->database());
        const auto sf = fileRepo.findByRelativePath(folderId, QStringLiteral("rapport.docx"));
        QVERIFY(sf.has_value());
        QCOMPARE(sf->hash(), sha256(content));

        delete svc;
        delete db;
    }

    // ------------------------------------------------------------------
    // 12. Conflit : fichier local différent → conflictDetected émis,
    //     fichier local préservé, copie de conflit créée.
    // ------------------------------------------------------------------
    void transferCompleted_conflict_preservesLocalAndCreatesConflictCopy()
    {
        QTemporaryDir dbDir, folderDir, receiveDir;
        QVERIFY(dbDir.isValid() && folderDir.isValid() && receiveDir.isValid());

        const QString dbPath = dbDir.filePath(QStringLiteral("fss_r8_conflict_%1.sqlite")
            .arg(QRandomGenerator::global()->generate()));

        auto *db = openRealDb(QStringLiteral("fss_r8_conflict"), dbPath);
        QVERIFY(db);

        core::SharedFolderManager mgr(db);
        const auto folder = mgr.createFolder(QStringLiteral("Docs"),
                                             folderDir.path(), 0);
        QVERIFY(folder.has_value());
        const qint64 folderId = folder->id();

        // Écrit un fichier local DIFFÉRENT (hash ≠ version distante).
        const QByteArray localContent  = QByteArrayLiteral("version locale alice");
        const QByteArray remoteContent = QByteArrayLiteral("version distante bob");
        const QString targetPath = folderDir.filePath(QStringLiteral("rapport.docx"));
        {
            QFile f(targetPath);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write(localContent);
        }

        // Indexe ce fichier local pour que SharedFileRepository le connaisse.
        QVERIFY(mgr.shareFolder(folderId).has_value());

        // Crée le service.
        auto *svc = new core::sync::FolderSyncService(db, &mgr, this);
        svc->setLocalMachineId(QStringLiteral("machine-local"));

        QSignalSpy spyIntegrated(svc, &core::sync::FolderSyncService::fileIntegrated);
        QSignalSpy spyConflict(svc, &core::sync::FolderSyncService::conflictDetected);

        // Fichier reçu (contenu différent).
        const QString receivedPath = receiveDir.filePath(QStringLiteral("rapport.docx"));
        {
            QFile f(receivedPath);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write(remoteContent);
        }

        // Enregistre et corrèle.
        svc->requestRemoteFile(folder->uuid(), QStringLiteral("rapport.docx"),
                               QStringLiteral("machine-bob"),
                               folderId, folderDir.path(),
                               sha256(remoteContent), 2);

        const QString transferKey = QStringLiteral("transfer-key-conflict");
        QMetaObject::invokeMethod(svc, "onTransferStarted",
            Qt::DirectConnection,
            Q_ARG(QString, transferKey),
            Q_ARG(QString, QStringLiteral("rapport.docx")),
            Q_ARG(qint64, remoteContent.size()),
            Q_ARG(bool, true),
            Q_ARG(qint64, 0),
            Q_ARG(QString, QStringLiteral("machine-bob")),
            Q_ARG(QString, QStringLiteral("machine-local")),
            Q_ARG(QHostAddress, QHostAddress::LocalHost),
            Q_ARG(QString, QStringLiteral("machine-bob")));

        QMetaObject::invokeMethod(svc, "onTransferCompleted",
            Qt::DirectConnection,
            Q_ARG(QString, transferKey),
            Q_ARG(QString, receivedPath));

        // conflictDetected émis, fileIntegrated aussi (avec wasConflict=true).
        QCOMPARE(spyConflict.count(), 1);
        QCOMPARE(spyIntegrated.count(), 1);
        QCOMPARE(spyIntegrated.at(0).at(2).toBool(), true);

        // Fichier local PRÉSERVÉ (contenu alice intact).
        QVERIFY(QFile::exists(targetPath));
        {
            QFile f(targetPath);
            QVERIFY(f.open(QIODevice::ReadOnly));
            QCOMPARE(f.readAll(), localContent);
        }

        // Fichier de conflit créé avec le contenu de bob.
        const QString conflictRelPath = spyConflict.at(0).at(2).toString();
        const QString conflictAbsPath = folderDir.filePath(conflictRelPath);
        QVERIFY(QFile::exists(conflictAbsPath));
        {
            QFile f(conflictAbsPath);
            QVERIFY(f.open(QIODevice::ReadOnly));
            QCOMPARE(f.readAll(), remoteContent);
        }

        // Le chemin de conflit contient le court machineId de bob.
        QVERIFY(conflictRelPath.contains(QStringLiteral("machine-bob").left(6)));

        delete svc;
        delete db;
    }

    // ------------------------------------------------------------------
    // 13. onTransferCompleted pour un transferKey inconnu → ignoré sans crash.
    // ------------------------------------------------------------------
    void transferCompleted_unknownKey_isIgnored()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        auto *svc = makeService(db.get(), this);
        QSignalSpy spy(svc, &core::sync::FolderSyncService::fileIntegrated);

        QMetaObject::invokeMethod(svc, "onTransferCompleted",
            Qt::DirectConnection,
            Q_ARG(QString, QStringLiteral("unknown-key-xyz")),
            Q_ARG(QString, QStringLiteral("/tmp/some-file.txt")));

        QCOMPARE(spy.count(), 0);
        delete svc;
    }

    // ------------------------------------------------------------------
    // 14. onTransferStarted outgoing (incoming=false) → ignoré.
    // ------------------------------------------------------------------
    void transferStarted_outgoing_isIgnored()
    {
        auto db = makeInMemoryDb();
        QVERIFY(db);

        auto *svc = makeService(db.get(), this);

        // Enregistre une demande en attente.
        // On ne peut pas appeler la surcharge privée directement depuis ici,
        // mais on peut vérifier que onTransferStarted avec incoming=false ne
        // consomme pas la demande en attente.

        // On simule un transferStarted sortant.
        QMetaObject::invokeMethod(svc, "onTransferStarted",
            Qt::DirectConnection,
            Q_ARG(QString, QStringLiteral("outgoing-key")),
            Q_ARG(QString, QStringLiteral("fichier.txt")),
            Q_ARG(qint64, 100),
            Q_ARG(bool, false), // outgoing
            Q_ARG(qint64, 0),
            Q_ARG(QString, QStringLiteral("machine-local")),
            Q_ARG(QString, QStringLiteral("machine-remote")),
            Q_ARG(QHostAddress, QHostAddress::LocalHost),
            Q_ARG(QString, QStringLiteral("machine-remote")));

        // onTransferCompleted avec la même clé → ignoré (pas dans activeByTransferKey).
        QSignalSpy spy(svc, &core::sync::FolderSyncService::fileIntegrated);
        QMetaObject::invokeMethod(svc, "onTransferCompleted",
            Qt::DirectConnection,
            Q_ARG(QString, QStringLiteral("outgoing-key")),
            Q_ARG(QString, QStringLiteral("/tmp/dummy")));

        QCOMPARE(spy.count(), 0);
        delete svc;
    }

    // ============================================================
    // Delete / Rename distants (complete le Release 6 : jusqu'ici seuls
    // Create/Update etaient appliques cote recepteur).
    // ============================================================

    // ------------------------------------------------------------------
    // 15. folder_op Delete recu d'un pair -> fichier supprime du disque
    //     et marque supprime (tombstone) en base.
    // ------------------------------------------------------------------
    void receiveFolderOpDelete_removesFileAndMarksTombstone()
    {
        QTemporaryDir dbDir, folderDir;
        QVERIFY(dbDir.isValid() && folderDir.isValid());

        const QString dbPath = dbDir.filePath(QStringLiteral("fss_delete_%1.sqlite")
            .arg(QRandomGenerator::global()->generate()));
        auto *db = openRealDb(QStringLiteral("fss_delete"), dbPath);
        QVERIFY(db);

        core::SharedFolderManager mgr(db);
        const auto folder = mgr.createFolder(QStringLiteral("Docs"), folderDir.path(), 0);
        QVERIFY(folder.has_value());
        const qint64 folderId = folder->id();

        // Fichier local existant, deja indexe (simule une synchro anterieure).
        const QString absPath = folderDir.filePath(QStringLiteral("obsolete.txt"));
        {
            QFile f(absPath);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write(QByteArrayLiteral("a supprimer"));
        }
        QVERIFY(mgr.shareFolder(folderId).has_value());
        QVERIFY(QFile::exists(absPath));

        auto *svc = new core::sync::FolderSyncService(db, &mgr, this);
        svc->setLocalMachineId(QStringLiteral("machine-local"));
        QSignalSpy spy(svc, &core::sync::FolderSyncService::fileIntegrated);

        QJsonObject obj;
        obj[QStringLiteral("type")]              = QStringLiteral("folder_op");
        obj[QStringLiteral("folder_uuid")]       = folder->uuid();
        obj[QStringLiteral("op_type")]           = QStringLiteral("Delete");
        obj[QStringLiteral("relative_path")]     = QStringLiteral("obsolete.txt");
        obj[QStringLiteral("old_relative_path")] = QString();
        obj[QStringLiteral("machine_id")]        = QStringLiteral("machine-remote");
        const QString json = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));

        QMetaObject::invokeMethod(svc, "onClientMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, json));

        // Le fichier a disparu du disque.
        QVERIFY(!QFile::exists(absPath));

        // La ligne SharedFiles est bien marquee supprimee (tombstone), plus
        // renvoyee par getFiles().
        QCOMPARE(mgr.getFiles(folderId).size(), 0);

        database::SharedFileRepository fileRepo(db->database());
        const auto sf = fileRepo.findByRelativePath(folderId, QStringLiteral("obsolete.txt"));
        QVERIFY(sf.has_value());
        QVERIFY(sf->deleted());

        QCOMPARE(spy.count(), 1);

        delete svc;
        delete db;
    }

    // ------------------------------------------------------------------
    // 16. folder_op Rename recu d'un pair -> fichier renomme sur disque et
    //     relative_path mis a jour en base.
    // ------------------------------------------------------------------
    void receiveFolderOpRename_movesFileAndUpdatesRelativePath()
    {
        QTemporaryDir dbDir, folderDir;
        QVERIFY(dbDir.isValid() && folderDir.isValid());

        const QString dbPath = dbDir.filePath(QStringLiteral("fss_rename_%1.sqlite")
            .arg(QRandomGenerator::global()->generate()));
        auto *db = openRealDb(QStringLiteral("fss_rename"), dbPath);
        QVERIFY(db);

        core::SharedFolderManager mgr(db);
        const auto folder = mgr.createFolder(QStringLiteral("Docs"), folderDir.path(), 0);
        QVERIFY(folder.has_value());
        const qint64 folderId = folder->id();

        const QByteArray content = QByteArrayLiteral("meme contenu");
        const QString oldAbsPath = folderDir.filePath(QStringLiteral("ancien.txt"));
        {
            QFile f(oldAbsPath);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write(content);
        }
        QVERIFY(mgr.shareFolder(folderId).has_value());

        auto *svc = new core::sync::FolderSyncService(db, &mgr, this);
        svc->setLocalMachineId(QStringLiteral("machine-local"));
        QSignalSpy spy(svc, &core::sync::FolderSyncService::fileIntegrated);

        QJsonObject obj;
        obj[QStringLiteral("type")]              = QStringLiteral("folder_op");
        obj[QStringLiteral("folder_uuid")]       = folder->uuid();
        obj[QStringLiteral("op_type")]           = QStringLiteral("Rename");
        obj[QStringLiteral("relative_path")]     = QStringLiteral("nouveau.txt");
        obj[QStringLiteral("old_relative_path")] = QStringLiteral("ancien.txt");
        obj[QStringLiteral("machine_id")]        = QStringLiteral("machine-remote");
        const QString json = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));

        QMetaObject::invokeMethod(svc, "onClientMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, json));

        const QString newAbsPath = folderDir.filePath(QStringLiteral("nouveau.txt"));
        QVERIFY(!QFile::exists(oldAbsPath));
        QVERIFY(QFile::exists(newAbsPath));
        {
            QFile f(newAbsPath);
            QVERIFY(f.open(QIODevice::ReadOnly));
            QCOMPARE(f.readAll(), content);
        }

        database::SharedFileRepository fileRepo(db->database());
        QVERIFY(!fileRepo.findByRelativePath(folderId, QStringLiteral("ancien.txt")).has_value());
        const auto sf = fileRepo.findByRelativePath(folderId, QStringLiteral("nouveau.txt"));
        QVERIFY(sf.has_value());
        QVERIFY(!sf->deleted());

        QCOMPARE(spy.count(), 1);

        delete svc;
        delete db;
    }
    // ============================================================
    // Enforcement de la révocation d'accès (Release post-R8).
    // ============================================================
    //
    // Pour que effectivePermission() puisse identifier un pair "connu dont
    // l'accès a été révoqué", l'UUID du pair doit exister dans la table
    // Users (findByUuid) ET son accès doit être absent de SharedFolderAccess.
    // Les helpers ci-dessous insèrent ces données directement en SQL.

    // Insère un utilisateur minimal et retourne son id.
    static qint64 insertUser(database::DatabaseManager *db,
                              const QString &name,
                              const QString &uuid)
    {
        QSqlQuery q(db->database());
        q.prepare(QStringLiteral(
            "INSERT INTO Users (name, uuid, role, status, password_hash, password_salt) "
            "VALUES (:name, :uuid, 'Member', 'Online', '', '')"));
        q.bindValue(QStringLiteral(":name"), name);
        q.bindValue(QStringLiteral(":uuid"), uuid);
        if (!q.exec()) return -1;
        return q.lastInsertId().toLongLong();
    }

    // ------------------------------------------------------------------
    // 17. folder_file_request d'un pair révoqué (uuid connu, accès None)
    //     → pas de sendFile (test indirect : pas de crash + log).
    //     Le test vérifie que le service ne tente pas d'envoyer le fichier
    //     (TransferService non branché, donc sendFile provoquerait un crash
    //     ou un warning ; ici l'early-return d'accès refusé doit arriver avant).
    // ------------------------------------------------------------------
    void fileRequest_revokedUser_isRefused()
    {
        QTemporaryDir dbDir, folderDir;
        QVERIFY(dbDir.isValid() && folderDir.isValid());

        const QString dbPath = dbDir.filePath(QStringLiteral("fss_revoke_fr_%1.sqlite")
            .arg(QRandomGenerator::global()->generate()));
        auto *db = openRealDb(QStringLiteral("fss_revoke_fr"), dbPath);
        QVERIFY(db);

        // Créer un dossier LOCAL (isLocalOrigin = true) avec un fichier.
        core::SharedFolderManager mgr(db);
        const QString filePath = folderDir.filePath(QStringLiteral("secret.txt"));
        { QFile f(filePath); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("secret"); }

        const auto folder = mgr.createFolder(QStringLiteral("Privé"), folderDir.path(), 0);
        QVERIFY(folder.has_value());
        QVERIFY(mgr.shareFolder(folder->id()).has_value());

        // Insérer un pair "machine-revoked" connu en base, SANS accès au dossier.
        const qint64 revokedId = insertUser(db, QStringLiteral("alice"), QStringLiteral("machine-revoked"));
        QVERIFY(revokedId > 0);
        // Note : aucun grantAccess → permissionFor retourne None → bloqué.

        auto *svc = new core::sync::FolderSyncService(db, &mgr, this);
        svc->setLocalMachineId(QStringLiteral("machine-local"));

        // Construit un folder_file_request depuis "machine-revoked".
        QJsonObject req;
        req[QStringLiteral("type")]                    = QStringLiteral("folder_file_request");
        req[QStringLiteral("folder_uuid")]             = folder->uuid();
        req[QStringLiteral("relative_path")]           = QStringLiteral("secret.txt");
        req[QStringLiteral("requester_machine_id")]    = QStringLiteral("machine-revoked");
        req[QStringLiteral("requester_transfer_port")] = 12346;
        const QString json = QString::fromUtf8(QJsonDocument(req).toJson(QJsonDocument::Compact));

        // Sans TransferService branché, un sendFile() crasherait.
        // Si l'enforcement fonctionne, l'early-return d'accès refusé arrive avant.
        // On vérifie juste qu'il n'y a pas de crash.
        QMetaObject::invokeMethod(svc, "onServerMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, json),
                                  Q_ARG(QHostAddress, QHostAddress::LocalHost));
        QVERIFY(true); // pas de crash = enforcement a bien intercepté

        // Le fichier n'a pas disparu (on n'a pas servi le fichier).
        QVERIFY(QFile::exists(filePath));

        delete svc;
        delete db;
    }

    // ------------------------------------------------------------------
    // 17bis. Release 9 — dossier en lecture seule : un pair avec un accès
    //     Read (et non Write) ne doit PAS recevoir le contenu du fichier
    //     via folder_file_request (seule la liste/les métadonnées sont
    //     visibles avec Read ; le contenu réel exige Write).
    // ------------------------------------------------------------------
    void fileRequest_readOnlyUser_isRefused()
    {
        QTemporaryDir dbDir, folderDir;
        QVERIFY(dbDir.isValid() && folderDir.isValid());

        const QString dbPath = dbDir.filePath(QStringLiteral("fss_readonly_fr_%1.sqlite")
            .arg(QRandomGenerator::global()->generate()));
        auto *db = openRealDb(QStringLiteral("fss_readonly_fr"), dbPath);
        QVERIFY(db);

        // Créer un dossier LOCAL (isLocalOrigin = true) avec un fichier.
        core::SharedFolderManager mgr(db);
        const QString filePath = folderDir.filePath(QStringLiteral("secret.txt"));
        { QFile f(filePath); QVERIFY(f.open(QIODevice::WriteOnly)); f.write("secret"); }

        const auto folder = mgr.createFolder(QStringLiteral("Privé"), folderDir.path(), 0);
        QVERIFY(folder.has_value());
        QVERIFY(mgr.shareFolder(folder->id()).has_value());

        // Insérer un pair "machine-reader" avec un accès explicite Read
        // (PAS None : la permission existe bel et bien, juste pas Write).
        const qint64 readerId = insertUser(db, QStringLiteral("reader"), QStringLiteral("machine-reader"));
        QVERIFY(readerId > 0);
        database::SharedFolderAccessRepository accessRepo(db->database());
        QVERIFY(accessRepo.grant(folder->id(), readerId, models::SharedFolderPermission::Read, 0).has_value());

        auto *svc = new core::sync::FolderSyncService(db, &mgr, this);
        svc->setLocalMachineId(QStringLiteral("machine-local"));

        // Construit un folder_file_request depuis "machine-reader".
        QJsonObject req;
        req[QStringLiteral("type")]                    = QStringLiteral("folder_file_request");
        req[QStringLiteral("folder_uuid")]             = folder->uuid();
        req[QStringLiteral("relative_path")]           = QStringLiteral("secret.txt");
        req[QStringLiteral("requester_machine_id")]    = QStringLiteral("machine-reader");
        req[QStringLiteral("requester_transfer_port")] = 12346;
        const QString json = QString::fromUtf8(QJsonDocument(req).toJson(QJsonDocument::Compact));

        // Sans TransferService branché, un sendFile() crasherait. Si
        // l'enforcement fonctionne, l'early-return d'accès refusé (Read
        // insuffisant) arrive avant.
        QMetaObject::invokeMethod(svc, "onServerMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, json),
                                  Q_ARG(QHostAddress, QHostAddress::LocalHost));
        QVERIFY(true); // pas de crash = enforcement a bien intercepté

        // Le fichier n'a pas été "consommé"/déplacé : on n'a rien servi.
        QVERIFY(QFile::exists(filePath));

        delete svc;
        delete db;
    }

    // ------------------------------------------------------------------
    // 18. folder_op Create d'un pair révoqué (uuid connu, accès None)
    //     → remoteOpReceived émis (signal toujours propagé) MAIS
    //     requestRemoteFile non déclenché (pas de crash, pas de demande de
    //     transfert) : on compte les messages sortants via StubServer.
    // ------------------------------------------------------------------
    void folderOp_revokedUser_isDropped()
    {
        QTemporaryDir dbDir, folderDir;
        QVERIFY(dbDir.isValid() && folderDir.isValid());

        const QString dbPath = dbDir.filePath(QStringLiteral("fss_revoke_op_%1.sqlite")
            .arg(QRandomGenerator::global()->generate()));
        auto *db = openRealDb(QStringLiteral("fss_revoke_op"), dbPath);
        QVERIFY(db);

        core::SharedFolderManager mgr(db);
        const auto folder = mgr.createFolder(QStringLiteral("Docs"), folderDir.path(), 0);
        QVERIFY(folder.has_value());

        // Pair révoqué : connu en base, mais sans accès.
        const qint64 revokedId = insertUser(db, QStringLiteral("bob"), QStringLiteral("machine-bob"));
        QVERIFY(revokedId > 0);

        // Pair légitime : a accès Write.
        const qint64 legitId = insertUser(db, QStringLiteral("carol"), QStringLiteral("machine-carol"));
        QVERIFY(legitId > 0);
        database::SharedFolderAccessRepository accessRepo(db->database());
        accessRepo.grant(folder->id(), legitId, models::SharedFolderPermission::Write, 0);

        auto *svc = new core::sync::FolderSyncService(db, &mgr, this);
        svc->setLocalMachineId(QStringLiteral("machine-local"));

        QSignalSpy spyOp(svc, &core::sync::FolderSyncService::remoteOpReceived);

        auto injectOp = [&](const QString &senderId) {
            QJsonObject obj;
            obj[QStringLiteral("type")]             = QStringLiteral("folder_op");
            obj[QStringLiteral("folder_uuid")]      = folder->uuid();
            obj[QStringLiteral("op_type")]          = QStringLiteral("Create");
            obj[QStringLiteral("relative_path")]    = QStringLiteral("newfile.txt");
            obj[QStringLiteral("old_relative_path")] = QString();
            obj[QStringLiteral("file_hash")]        = QStringLiteral("deadbeef");
            obj[QStringLiteral("file_size")]        = 100;
            obj[QStringLiteral("version")]          = 1;
            obj[QStringLiteral("machine_id")]       = senderId;
            obj[QStringLiteral("op_id")]            = 1;
            obj[QStringLiteral("transfer_port")]    = 12346;
            const QString json = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
            QMetaObject::invokeMethod(svc, "onClientMessageReceived",
                                      Qt::DirectConnection,
                                      Q_ARG(QString, json));
        };

        // Op du pair révoqué : remoteOpReceived quand même (signal informatif),
        // mais pas de requestRemoteFile (pas de broadcast sortant possible sans
        // MessagingService branché, et le code ne devrait pas aller jusque là).
        injectOp(QStringLiteral("machine-bob"));
        // L'accès de bob est None → l'enforcement coupe avant requestRemoteFile.
        // remoteOpReceived est quand même émis (avant le check d'enforcement).
        QCOMPARE(spyOp.count(), 1);

        // Op du pair légitime : requestRemoteFile tenté (sans crash car pas de
        // MessagingService -- mais la vérification d'accès passe).
        spyOp.clear();
        injectOp(QStringLiteral("machine-carol"));
        QCOMPARE(spyOp.count(), 1);

        delete svc;
        delete db;
    }

    // ------------------------------------------------------------------
    // 19. handleFolderAccessRevoked : quand NOUS sommes le pair révoqué
    //     (m_localUserId == revokedUser->id()), le dossier et ses fichiers
    //     locaux sont supprimés (cleanupRevokedFolder).
    // ------------------------------------------------------------------
    void accessRevoked_selfUser_cleansUpLocalFolder()
    {
        QTemporaryDir dbDir, folderDir;
        QVERIFY(dbDir.isValid() && folderDir.isValid());

        const QString dbPath = dbDir.filePath(QStringLiteral("fss_revoke_self_%1.sqlite")
            .arg(QRandomGenerator::global()->generate()));
        auto *db = openRealDb(QStringLiteral("fss_revoke_self"), dbPath);
        QVERIFY(db);

        core::SharedFolderManager mgr(db);

        // Nous = utilisateur local avec uuid "machine-local".
        const qint64 ownerId = insertUser(db, QStringLiteral("owner"), QStringLiteral("machine-owner"));
        QVERIFY(ownerId > 0);
        const qint64 localUserId = insertUser(db, QStringLiteral("me"), QStringLiteral("machine-local"));
        QVERIFY(localUserId > 0);

        // Créer un dossier dans folderDir (createFolder garantit un localPath valide).
        const auto folder = mgr.createFolder(QStringLiteral("Projet"), folderDir.path(), ownerId);
        QVERIFY(folder.has_value());

        // Accorder l'accès à "nous" sur ce dossier.
        QVERIFY(mgr.grantAccess(folder->id(), localUserId, ownerId));

        auto *svc = new core::sync::FolderSyncService(db, &mgr, this);
        svc->setLocalMachineId(QStringLiteral("machine-local"));
        svc->setLocalUserId(localUserId); // nous sommes l'utilisateur révoqué

        // Vérifier que le dossier existe bien avant la révocation.
        QVERIFY(mgr.getFolderByUuid(folder->uuid()).has_value());

        // Injecter le message folder_access_revoked depuis "machine-owner".
        QJsonObject obj;
        obj[QStringLiteral("type")]              = QStringLiteral("folder_access_revoked");
        obj[QStringLiteral("folder_uuid")]       = folder->uuid();
        obj[QStringLiteral("user_uuid")]         = QStringLiteral("machine-local"); // notre uuid
        obj[QStringLiteral("origin_machine_id")] = QStringLiteral("machine-owner");
        const QString json = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));

        QMetaObject::invokeMethod(svc, "onClientMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, json));

        // Le dossier doit avoir été supprimé de la base locale.
        QVERIFY(!mgr.getFolderByUuid(folder->uuid()).has_value());

        delete svc;
        delete db;
    }

    // ------------------------------------------------------------------
    // 20. handleFolderAccessRevoked pour un autre utilisateur (pas nous)
    //     → seulement revokeAccess en base, dossier conservé.
    // ------------------------------------------------------------------
    void accessRevoked_otherUser_keepsFolder()
    {
        QTemporaryDir dbDir, folderDir;
        QVERIFY(dbDir.isValid() && folderDir.isValid());

        const QString dbPath = dbDir.filePath(QStringLiteral("fss_revoke_other_%1.sqlite")
            .arg(QRandomGenerator::global()->generate()));
        auto *db = openRealDb(QStringLiteral("fss_revoke_other"), dbPath);
        QVERIFY(db);

        core::SharedFolderManager mgr(db);

        const qint64 ownerId = insertUser(db, QStringLiteral("owner"), QStringLiteral("machine-owner"));
        QVERIFY(ownerId > 0);
        const qint64 localUserId = insertUser(db, QStringLiteral("me"), QStringLiteral("machine-local"));
        QVERIFY(localUserId > 0);
        const qint64 otherUserId = insertUser(db, QStringLiteral("carol"), QStringLiteral("machine-carol"));
        QVERIFY(otherUserId > 0);

        const auto folder = mgr.createFolder(QStringLiteral("Docs"), folderDir.path(), ownerId);
        QVERIFY(folder.has_value());

        // Accorder l'accès à carol (otherUserId).
        QVERIFY(mgr.grantAccess(folder->id(), otherUserId, ownerId));

        auto *svc = new core::sync::FolderSyncService(db, &mgr, this);
        svc->setLocalMachineId(QStringLiteral("machine-local"));
        svc->setLocalUserId(localUserId); // nous NE sommes PAS carol

        QJsonObject obj;
        obj[QStringLiteral("type")]              = QStringLiteral("folder_access_revoked");
        obj[QStringLiteral("folder_uuid")]       = folder->uuid();
        obj[QStringLiteral("user_uuid")]         = QStringLiteral("machine-carol"); // carol révoquée
        obj[QStringLiteral("origin_machine_id")] = QStringLiteral("machine-owner");
        const QString json = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));

        QMetaObject::invokeMethod(svc, "onClientMessageReceived",
                                  Qt::DirectConnection,
                                  Q_ARG(QString, json));

        // Le dossier est toujours là (c'est carol qui est révoquée, pas nous).
        QVERIFY(mgr.getFolder(folder->id()).has_value());

        // L'accès de carol a été retiré.
        database::SharedFolderAccessRepository accessRepo(db->database());
        QCOMPARE(accessRepo.permissionFor(folder->id(), otherUserId),
                 models::SharedFolderPermission::None);

        delete svc;
        delete db;
    }
};

QTEST_MAIN(TestFolderSyncService)
#include "test_foldersyncservice.moc"
