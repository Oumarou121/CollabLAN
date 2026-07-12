#include "SettingsRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>

namespace database {

SettingsRepository::SettingsRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

SettingsRepository::~SettingsRepository() = default;

models::Settings SettingsRepository::settingsFromQuery(const QSqlQuery &query) const
{
    models::Settings settings;
    settings.setKey(query.value(QStringLiteral("key")).toString());
    settings.setValue(query.value(QStringLiteral("value")));
    return settings;
}

bool SettingsRepository::save(const models::Settings &settings)
{
    QSqlQuery query(m_db);

    // Utiliser INSERT OR REPLACE pour insérer ou mettre à jour
    query.prepare(QStringLiteral(
        "INSERT OR REPLACE INTO Settings (key, value) "
        "VALUES (:key, :value)"
    ));
    query.bindValue(QStringLiteral(":key"), settings.key());
    query.bindValue(QStringLiteral(":value"), settings.value());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

std::optional<models::Settings> SettingsRepository::findByKey(const QString &key) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT key, value FROM Settings WHERE key = :key"));
    query.bindValue(QStringLiteral(":key"), key);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return settingsFromQuery(query);
}

std::vector<models::Settings> SettingsRepository::findAll() const
{
    std::vector<models::Settings> settingsList;

    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT key, value FROM Settings ORDER BY key"))) {
        m_lastError = query.lastError().text();
        return settingsList;
    }
    while (query.next()) {
        settingsList.push_back(settingsFromQuery(query));
    }
    return settingsList;
}

bool SettingsRepository::remove(const QString &key)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM Settings WHERE key = :key"));
    query.bindValue(QStringLiteral(":key"), key);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

QString SettingsRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
