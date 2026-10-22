// Partage de dossiers de bout en bout : deux instances completes, la
// proprietaire alice sur le serveur S, bob sur le client B (vrai serveur de
// messagerie, vrais transferts P2P, vrai FolderWatcher).
//
// Chaque scenario couvre un defaut constate a l'audit (2026-10-22) :
//  - un membre en lecture seule ne recevait jamais les fichiers ;
//  - chaque mise a jour creait une copie de conflit (l'original restait perime) ;
//  - le dossier choisi par un membre n'etait pas surveille (ses ajouts ne partaient pas) ;
//  - une suppression distante effacait une modification locale (desormais la
//    modification l'emporte, sur tous les postes) ;
//  - noms differant par la casse seulement, renommage de casse ;
//  - arret du partage / depart d'un membre non propages.
#include <QtTest>
#include <QDir>
#include <QFile>
#include <QHostAddress>
#include <QRandomGenerator>
#include <QTemporaryDir>

#include "Application.h"
#include "PermissionManager.h"
#include "SharedFolderManager.h"
#include "UserManager.h"
#include "Election/ElectionService.h"
#include "Messaging/MessagingService.h"
#include "Security/SecurityService.h"
#include "Sync/FolderSyncService.h"

class TestDossiersE2E : public QObject
{
    Q_OBJECT

    struct Poste {
        std::unique_ptr<Application> app;
        QString name;
        QString role;
        quint16 port = 0;
        int priority = -1;
        QString fingerprint;
        bool connectedTo(quint16 serverPort) const
        {
            return app->messagingService()->isConnected() && app->messagingService()->peerPort() == serverPort;
        }
    };

    QTemporaryDir m_dir;
    quint16 m_base = 0;
    quint16 m_electionPort = 0;

    void boot(Poste &p)
    {
        p.app = std::make_unique<Application>();
        p.app->setDiscoveryPort(static_cast<quint16>(p.port + 5));
        p.app->initialize(p.port, m_dir.filePath(p.name + QStringLiteral(".db")), p.role, p.priority, m_electionPort);
        p.app->electionService()->setHeartbeatIntervalMs(300);
        p.app->electionService()->setHeartbeatTimeoutMs(2000);
        p.app->electionService()->setElectionWindowMs(400);
        p.fingerprint = p.app->securityService()->identity().fingerprintSha256.toLower();
    }
    static int userId(Application &app, const QString &name)
    {
        for (const auto &u : app.userManager()->allUsers())
            if (u.name() == name) return u.id();
        return -1;
    }
    static void write(const QString &path, const QByteArray &content)
    {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
        f.write(content);
    }
    static QByteArray read(const QString &path)
    {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
    }
    static QStringList conflictCopies(const QString &dir)
    {
        return QDir(dir).entryList({QStringLiteral("* (conflit *)*")}, QDir::Files);
    }

    // Reseau S (alice, proprietaire) + B (bob) ; dossier d'alice avec un fichier,
    // partage a bob (ecriture ou lecture) ; bob l'accepte dans un dossier choisi.
    struct Setup { Poste s; Poste b; qint64 folderId = 0; QString uuid; QString ownerDir; QString bobDir; };
    void start(Setup &x, const QString &prefix, int offset, bool allowWrite)
    {
        m_electionPort = static_cast<quint16>(m_base + offset + 9);
        x.s = Poste{nullptr, prefix + QStringLiteral("-serveur"), QStringLiteral("SERVER"), static_cast<quint16>(m_base + offset), -1, {}};
        x.b = Poste{nullptr, prefix + QStringLiteral("-b"), QStringLiteral("CLIENT"), static_cast<quint16>(m_base + offset + 10), 10, {}};
        boot(x.s);
        const auto admin = x.s.app->userManager()->createUser(QStringLiteral("alice"), QStringLiteral("motdepasse"));
        QVERIFY(admin.has_value());
        QVERIFY(x.s.app->userManager()->createUser(QStringLiteral("bob"), QStringLiteral("motdepasse")).has_value());
        QVERIFY(x.s.app->userManager()->login(QStringLiteral("alice"), QStringLiteral("motdepasse")));
        boot(x.b);
        QVERIFY(x.s.app->permissionManager()->authorizeMachineByCertificate(
            x.b.fingerprint, x.b.name, x.b.name.toUpper(), QStringLiteral("127.0.0.1"), admin->id(), QStringLiteral("essai")));
        QVERIFY(x.b.app->permissionManager()->approveServerCertificate(x.s.fingerprint, QStringLiteral("127.0.0.1")));
        QTRY_VERIFY_WITH_TIMEOUT(x.b.connectedTo(x.s.port), 20000);
        QTRY_VERIFY_WITH_TIMEOUT(userId(*x.b.app, QStringLiteral("alice")) > 0, 10000);
        QVERIFY(x.b.app->userManager()->login(QStringLiteral("bob"), QStringLiteral("motdepasse")));
        QTest::qWait(800);

        x.ownerDir = m_dir.filePath(prefix + QStringLiteral("-alice"));
        x.bobDir = m_dir.filePath(prefix + QStringLiteral("-bob"));
        QVERIFY(QDir().mkpath(x.ownerDir) && QDir().mkpath(x.bobDir));
        write(x.ownerDir + QStringLiteral("/rapport.txt"), "version 1");
        const auto folder = x.s.app->sharedFolderManager()->createFolder(QStringLiteral("Projet"), x.ownerDir, admin->id());
        QVERIFY(folder.has_value());
        x.uuid = folder->uuid();
        QTest::qWait(500);
        QVERIFY(x.s.app->sharedFolderManager()->grantAccess(folder->id(), userId(*x.s.app, QStringLiteral("bob")), admin->id(),
                                                            allowWrite ? models::SharedFolderPermission::Write
                                                                       : models::SharedFolderPermission::Read));
        QTRY_VERIFY_WITH_TIMEOUT(x.b.app->sharedFolderManager()->getFolderByUuid(x.uuid).has_value(), 10000);
        x.folderId = x.b.app->sharedFolderManager()->getFolderByUuid(x.uuid)->id();
        // Acceptation dans un dossier choisi : le chemin de l'interface
        // (SharedFolderContext::setFolderLocalPath), la demande du contenu
        // suit le signal folderLocalPathProvisioned.
        QVERIFY(x.b.app->sharedFolderManager()->updateFolderLocalPath(x.folderId, x.bobDir));
        QTRY_VERIFY_WITH_TIMEOUT(read(x.bobDir + QStringLiteral("/rapport.txt")) == "version 1", 15000);
        QTest::qWait(1500); // fin de la fenetre de suppression du watcher apres reception
    }

private slots:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        m_base = static_cast<quint16>(43000 + QRandomGenerator::global()->bounded(800) * 10);
    }

    // Un membre en lecture seule recoit le contenu (le serveur de fichiers
    // refusait toute demande d'un membre sans droit d'ecriture) et les mises
    // a jour ; ses propres modifications ne partent pas.
    void readOnlyMemberReceivesFiles()
    {
        Setup x;
        start(x, QStringLiteral("lecture"), 0, false);

        write(x.ownerDir + QStringLiteral("/rapport.txt"), "version 2");
        QTRY_VERIFY_WITH_TIMEOUT(read(x.bobDir + QStringLiteral("/rapport.txt")) == "version 2", 15000);
        QVERIFY(conflictCopies(x.bobDir).isEmpty());

        write(x.bobDir + QStringLiteral("/note-lecteur.txt"), "ne doit pas partir");
        QTest::qWait(5000);
        QVERIFY(!QFile::exists(x.ownerDir + QStringLiteral("/note-lecteur.txt")));

        // Fichier d'alice dont le nom ne differe que par la casse d'un fichier
        // de bob (cas d'un poste Linux) : non ecrit, le fichier de bob est intact
        // et un avis est emis.
        QSignalSpy notices(x.b.app->folderSyncService(), &core::sync::FolderSyncService::syncNotice);
        write(x.bobDir + QStringLiteral("/notes.txt"), "notes de bob");
        write(x.ownerDir + QStringLiteral("/Notes.txt"), "notes d'alice");
        QTRY_VERIFY_WITH_TIMEOUT(!notices.isEmpty(), 15000);
        QCOMPARE(notices.first().at(2).toString(), QStringLiteral("case-collision"));
        QCOMPARE(read(x.bobDir + QStringLiteral("/notes.txt")), QByteArray("notes de bob"));
        QVERIFY(QDir(x.bobDir).entryList(QDir::Files).contains(QStringLiteral("notes.txt")));
    }

    void writeMemberUpdatesAddsAndDeletes()
    {
        Setup x;
        start(x, QStringLiteral("ecriture"), 100, true);

        // Mise a jour de la proprietaire : simple remplacement chez bob.
        write(x.ownerDir + QStringLiteral("/rapport.txt"), "version 2 de alice");
        QTRY_VERIFY_WITH_TIMEOUT(read(x.bobDir + QStringLiteral("/rapport.txt")) == "version 2 de alice", 15000);
        QTest::qWait(1500);
        QVERIFY2(conflictCopies(x.bobDir).isEmpty(), qPrintable(conflictCopies(x.bobDir).join(", ")));

        // Mise a jour de bob dans le dossier qu'il a choisi : recue par alice,
        // sans copie de conflit (alice n'a pas touche au fichier).
        write(x.bobDir + QStringLiteral("/rapport.txt"), "version 3 de bob");
        QTRY_VERIFY_WITH_TIMEOUT(read(x.ownerDir + QStringLiteral("/rapport.txt")) == "version 3 de bob", 15000);
        QTest::qWait(1500);
        QVERIFY2(conflictCopies(x.ownerDir).isEmpty(), qPrintable(conflictCopies(x.ownerDir).join(", ")));
        QVERIFY(conflictCopies(x.bobDir).isEmpty());

        // Ajout de bob, dans un sous-dossier.
        write(x.bobDir + QStringLiteral("/notes/note-bob.txt"), "ajout de bob");
        QTRY_VERIFY_WITH_TIMEOUT(read(x.ownerDir + QStringLiteral("/notes/note-bob.txt")) == "ajout de bob", 15000);

        // Suppression par alice d'un fichier non modifie ailleurs : supprime chez bob.
        QVERIFY(QFile::remove(x.ownerDir + QStringLiteral("/notes/note-bob.txt")));
        QTRY_VERIFY_WITH_TIMEOUT(!QFile::exists(x.bobDir + QStringLiteral("/notes/note-bob.txt")), 15000);

        // Renommage par alice qui ne change que la casse : meme fichier chez bob,
        // renomme sans etre perdu.
        QTest::qWait(1500);
        QVERIFY(QFile::rename(x.ownerDir + QStringLiteral("/rapport.txt"), x.ownerDir + QStringLiteral("/Rapport.txt")));
        QTRY_VERIFY_WITH_TIMEOUT(QDir(x.bobDir).entryList(QDir::Files).contains(QStringLiteral("Rapport.txt")), 15000);
        QCOMPARE(read(x.bobDir + QStringLiteral("/Rapport.txt")), QByteArray("version 3 de bob"));

        // Bob modifie le fichier pendant qu'alice le supprime : la modification
        // l'emporte, le fichier revient chez alice avec la version de bob.
        QTest::qWait(1500);
        write(x.bobDir + QStringLiteral("/Rapport.txt"), "modification locale de bob");
        QVERIFY(QFile::remove(x.ownerDir + QStringLiteral("/Rapport.txt")));
        QTRY_VERIFY_WITH_TIMEOUT(read(x.ownerDir + QStringLiteral("/Rapport.txt")) == "modification locale de bob", 15000);
        QTest::qWait(3000); // plus rien ne doit bouger
        QCOMPARE(read(x.bobDir + QStringLiteral("/Rapport.txt")), QByteArray("modification locale de bob"));
        QCOMPARE(read(x.ownerDir + QStringLiteral("/Rapport.txt")), QByteArray("modification locale de bob"));
        QVERIFY(conflictCopies(x.bobDir).isEmpty());
    }

    // Deux modifications simultanees du meme fichier : meme decision des deux
    // cotes, aucune version perdue.
    void concurrentEditsConverge()
    {
        Setup x;
        start(x, QStringLiteral("conflit"), 200, true);

        write(x.ownerDir + QStringLiteral("/rapport.txt"), "version d'alice");
        write(x.bobDir + QStringLiteral("/rapport.txt"), "version de bob");

        QTRY_VERIFY_WITH_TIMEOUT(conflictCopies(x.ownerDir).size() == 1 && conflictCopies(x.bobDir).size() == 1, 20000);
        QTest::qWait(3000); // plus rien ne doit bouger
        QCOMPARE(conflictCopies(x.ownerDir), conflictCopies(x.bobDir));
        QCOMPARE(read(x.ownerDir + QStringLiteral("/rapport.txt")), read(x.bobDir + QStringLiteral("/rapport.txt")));
        const QString copy = conflictCopies(x.ownerDir).first();
        QCOMPARE(read(x.ownerDir + QLatin1Char('/') + copy), read(x.bobDir + QLatin1Char('/') + copy));
        const QSet<QByteArray> versions = {read(x.ownerDir + QStringLiteral("/rapport.txt")),
                                           read(x.ownerDir + QLatin1Char('/') + copy)};
        QCOMPARE(versions, (QSet<QByteArray>{"version d'alice", "version de bob"}));
        QVERIFY2(copy.contains(QStringLiteral("alice")) || copy.contains(QStringLiteral("bob")), qPrintable(copy));
    }

    // Arret du partage par la proprietaire : le dossier quitte LocaLink chez
    // bob, ses fichiers restent sur son disque.
    void stopSharingKeepsMemberFiles()
    {
        Setup x;
        start(x, QStringLiteral("arret"), 300, true);

        const qint64 ownerFolderId = x.s.app->sharedFolderManager()->getFolderByUuid(x.uuid)->id();
        x.s.app->folderSyncService()->stopSharing(ownerFolderId);
        QVERIFY(x.s.app->sharedFolderManager()->removeFolder(ownerFolderId));

        QTRY_VERIFY_WITH_TIMEOUT(!x.b.app->sharedFolderManager()->getFolderByUuid(x.uuid).has_value(), 10000);
        QCOMPARE(read(x.bobDir + QStringLiteral("/rapport.txt")), QByteArray("version 1"));
        QCOMPARE(read(x.ownerDir + QStringLiteral("/rapport.txt")), QByteArray("version 1"));
    }

    // Depart d'un membre : la proprietaire retire son acces et ne lui renvoie
    // plus le dossier ; ses fichiers restent chez lui.
    void memberLeaveIsPropagated()
    {
        Setup x;
        start(x, QStringLiteral("depart"), 400, true);

        const qint64 ownerFolderId = x.s.app->sharedFolderManager()->getFolderByUuid(x.uuid)->id();
        const int bobOnServer = userId(*x.s.app, QStringLiteral("bob"));
        auto bobHasAccess = [&] {
            for (const auto &access : x.s.app->sharedFolderManager()->accessForFolder(ownerFolderId))
                if (access.userId() == bobOnServer) return true;
            return false;
        };
        QVERIFY(bobHasAccess());

        x.b.app->folderSyncService()->leaveFolder(x.folderId);
        QVERIFY(x.b.app->sharedFolderManager()->removeFolder(x.folderId));
        QTRY_VERIFY_WITH_TIMEOUT(!bobHasAccess(), 10000);

        // La proprietaire continue de travailler, bob se resynchronise : le
        // dossier ne revient pas chez lui.
        write(x.ownerDir + QStringLiteral("/rapport.txt"), "version apres depart");
        x.b.app->folderSyncService()->onConnectedToServer();
        QTest::qWait(5000);
        QVERIFY(!x.b.app->sharedFolderManager()->getFolderByUuid(x.uuid).has_value());
        QCOMPARE(read(x.bobDir + QStringLiteral("/rapport.txt")), QByteArray("version 1"));
    }
};

QTEST_MAIN(TestDossiersE2E)
#include "test_dossiers_e2e.moc"
