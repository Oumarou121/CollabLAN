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
    return QDir(dataDir).filePath(QStringLiteral("localink.db"));
}

bool DatabaseManager::open(const QString &dbFilePath)
{
    if (isOpen()) {
        return true;
    }

    m_dbFilePath = dbFilePath.isEmpty() ? defaultDatabaseFilePath() : dbFilePath;

    // Cree le repertoire parent du fichier de base si necessaire
    // (ex: ~/.local/share/LocaLink sous Linux), sauf pour les bases
    // en memoire (":memory:") utilisees dans les tests.
    if (m_dbFilePath != QStringLiteral(":memory:")) {
        const QFileInfo dbFileInfo(m_dbFilePath);
        const QDir dbDir = dbFileInfo.dir();
        if (!dbDir.exists() && !dbDir.mkpath(QStringLiteral("."))) {
            m_lastError = QStringLiteral("Impossible de creer le repertoire de la base de donnees : %1")
                               .arg(dbDir.absolutePath());
            return false;
        }
    }

    if (QSqlDatabase::contains(m_connectionName)) {
        QSqlDatabase::removeDatabase(m_connectionName);
    }

    QSqlDatabase db = QSqlDatabase::addDatabase(kSqliteDriver, m_connectionName);
    db.setDatabaseName(m_dbFilePath);

    if (!db.open()) {
        m_lastError = db.lastError().text();
        QSqlDatabase::removeDatabase(m_connectionName);
        return false;
    }

    // SQLite desactive les contraintes de cles etrangeres par defaut :
    // on les active explicitement pour chaque connexion ouverte.
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
    QSqlQuery query(database());
    const bool ok = query.exec(QStringLiteral(
        "CREATE TABLE IF NOT EXISTS schema_migrations ("
        "  name TEXT PRIMARY KEY,"
        "  applied_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ");"));
    if (!ok) {
        m_lastError = query.lastError().text();
    }
    return ok;
}

QStringList DatabaseManager::pendingMigrationFiles() const
{
    // Le dossier Migrations/ est situe a cote des sources de ce module ;
    // on le cherche relativement au repertoire de l'executable puis,
    // a defaut, relativement aux sources (utile en developpement/tests
    // lances depuis le repertoire de build).
    QStringList candidateDirs = {
        QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("database/%1").arg(kMigrationsDirName)),
        // QFileInfo(__FILE__).dir() donne le repertoire contenant CE fichier source
        // (ex: .../database), independamment du repertoire de l'executable — utile
        // en developpement/tests lances depuis le repertoire de build.
        QFileInfo(QStringLiteral(__FILE__)).dir().filePath(kMigrationsDirName),
        // Copie embarquee dans l executable (database/CMakeLists.txt) : seule
        // source sur un poste ou l application a ete copiee sans ses sources.
        QStringLiteral(":/database/migrations"),
    };

    QDir migrationsDir;
    for (const QString &candidate : candidateDirs) {
        QDir dir(candidate);
        if (dir.exists()) {
            migrationsDir = dir;
            break;
        }
    }

    if (!migrationsDir.exists()) {
        return {};
    }

    QStringList alreadyApplied;
    {
        QSqlQuery query(database());
        if (query.exec(QStringLiteral("SELECT name FROM schema_migrations;"))) {
            while (query.next()) {
                alreadyApplied << query.value(0).toString();
            }
        }
    }

    const QStringList sqlFiles = migrationsDir.entryList(
        QStringList() << QStringLiteral("*.sql"), QDir::Files, QDir::Name);

    QStringList pending;
    for (const QString &fileName : sqlFiles) {
        if (!alreadyApplied.contains(fileName)) {
            pending << migrationsDir.filePath(fileName);
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
            // SQLite n'a pas de "ADD COLUMN IF NOT EXISTS" : certaines
            // migrations ajoutent une colonne qui peut deja exister
            // (schema deja a jour). On ignore ce cas precis plutot que
            // de faire echouer toute l'ouverture de la base.
            const bool isAddColumn = statement.contains(QStringLiteral("ADD COLUMN"), Qt::CaseInsensitive);
            const bool isDuplicateColumn = query.lastError().text().contains(
                QStringLiteral("duplicate column name"), Qt::CaseInsensitive);
            if (isAddColumn && isDuplicateColumn) {
                continue;
            }

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

QStringList DatabaseManager::splitStatements(const QString &sqlScript) const
{
    // Decoupage simple sur ';' : suffisant pour nos scripts de migration
    // (pas de procedures stockees ni de chaines contenant ';').
    // Les commentaires "-- ..." sont retires ligne par ligne avant decoupage.
    QString cleaned;
    for (const QString &line : sqlScript.split(QLatin1Char('\n'))) {
        const int commentIndex = line.indexOf(QStringLiteral("--"));
        cleaned += (commentIndex >= 0 ? line.left(commentIndex) : line) + QLatin1Char('\n');
    }

    QStringList statements;
    for (const QString &part : cleaned.split(QLatin1Char(';'))) {
        const QString trimmed = part.trimmed();
        if (!trimmed.isEmpty()) {
            statements << trimmed;
        }
    }
    return statements;
}

} // namespace database
