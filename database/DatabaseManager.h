#ifndef DATABASE_DATABASEMANAGER_H
#define DATABASE_DATABASEMANAGER_H

#include <QSqlDatabase>
#include <QString>
#include <QStringList>

namespace database {

/**
 * @brief Ouverture/fermeture de la base SQLite, execution des migrations.
 *
 * Le DatabaseManager est responsable de :
 *  - ouvrir (ou creer) le fichier SQLite dans le repertoire de donnees
 *    applicatif (ou un chemin explicite, utile pour les tests) ;
 *  - activer les "foreign keys" SQLite (desactivees par defaut) ;
 *  - executer au demarrage les scripts SQL du dossier Migrations/,
 *    dans l'ordre lexicographique de leur nom de fichier, en ne
 *    rejouant jamais une migration deja appliquee (table de suivi
 *    schema_migrations) ;
 *  - exposer la connexion QSqlDatabase aux repositories.
 *
 * Chaque instance utilise un nom de connexion Qt unique afin de
 * pouvoir coexister avec d'autres connexions (utile notamment dans
 * les tests unitaires qui ouvrent plusieurs bases en memoire).
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

    // Nombre de migrations appliquees avec succes sur cette base
    // (0 si jamais ouverte ou si aucune migration n'a encore ete jouee).
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
