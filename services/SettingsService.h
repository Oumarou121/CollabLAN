#ifndef SERVICES_SETTINGSSERVICE_H
#define SERVICES_SETTINGSSERVICE_H

#include <QObject>
#include <QString>
#include <QVariant>

namespace database {
class DatabaseManager;
class SettingsRepository;
}

namespace services {

/**
 * @brief Lecture/ecriture des parametres utilisateur.
 */
class SettingsService : public QObject
{
    Q_OBJECT

public:
    explicit SettingsService(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~SettingsService();

    /// Récupère la valeur d'un paramètre
    Q_INVOKABLE QVariant getValue(const QString &key, const QVariant &defaultValue = QVariant()) const;

    /// Définit la valeur d'un paramètre
    Q_INVOKABLE bool setValue(const QString &key, const QVariant &value);

    /// Récupère un paramètre sous forme de chaîne
    Q_INVOKABLE QString getString(const QString &key, const QString &defaultValue = QString()) const;

    /// Récupère un paramètre sous forme d'entier
    Q_INVOKABLE int getInt(const QString &key, int defaultValue = 0) const;

    /// Récupère un paramètre sous forme de booléen
    Q_INVOKABLE bool getBool(const QString &key, bool defaultValue = false) const;

    /// Supprime un paramètre
    Q_INVOKABLE bool remove(const QString &key);

    /// Vérifie si un paramètre existe
    Q_INVOKABLE bool contains(const QString &key) const;

signals:
    void valueChanged(const QString &key, const QVariant &value);
    void errorOccurred(const QString &errorString);

private:
    database::DatabaseManager *m_dbManager = nullptr;
    std::unique_ptr<database::SettingsRepository> m_repository;
};

} // namespace services

#endif // SERVICES_SETTINGSSERVICE_H
