#include "SettingsRepository.h"

#include <QSqlError>
#include <QSqlQuery>

namespace database {

namespace {
const QString kKeyStationName = QStringLiteral("station_name");
const QString kKeyLanguage = QStringLiteral("language");
const QString kKeyTheme = QStringLiteral("theme");
const QString kKeyDownloadFolder = QStringLiteral("download_folder");
} // namespace

SettingsRepository::SettingsRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

SettingsRepository::~SettingsRepository() = default;

QString SettingsRepository::getValue(const QString &key, const QString &defaultValue) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT value FROM Settings WHERE key = :key"));
    query.bindValue(QStringLiteral(":key"), key);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return defaultValue;
    }
    if (!query.next()) {
        return defaultValue;
    }

    const QVariant value = query.value(0);
    return value.isNull() ? defaultValue : value.toString();
}

bool SettingsRepository::setValue(const QString &key, const QString &value)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO Settings (key, value) VALUES (:key, :value) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value"));
    query.bindValue(QStringLiteral(":key"), key);
    query.bindValue(QStringLiteral(":value"), value);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

models::Settings SettingsRepository::load() const
{
    const models::Settings fallback = models::Settings::defaults();

    models::Settings settings;
    settings.setStationName(getValue(kKeyStationName, fallback.stationName()));
    settings.setLanguage(getValue(kKeyLanguage, fallback.language()));
    settings.setTheme(getValue(kKeyTheme, fallback.theme()));
    settings.setDownloadFolder(getValue(kKeyDownloadFolder, fallback.downloadFolder()));
    return settings;
}

bool SettingsRepository::save(const models::Settings &settings)
{
    bool ok = true;
    ok = setValue(kKeyStationName, settings.stationName()) && ok;
    ok = setValue(kKeyLanguage, settings.language()) && ok;
    ok = setValue(kKeyTheme, settings.theme()) && ok;
    ok = setValue(kKeyDownloadFolder, settings.downloadFolder()) && ok;
    return ok;
}

QString SettingsRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
