#include "DatabaseManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QTextStream>

namespace database {

namespace {
constexpr const char *kSqliteDriver = "QSQLITE";
constexpr const char *kMigrationsDirName = "Migrations";
}

DatabaseManager::DatabaseManager(const QString &connectionName)
    : m_connectionName(connectionName)
{
}

DatabaseManager::~DatabaseManager()
{
    close();
}

QString DatabaseManager::defaultDatabaseFilePath()
{
    const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    return QDir(dataDir).filePath(QStringLiteral("collablan.db"));
}

bool DatabaseManager::open(const QString &dbFilePath)
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
        QSqlDatabase::removeDatabase(m_connectionName);
        return false;
    }

    // Active les contraintes de cle etrangere pour SQLite.
    QSqlQuery pragma(db);
    if (!pragma.exec(QStringLiteral("PRAGMA foreign_keys = ON;"))) {
        m_lastError = pragma.lastError().text();
    }

    if (!ensureMigrationsTable()) {
        close();
        return false;
    }

    const QStringList migrations = pendingMigrationFiles();
    for (const QString &migrationPath : migrations) {
        if (!applyMigrationFile(migrationPath)) {
            close();
            return false;
        }
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

QString DatabaseManager::databaseFilePath() const
{
    return m_dbFilePath;
}

QSqlDatabase DatabaseManager::database() const
{
    return QSqlDatabase::database(m_connectionName, false);
}

QString DatabaseManager::lastError() const
{
    return m_lastError;
}

int DatabaseManager::schemaVersion() const
{
    if (!isOpen()) {
        return 0;
    }

    QSqlQuery query(database());
    if (!query.exec(QStringLiteral("SELECT COUNT(*) FROM schema_migrations;"))) {
        return 0;
    }
    if (query.next()) {
        return query.value(0).toInt();
    }
    return 0;
}

bool DatabaseManager::ensureMigrationsTable()
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
    return pending;
}

bool DatabaseManager::applyMigrationFile(const QString &filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_lastError = QStringLiteral("Impossible d'ouvrir le fichier de migration : %1").arg(filePath);
        return false;
    }

    QTextStream stream(&file);
    const QString sqlScript = stream.readAll();
    file.close();

    QSqlDatabase db = database();
    if (!db.transaction()) {
        m_lastError = db.lastError().text();
        return false;
    }

    for (const QString &statement : splitStatements(sqlScript)) {
        QSqlQuery query(db);
        if (!query.exec(statement)) {
            m_lastError = QStringLiteral("Echec de la migration %1 : %2")
                               .arg(QFileInfo(filePath).fileName(), query.lastError().text());
            db.rollback();
            return false;
        }
    }

    const QString migrationName = QFileInfo(filePath).fileName();
    if (!markMigrationApplied(migrationName)) {
        db.rollback();
        return false;
    }

    if (!db.commit()) {
        m_lastError = db.lastError().text();
        db.rollback();
        return false;
    }

    return true;
}

bool DatabaseManager::markMigrationApplied(const QString &migrationName)
{
    QSqlQuery query(database());
    query.prepare(QStringLiteral("INSERT INTO schema_migrations (name) VALUES (:name);"));
    query.bindValue(QStringLiteral(":name"), migrationName);
    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true;
}

} // namespace database
