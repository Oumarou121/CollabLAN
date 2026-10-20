// Lot 1 securite : les chemins relatifs des dossiers partages arrivent du reseau et ne doivent
// jamais permettre de sortir du dossier partage (lecture, ecriture, renommage, suppression).
#include <QtTest>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QTemporaryDir>

#include "Sync/SafePath.h"

using core::sync::resolveInsideFolder;

class TestSafePath : public QObject
{
    Q_OBJECT

private slots:
    void acceptsPathsInsideTheFolder()
    {
        QTemporaryDir root;
        QVERIFY(root.isValid());
        const QString base = QDir::cleanPath(root.path());

        QCOMPARE(resolveInsideFolder(root.path(), QStringLiteral("notes.txt")), base + QStringLiteral("/notes.txt"));
        QCOMPARE(resolveInsideFolder(root.path(), QStringLiteral("a/b/c.pdf")), base + QStringLiteral("/a/b/c.pdf"));
        QCOMPARE(resolveInsideFolder(root.path(), QStringLiteral("a\\b\\c.pdf")), base + QStringLiteral("/a/b/c.pdf"));
        QCOMPARE(resolveInsideFolder(root.path(), QStringLiteral("./a//b.txt")), base + QStringLiteral("/a/b.txt"));
        // Un nom contenant ".." sans etre un segment ".." reste un nom de fichier valide.
        QCOMPARE(resolveInsideFolder(root.path(), QStringLiteral("rapport..v2.docx")), base + QStringLiteral("/rapport..v2.docx"));
    }

    void rejectsTraversalAndAbsolutePaths_data()
    {
        QTest::addColumn<QString>("relative");
        QTest::newRow("vide") << QString();
        QTest::newRow("espaces") << QStringLiteral("   ");
        QTest::newRow("dossier lui-meme") << QStringLiteral(".");
        QTest::newRow("parent") << QStringLiteral("..");
        QTest::newRow("traversee") << QStringLiteral("../secret.txt");
        QTest::newRow("traversee profonde") << QStringLiteral("../../Users/Public/secret.txt");
        QTest::newRow("traversee au milieu") << QStringLiteral("a/../../secret.txt");
        QTest::newRow("traversee backslash") << QStringLiteral("..\\..\\Windows\\win.ini");
        QTest::newRow("absolu unix") << QStringLiteral("/etc/passwd");
        QTest::newRow("absolu windows") << QStringLiteral("C:/Windows/win.ini");
        QTest::newRow("lecteur relatif") << QStringLiteral("C:secret.txt");
        QTest::newRow("unc") << QStringLiteral("\\\\serveur\\partage\\x.txt");
        QTest::newRow("flux ntfs") << QStringLiteral("notes.txt:cache");
    }

    void rejectsTraversalAndAbsolutePaths()
    {
        QFETCH(QString, relative);
        QTemporaryDir root;
        QVERIFY(root.isValid());
        QVERIFY2(resolveInsideFolder(root.path(), relative).isEmpty(), qPrintable(relative));
    }

    void rejectsWhenRootIsMissing()
    {
        QVERIFY(resolveInsideFolder(QString(), QStringLiteral("a.txt")).isEmpty());
    }

#ifdef Q_OS_WIN
    // Une jonction placee dans le dossier partage ne doit pas servir de porte de sortie.
    void rejectsJunctionPointingOutside()
    {
        QTemporaryDir root;
        QTemporaryDir outside;
        QVERIFY(root.isValid() && outside.isValid());
        QFile secret(outside.filePath(QStringLiteral("secret.txt")));
        QVERIFY(secret.open(QIODevice::WriteOnly));
        secret.write("x");
        secret.close();

        const QString link = QDir::toNativeSeparators(root.filePath(QStringLiteral("lien")));
        const int code = QProcess::execute(QStringLiteral("cmd"),
            {QStringLiteral("/c"), QStringLiteral("mklink"), QStringLiteral("/J"), link,
             QDir::toNativeSeparators(outside.path())});
        if (code != 0)
            QSKIP("Creation de jonction impossible sur ce poste");

        QVERIFY(resolveInsideFolder(root.path(), QStringLiteral("lien/secret.txt")).isEmpty());
        QDir().rmdir(link);
    }
#endif
};

QTEST_GUILESS_MAIN(TestSafePath)
#include "test_safepath.moc"
