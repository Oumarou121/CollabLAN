#ifndef DATABASE_DATABASEMANAGER_H
#define DATABASE_DATABASEMANAGER_H

#include <QSqlDatabase>
#include <QString>
#include <QStringList>

namespace database {

/**
 * @brief Ouverture/fermeture de la base SQLite, execution des migrations.
 */
class DatabaseManager {
public:
    explicit DatabaseManager(const QString &connectionName = QStringLiteral("collablan_db"));
    ~DatabaseManager();

    DatabaseManager(const DatabaseManager &) = delete;
    DatabaseManager &operator=(const DatabaseManager &) = delete;

    bool open(const QString &dbFilePath = QString());
    void close();
    bool isOpen() const;

    QString databaseFilePath() const;
    static QString defaultDatabaseFilePath();

    QSqlDatabase database() const;
    QString lastError() const;

    int schemaVersion() const;

private:
    bool ensureMigrationsTable();
    QStringList pendingMigrationFiles() const;
    bool applyMigrationFile(const QString &filePath);
    bool markMigrationApplied(const QString &migrationName);
    QStringList splitStatements(const QString &sqlScript) const;

    QString m_connectionName;
    QString m_dbFilePath;
    QString m_lastError;
};

} // namespace database

#endif // DATABASE_DATABASEMANAGER_H
