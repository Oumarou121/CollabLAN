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

        {
            database::DatabaseManager manager(QStringLiteral("test-reopen-a-%1").arg(reinterpret_cast<quintptr>(this)));
            QVERIFY(manager.open(path));
            manager.close();
        }

        // Reouverture : la migration ne doit pas etre rejouee (pas d'erreur
        // "table already exists" grace au IF NOT EXISTS + user_version).
        database::DatabaseManager manager2(QStringLiteral("test-reopen-b-%1").arg(reinterpret_cast<quintptr>(this)));
        QVERIFY(manager2.open(path));
        QVERIFY(manager2.lastError().isEmpty());
        QCOMPARE(manager2.schemaVersion(), 1);
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
};

QTEST_MAIN(TestDatabaseManager)
#include "test_databasemanager.moc"
