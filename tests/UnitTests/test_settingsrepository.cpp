#include <QtTest>
#include <QTemporaryDir>
#include <QRandomGenerator>

#include "database/DatabaseManager.h"
#include "database/Repositories/SettingsRepository.h"

class TestSettingsRepository : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_tempDir;
    database::DatabaseManager *m_dbManager = nullptr;

private slots:
    void init()
    {
        QVERIFY(m_tempDir.isValid());
        const QString dbPath = m_tempDir.filePath(
            QStringLiteral("test_%1.sqlite").arg(QRandomGenerator::global()->generate()));
        m_dbManager = new database::DatabaseManager(
            QStringLiteral("test_settingsrepo_connection_%1").arg(QRandomGenerator::global()->generate()));
        QVERIFY(m_dbManager->open(dbPath));
    }

    void cleanup()
    {
        delete m_dbManager;
        m_dbManager = nullptr;
    }

    void testLoadOnEmptyDatabaseReturnsDefaults()
    {
        database::SettingsRepository repo(m_dbManager->database());

        const auto settings = repo.load();
        const auto defaults = models::Settings::defaults();

        QCOMPARE(settings.language(), defaults.language());
        QCOMPARE(settings.theme(), defaults.theme());
        QCOMPARE(settings.downloadFolder(), defaults.downloadFolder());
    }

    void testSaveThenLoadRoundTrips()
    {
        database::SettingsRepository repo(m_dbManager->database());

        models::Settings settings;
        settings.setStationName(QStringLiteral("Poste-Alice"));
        settings.setLanguage(QStringLiteral("en"));
        settings.setTheme(QStringLiteral("dark"));
        settings.setDownloadFolder(QStringLiteral("/home/alice/Downloads"));

        QVERIFY(repo.save(settings));

        const auto reloaded = repo.load();
        QCOMPARE(reloaded.stationName(), QStringLiteral("Poste-Alice"));
        QCOMPARE(reloaded.language(), QStringLiteral("en"));
        QCOMPARE(reloaded.theme(), QStringLiteral("dark"));
        QCOMPARE(reloaded.downloadFolder(), QStringLiteral("/home/alice/Downloads"));
    }

    void testSaveTwiceUpdatesExistingValues()
    {
        database::SettingsRepository repo(m_dbManager->database());

        models::Settings first;
        first.setStationName(QStringLiteral("Poste-1"));
        first.setTheme(QStringLiteral("light"));
        QVERIFY(repo.save(first));

        models::Settings second;
        second.setStationName(QStringLiteral("Poste-1-renamed"));
        second.setTheme(QStringLiteral("dark"));
        QVERIFY(repo.save(second));

        const auto reloaded = repo.load();
        QCOMPARE(reloaded.stationName(), QStringLiteral("Poste-1-renamed"));
        QCOMPARE(reloaded.theme(), QStringLiteral("dark"));
    }

    void testGetSetValueGenericKey()
    {
        database::SettingsRepository repo(m_dbManager->database());

        QCOMPARE(repo.getValue(QStringLiteral("custom_key"), QStringLiteral("fallback")),
                 QStringLiteral("fallback"));

        QVERIFY(repo.setValue(QStringLiteral("custom_key"), QStringLiteral("custom_value")));
        QCOMPARE(repo.getValue(QStringLiteral("custom_key"), QStringLiteral("fallback")),
                 QStringLiteral("custom_value"));
    }
};

QTEST_MAIN(TestSettingsRepository)
#include "test_settingsrepository.moc"
