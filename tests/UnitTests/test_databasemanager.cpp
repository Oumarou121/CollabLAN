#include <QtTest>
#include <QTemporaryDir>
#include <QFile>
#include <QSqlQuery>
#include <QSqlError>

#include "DatabaseManager.h"

class TestDatabaseManager : public QObject
{
    Q_OBJECT

private:
    QString dbPathIn(const QTemporaryDir &dir) const
    {
        return dir.filePath(QStringLiteral("test.db"));
    }

private slots:
    void openCreatesFileAndAppliesMigrations()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        database::DatabaseManager manager(QStringLiteral("test-open-%1").arg(reinterpret_cast<quintptr>(this)));
        QVERIFY(manager.open(dbPathIn(dir)));
        QVERIFY(manager.isOpen());
        QVERIFY(manager.lastError().isEmpty());
        QVERIFY(QFile::exists(dbPathIn(dir)));
        QVERIFY(manager.schemaVersion() > 0);

        // Les tables de la migration initiale doivent exister.
        QSqlQuery query(manager.database());
        QVERIFY(query.exec(QStringLiteral(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='Users'")));
        QVERIFY(query.next());

        manager.close();
        QVERIFY(!manager.isOpen());
    }

    void reopenIsIdempotent()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dbPathIn(dir);

        int versionAfterFirstOpen = 0;
        {
            database::DatabaseManager manager(QStringLiteral("test-reopen-a-%1").arg(reinterpret_cast<quintptr>(this)));
            QVERIFY(manager.open(path));
            versionAfterFirstOpen = manager.schemaVersion();
            QVERIFY(versionAfterFirstOpen > 0);
            manager.close();
        }

        // Reouverture : la migration ne doit pas etre rejouee (pas d'erreur
        // "table already exists" grace au IF NOT EXISTS + user_version).
        database::DatabaseManager manager2(QStringLiteral("test-reopen-b-%1").arg(reinterpret_cast<quintptr>(this)));
        QVERIFY(manager2.open(path));
        QVERIFY(manager2.lastError().isEmpty());
        // On compare a la version obtenue ci-dessus plutot qu'a un nombre fige : ce test
        // verifie que rien n'est rejoue, pas le nombre de migrations du projet (qui change a
        // chaque evolution du schema et faisait echouer ce test sans aucun rapport avec son objet).
        QCOMPARE(manager2.schemaVersion(), versionAfterFirstOpen);
    }

    void foreignKeysAreEnabled()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        database::DatabaseManager manager(QStringLiteral("test-fk-%1").arg(reinterpret_cast<quintptr>(this)));
        QVERIFY(manager.open(dbPathIn(dir)));

        QSqlQuery query(manager.database());
        QVERIFY(query.exec(QStringLiteral("PRAGMA foreign_keys")));
        QVERIFY(query.next());
        QCOMPARE(query.value(0).toInt(), 1);
    }

    void closeWithoutOpenIsSafe()
    {
        // Fermer un manager jamais ouvert ne doit ni planter ni lever
        // d'erreur : c'est un no-op.
        database::DatabaseManager manager(QStringLiteral("test-close-noop-%1").arg(reinterpret_cast<quintptr>(this)));
        QVERIFY(!manager.isOpen());
        manager.close();
        QVERIFY(!manager.isOpen());
    }

    void doubleCloseIsSafe()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        database::DatabaseManager manager(QStringLiteral("test-double-close-%1").arg(reinterpret_cast<quintptr>(this)));
        QVERIFY(manager.open(dbPathIn(dir)));

        manager.close();
        QVERIFY(!manager.isOpen());

        // Un second close() sur une connexion deja fermee ne doit pas planter.
        manager.close();
        QVERIFY(!manager.isOpen());
    }

    void reopenAfterCloseOnSameInstanceWorks()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dbPathIn(dir);

        database::DatabaseManager manager(QStringLiteral("test-reuse-%1").arg(reinterpret_cast<quintptr>(this)));

        QVERIFY(manager.open(path));
        QVERIFY(manager.isOpen());
        const int versionAfterFirstOpen = manager.schemaVersion();
        QVERIFY(versionAfterFirstOpen > 0);
        manager.close();
        QVERIFY(!manager.isOpen());

        // Reutiliser la meme instance (meme nom de connexion) pour rouvrir
        // la meme base doit fonctionner sans erreur residuelle.
        QVERIFY(manager.open(path));
        QVERIFY(manager.isOpen());
        QVERIFY(manager.lastError().isEmpty());
        // Voir reopenIsIdempotent() : on compare a la version relevee avant fermeture.
        QCOMPARE(manager.schemaVersion(), versionAfterFirstOpen);

        manager.close();
    }

    void openOnAlreadyOpenInstanceIsNoop()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        database::DatabaseManager manager(QStringLiteral("test-reopen-noop-%1").arg(reinterpret_cast<quintptr>(this)));
        QVERIFY(manager.open(dbPathIn(dir)));
        const QString firstPath = manager.databaseFilePath();

        // Un second open() alors que la connexion est deja active ne doit
        // rien casser : il doit rester ouvert sur la meme base.
        QVERIFY(manager.open(dbPathIn(dir)));
        QCOMPARE(manager.databaseFilePath(), firstPath);
        QVERIFY(manager.isOpen());

        manager.close();
    }

    void openWithUnwritableParentDirectoryFailsCleanly()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());

        // On force un chemin dont un composant parent est un FICHIER
        // (et non un dossier) : la creation du repertoire doit echouer,
        // et open() doit retourner false proprement, sans planter,
        // avec un message dans lastError().
        const QString blockingFile = dir.filePath(QStringLiteral("not_a_directory"));
        QFile file(blockingFile);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.close();

        const QString invalidDbPath = blockingFile + QStringLiteral("/sub/test.db");

        database::DatabaseManager manager(QStringLiteral("test-invalid-path-%1").arg(reinterpret_cast<quintptr>(this)));
        QVERIFY(!manager.open(invalidDbPath));
        QVERIFY(!manager.isOpen());
        QVERIFY(!manager.lastError().isEmpty());
    }
};

QTEST_MAIN(TestDatabaseManager)
#include "test_databasemanager.moc"