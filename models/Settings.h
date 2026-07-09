#ifndef MODELS_SETTINGS_H
#define MODELS_SETTINGS_H

#include <QString>

namespace models {

/**
 * @brief Represente les parametres locaux de l'application pour ce poste.
 *
 * Ces parametres sont persistes en base (table Settings, cle/valeur) via
 * database::SettingsRepository et recharges au demarrage de l'application.
 */
class Settings {
public:
    Settings();
    Settings(QString stationName,
             QString language,
             QString theme,
             QString downloadFolder);
    ~Settings();

    QString stationName() const;
    void setStationName(const QString &stationName);

    QString language() const;
    void setLanguage(const QString &language);

    QString theme() const;
    void setTheme(const QString &theme);

    QString downloadFolder() const;
    void setDownloadFolder(const QString &downloadFolder);

    /**
     * @brief Valeurs par defaut utilisees lorsque la base ne contient
     * pas (encore) de parametres sauvegardes.
     */
    static Settings defaults();

private:
    QString m_stationName;
    QString m_language = QStringLiteral("fr");
    QString m_theme = QStringLiteral("light");
    QString m_downloadFolder;
};

} // namespace models

#endif // MODELS_SETTINGS_H
