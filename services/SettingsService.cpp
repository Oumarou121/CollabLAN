#include "SettingsService.h"

#include "DatabaseManager.h"
#include "Database/Repositories/SettingsRepository.h"
#include "models/Settings.h"

namespace services {

SettingsService::SettingsService(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
{
    if (m_dbManager) {
        m_repository = std::make_unique<database::SettingsRepository>(m_dbManager->database());
    }
}

SettingsService::~SettingsService()
{
}

QVariant SettingsService::getValue(const QString &key, const QVariant &defaultValue) const
{
    if (!m_repository) {
        return defaultValue;
    }

    const auto settings = m_repository->findByKey(key);
    if (!settings.has_value()) {
        return defaultValue;
    }
    return settings->value();
}

bool SettingsService::setValue(const QString &key, const QVariant &value)
{
    if (!m_repository) {
        emit errorOccurred(tr("Repository non initialisé"));
        return false;
    }

    models::Settings settings(key, value);
    if (!m_repository->save(settings)) {
        emit errorOccurred(tr("Impossible de sauvegarder le paramètre : %1").arg(m_repository->lastError()));
        return false;
    }

    emit valueChanged(key, value);
    return true;
}

QString SettingsService::getString(const QString &key, const QString &defaultValue) const
{
    return getValue(key, defaultValue).toString();
}

int SettingsService::getInt(const QString &key, int defaultValue) const
{
    return getValue(key, defaultValue).toInt();
}

bool SettingsService::getBool(const QString &key, bool defaultValue) const
{
    return getValue(key, defaultValue).toBool();
}

bool SettingsService::remove(const QString &key)
{
    if (!m_repository) {
        emit errorOccurred(tr("Repository non initialisé"));
        return false;
    }

    if (!m_repository->remove(key)) {
        emit errorOccurred(tr("Impossible de supprimer le paramètre : %1").arg(m_repository->lastError()));
        return false;
    }

    emit valueChanged(key, QVariant());
    return true;
}

bool SettingsService::contains(const QString &key) const
{
    if (!m_repository) {
        return false;
    }
    return m_repository->findByKey(key).has_value();
}

} // namespace services
