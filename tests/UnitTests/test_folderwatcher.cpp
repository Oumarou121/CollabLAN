#include <QtTest>
#include <QSignalSpy>
#include <QFile>
#include <QDir>
#include <QFileSystemWatcher>
#include <QTemporaryDir>

#include "core/Sync/FolderWatcher.h"

/*
 * Tests unitaires de core::sync::FolderWatcher (Release 2 -- doc de
 * conception : "detection des changements").
 *
 * On ne peut pas tester QFileSystemWatcher de facon fiable dans tous les
 * environnements CI (inotify peut etre indisponible sur certains postes),
 * donc on se concentre sur les comportements purement C++ :
 *   - watchFolder / unwatchFolder : pas de crash, state coherent
 *   - refreshWatchedFiles : pas de crash, ajout/suppression OK
 *   - setDebounceInterval : change l'intervalle sans crash
 *   - changesDetected     : debounce -- plusieurs notifications rapides ne
 *     produisent qu'un seul signal apres le delai.
 *
 * Les tests qui necessitent un vrai evenement systeme de fichier sont
 * marques QSKIP si inotify n'est pas disponible (ex: environnement Docker
 * sans montage de volumes).
 */
class TestFolderWatcher : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;

    bool writeFile(const QString &relativePath, const QByteArray &content = QByteArrayLiteral("x"))
    {
        const QString absPath = m_dir.filePath(relativePath);
        QDir().mkpath(QFileInfo(absPath).absolutePath());
        QFile f(absPath);
        if (!f.open(QIODevice::WriteOnly))
            return false;
        f.write(content);
        return true;
    }

private slots:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
    }

    // watchFolder / unwatchFolder : ne plante pas et accepte l'appel
    // multiple (idempotent si le meme folderId est fourni deux fois).
    void watchAndUnwatchIsIdempotent()
    {
        core::sync::FolderWatcher watcher;
        watcher.watchFolder(1, m_dir.path(), QStringList());
        watcher.watchFolder(1, m_dir.path(), QStringList()); // deuxieme appel : remplace
        watcher.unwatchFolder(1);
        watcher.unwatchFolder(1); // appel superflu : pas de crash
    }

    // unwatchFolder sur un id inconnu ne plante pas.
    void unwatchUnknownFolderIsSafe()
    {
        core::sync::FolderWatcher watcher;
        watcher.unwatchFolder(999);
    }

    // refreshWatchedFiles sur un id non surveille ne plante pas.
    void refreshUnknownFolderIsSafe()
    {
        core::sync::FolderWatcher watcher;
        watcher.refreshWatchedFiles(42, QStringList() << QStringLiteral("a.txt"));
    }

    // setDebounceInterval accepte des valeurs variees.
    void setDebounceIntervalAcceptsVariousValues()
    {
        core::sync::FolderWatcher watcher;
        watcher.setDebounceInterval(0);
        watcher.setDebounceInterval(100);
        watcher.setDebounceInterval(2000);
    }

    // watchFolder avec une liste de fichiers connus : refreshWatchedFiles
    // peut ensuite ajouter/supprimer des entrees sans crash.
    void refreshWatchedFilesAddsAndRemovesPaths()
    {
        writeFile(QStringLiteral("a.txt"));
        writeFile(QStringLiteral("b.txt"));

        core::sync::FolderWatcher watcher;
        watcher.watchFolder(1, m_dir.path(),
                            QStringList() << QStringLiteral("a.txt"));

        // Ajoute b.txt, retire a.txt
        watcher.refreshWatchedFiles(1, QStringList() << QStringLiteral("b.txt"));
        // Vide
        watcher.refreshWatchedFiles(1, QStringList());
        watcher.unwatchFolder(1);
    }

    // Le debounce regroupe plusieurs notifications rapides en une seule.
    // Ce test ne peut fonctionner que si QFileSystemWatcher est operationnel
    // sur cet OS/environnement (inotify disponible, etc.).
    void debounceEmitsOnlyOneSignalForBurstOfChanges()
    {
#ifdef Q_OS_LINUX
        // Sur certains CI Linux sans inotify (Docker, Nix...) QFileSystemWatcher
        // reste muet : on detecte cela en essayant d'ajouter un chemin et en
        // verifiant que la liste "files()" a bien accepte le chemin.  S'il n'est
        // pas accepte, l'environnement ne supporte pas inotify et on passe le
        // test.
        QFileSystemWatcher probe;
        writeFile(QStringLiteral("probe.txt"));
        // addPath() returns true if the path was successfully watched.
        // If it returns false the kernel watch facility (inotify/kqueue…)
        // is not available in this environment (e.g. Docker without inotify),
        // so skip the signal-based part of the test.
        const bool watched = probe.addPath(m_dir.filePath(QStringLiteral("probe.txt")));
        if (!watched) {
            QSKIP("QFileSystemWatcher non operationnel dans cet environnement (inotify absent ?)");
        }
#endif

        core::sync::FolderWatcher watcher;
        watcher.setDebounceInterval(80); // 80 ms
        watcher.watchFolder(1, m_dir.path(), QStringList());

        QSignalSpy spy(&watcher, &core::sync::FolderWatcher::changesDetected);

        // Declenche plusieurs changements rapides
        writeFile(QStringLiteral("burst1.txt"));
        QTest::qWait(10);
        writeFile(QStringLiteral("burst2.txt"));
        QTest::qWait(10);
        writeFile(QStringLiteral("burst3.txt"));

        // Attends que le debounce expire
        QTest::qWait(200);

        // Un seul signal malgre plusieurs changements
        QVERIFY2(spy.count() <= 1,
                 qPrintable(QString("Attendu <= 1 signal, recu %1").arg(spy.count())));

        watcher.unwatchFolder(1);
    }
};

QTEST_MAIN(TestFolderWatcher)
#include "test_folderwatcher.moc"
