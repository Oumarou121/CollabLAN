#include "LoggerService.h"

#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QDebug>

namespace services {

LoggerService::LoggerService(QObject *parent)
    : QObject(parent)
{
}

LoggerService::~LoggerService()
{
}

void LoggerService::debug(const QString &message)
{
    log(LogLevel::Debug, message);
}

void LoggerService::info(const QString &message)
{
    log(LogLevel::Info, message);
}

void LoggerService::warning(const QString &message)
{
    log(LogLevel::Warning, message);
}

void LoggerService::error(const QString &message)
{
    log(LogLevel::Error, message);
}

void LoggerService::critical(const QString &message)
{
    log(LogLevel::Critical, message);
}

void LoggerService::setMinLogLevel(LogLevel level)
{
    m_minLogLevel = level;
}

void LoggerService::setConsoleOutputEnabled(bool enabled)
{
    m_consoleOutputEnabled = enabled;
}

void LoggerService::setFileOutputEnabled(bool enabled)
{
    m_fileOutputEnabled = enabled;
}

void LoggerService::setLogFilePath(const QString &filePath)
{
    m_logFilePath = filePath;
}

void LoggerService::log(LogLevel level, const QString &message)
{
    if (level < m_minLogLevel) {
        return;
    }

    const QString timestamp = currentTimestamp();
    const QString levelStr = levelToString(level);
    const QString logEntry = QStringLiteral("[%1] [%2] %3").arg(timestamp, levelStr, message);

    // Sortie console
    if (m_consoleOutputEnabled) {
        switch (level) {
        case LogLevel::Debug:
            qDebug().noquote() << logEntry;
            break;
        case LogLevel::Info:
            qInfo().noquote() << logEntry;
            break;
        case LogLevel::Warning:
            qWarning().noquote() << logEntry;
            break;
        case LogLevel::Error:
        case LogLevel::Critical:
            qCritical().noquote() << logEntry;
            break;
        }
    }

    // Sortie fichier
    if (m_fileOutputEnabled && !m_logFilePath.isEmpty()) {
        QFile logFile(m_logFilePath);
        if (logFile.open(QIODevice::Append | QIODevice::Text)) {
            QTextStream out(&logFile);
            out.setEncoding(QStringConverter::Utf8);
            out << logEntry << "\n";
            logFile.close();
        }
    }

    emit logMessage(level, message, timestamp);
}

QString LoggerService::levelToString(LogLevel level) const
{
    switch (level) {
    case LogLevel::Debug:
        return QStringLiteral("DEBUG");
    case LogLevel::Info:
        return QStringLiteral("INFO");
    case LogLevel::Warning:
        return QStringLiteral("WARNING");
    case LogLevel::Error:
        return QStringLiteral("ERROR");
    case LogLevel::Critical:
        return QStringLiteral("CRITICAL");
    }
    return QStringLiteral("UNKNOWN");
}

QString LoggerService::currentTimestamp() const
{
    return QDateTime::currentDateTime().toString(Qt::ISODate);
}

} // namespace services
