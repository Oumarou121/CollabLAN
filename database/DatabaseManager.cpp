#include "DatabaseManager.h"

#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTextStream>

namespace database {

namespace {

// Contenu de la migration initiale (miroir de
// database/Migrations/001_initial_schema.sql). Embarque en dur pour que
// l'ouverture de la base ne depende pas du repertoire de travail courant
// au runtime ; le fichier .sql reste la reference documentee.
const char *kInitialSchema = R"SQL(
CREATE TABLE IF NOT EXISTS Users (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    name           TEXT NOT NULL UNIQUE,
    ip_address     TEXT NOT NULL DEFAULT '',
    status         TEXT NOT NULL DEFAULT 'offline',
    is_admin       INTEGER NOT NULL DEFAULT 0,
    password_hash  TEXT NOT NULL DEFAULT '',
    password_salt  TEXT NOT NULL DEFAULT '',
    created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS Groups (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL,
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS Messages (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_id     INTEGER NOT NULL REFERENCES Users(id),
    group_id      INTEGER REFERENCES Groups(id),
    recipient_id  INTEGER REFERENCES Users(id),
    content       TEXT NOT NULL,
    sent_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS Transfers (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_id     INTEGER NOT NULL REFERENCES Users(id),
    recipient_id  INTEGER NOT NULL REFERENCES Users(id),
    file_name     TEXT NOT NULL,
    file_size     INTEGER NOT NULL,
    status        TEXT NOT NULL DEFAULT 'pending',
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS AuditLogs (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type    TEXT NOT NULL,
    description   TEXT,
    user_id       INTEGER REFERENCES Users(id),
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS Settings (
    key           TEXT PRIMARY KEY,
    value         TEXT
);
)SQL";

QString defaultDatabasePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return QDir(dir).filePath(QStringLiteral("collablan.sqlite"));
}

} // namespace

DatabaseManager::DatabaseManager()
    : DatabaseManager(defaultDatabasePath())
{
}

DatabaseManager::DatabaseManager(QString databasePath, QString connectionName)
    : m_databasePath(std::move(databasePath))
    , m_connectionName(std::move(connectionName))
{
}

DatabaseManager::~DatabaseManager()
{
    close();
}

bool DatabaseManager::open()
{
    if (isOpen()) {
        return true;
    }

    QDir().mkpath(QFileInfo(m_databasePath).absolutePath());

    QSqlDatabase db = QSqlDatabase::contains(m_connectionName)
                           ? QSqlDatabase::database(m_connectionName)
                           : QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), m_connectionName);
    db.setDatabaseName(m_databasePath);

    if (!db.open()) {
        m_lastError = db.lastError().text();
        return false;
    }

    // Active les contraintes de cle etrangere pour SQLite.
    QSqlQuery pragma(db);
    pragma.exec(QStringLiteral("PRAGMA foreign_keys = ON;"));

    if (!runMigrations()) {
        return false;
    }

    return true;
}

void DatabaseManager::close()
{
    if (QSqlDatabase::contains(m_connectionName)) {
        {
            QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
            if (db.isOpen()) {
                db.close();
            }
        }
        QSqlDatabase::removeDatabase(m_connectionName);
    }
}

bool DatabaseManager::isOpen() const
{
    return QSqlDatabase::contains(m_connectionName)
           && QSqlDatabase::database(m_connectionName, false).isOpen();
}

QString DatabaseManager::databasePath() const
{
    return m_databasePath;
}

QString DatabaseManager::lastError() const
{
    return m_lastError;
}

QSqlDatabase DatabaseManager::database() const
{
    return QSqlDatabase::database(m_connectionName);
}

bool DatabaseManager::runMigrations()
{
    QSqlDatabase db = database();

    const QStringList statements = QString::fromUtf8(kInitialSchema)
                                        .split(QChar(';'), Qt::SkipEmptyParts);

    for (const QString &rawStatement : statements) {
        const QString statement = rawStatement.trimmed();
        if (statement.isEmpty()) {
            continue;
        }
        QSqlQuery query(db);
        if (!query.exec(statement)) {
            m_lastError = query.lastError().text();
            return false;
        }
    }

    return true;
}

bool DatabaseManager::executeSqlScript(const QString &sqlFilePath)
{
    QFile file(sqlFilePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_lastError = QStringLiteral("Impossible d'ouvrir le script SQL: %1").arg(sqlFilePath);
        return false;
    }

    QTextStream stream(&file);
    const QString content = stream.readAll();
    const QStringList statements = content.split(QChar(';'), Qt::SkipEmptyParts);

    QSqlDatabase db = database();
    for (const QString &rawStatement : statements) {
        const QString statement = rawStatement.trimmed();
        if (statement.isEmpty()) {
            continue;
        }
        QSqlQuery query(db);
        if (!query.exec(statement)) {
            m_lastError = query.lastError().text();
            return false;
        }
    }

    return true;
}

} // namespace database
