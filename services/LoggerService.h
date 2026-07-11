#ifndef SERVICES_LOGGERSERVICE_H
#define SERVICES_LOGGERSERVICE_H

#include <QObject>
#include <QString>

namespace services {

enum class LogLevel {
    Debug,
    Info,
    Warning,
    Error,
    Critical
};

/**
 * @brief Journalisation technique de l'application (logs applicatifs).
 */
class LoggerService : public QObject
{
    Q_OBJECT

public:
    explicit LoggerService(QObject *parent = nullptr);
    ~LoggerService();

    /// Enregistre un message de niveau Debug
    Q_INVOKABLE void debug(const QString &message);

    /// Enregistre un message de niveau Info
    Q_INVOKABLE void info(const QString &message);

    /// Enregistre un message de niveau Warning
    Q_INVOKABLE void warning(const QString &message);

    /// Enregistre un message de niveau Error
    Q_INVOKABLE void error(const QString &message);

    /// Enregistre un message de niveau Critical
    Q_INVOKABLE void critical(const QString &message);

    /// Définit le niveau minimum de log
    void setMinLogLevel(LogLevel level);

    /// Active/Désactive la sortie console
    void setConsoleOutputEnabled(bool enabled);

    /// Active/Désactive la sortie fichier
    void setFileOutputEnabled(bool enabled);

    /// Définit le chemin du fichier de log
    void setLogFilePath(const QString &filePath);

signals:
    void logMessage(LogLevel level, const QString &message, const QString &timestamp);

private:
    void log(LogLevel level, const QString &message);
    QString levelToString(LogLevel level) const;
    QString currentTimestamp() const;

    LogLevel m_minLogLevel = LogLevel::Info;
    bool m_consoleOutputEnabled = true;
    bool m_fileOutputEnabled = false;
    QString m_logFilePath;
};

} // namespace services

#endif // SERVICES_LOGGERSERVICE_H
