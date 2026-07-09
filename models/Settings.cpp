#include "Settings.h"

#include <QStandardPaths>

namespace models {

Settings::Settings()
    : m_stationName(QString())
    , m_downloadFolder(QStandardPaths::writableLocation(QStandardPaths::DownloadLocation))
{
}

Settings::Settings(QString stationName,
                    QString language,
                    QString theme,
                    QString downloadFolder)
    : m_stationName(std::move(stationName))
    , m_language(language.isEmpty() ? QStringLiteral("fr") : std::move(language))
    , m_theme(theme.isEmpty() ? QStringLiteral("light") : std::move(theme))
    , m_downloadFolder(downloadFolder.isEmpty()
                            ? QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)
                            : std::move(downloadFolder))
{
}

Settings::~Settings() = default;

QString Settings::stationName() const { return m_stationName; }
void Settings::setStationName(const QString &stationName) { m_stationName = stationName; }

QString Settings::language() const { return m_language; }
void Settings::setLanguage(const QString &language)
{
    m_language = language.isEmpty() ? QStringLiteral("fr") : language;
}

QString Settings::theme() const { return m_theme; }
void Settings::setTheme(const QString &theme)
{
    m_theme = theme.isEmpty() ? QStringLiteral("light") : theme;
}

QString Settings::downloadFolder() const { return m_downloadFolder; }
void Settings::setDownloadFolder(const QString &downloadFolder)
{
    m_downloadFolder = downloadFolder.isEmpty()
                            ? QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)
                            : downloadFolder;
}

Settings Settings::defaults()
{
    return Settings();
}

} // namespace models
