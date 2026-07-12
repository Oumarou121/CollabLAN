#ifndef DATABASE_SETTINGSREPOSITORY_H
#define DATABASE_SETTINGSREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <QVariant>
#include <optional>
#include <vector>

#include "models/Settings.h"

namespace database {

/**
 * @brief Acces aux donnees de la table Settings.
 */
class SettingsRepository
{
public:
    explicit SettingsRepository(QSqlDatabase database);
    ~SettingsRepository();

    /// Insère ou met à jour un paramètre
    bool save(const models::Settings &settings);

    /// Récupère un paramètre par sa clé
    std::optional<models::Settings> findByKey(const QString &key) const;

    /// Récupère tous les paramètres
    std::vector<models::Settings> findAll() const;

    /// Supprime un paramètre par sa clé
    bool remove(const QString &key);

    QString lastError() const;

private:
    models::Settings settingsFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SETTINGSREPOSITORY_H
