#ifndef DATABASE_DATABASEMANAGER_H
#define DATABASE_DATABASEMANAGER_H

#include <QString>
#include <QSqlDatabase>

namespace database {

/**
 * @brief Ouverture/fermeture de la base SQLite, execution des migrations.
 */
class DatabaseManager {
public:
    DatabaseManager();
    explicit DatabaseManager(QString databasePath, QString connectionName = QStringLiteral("collablan"));
    ~DatabaseManager();

    // Non copiable (une connexion SQL n'a pas vocation a etre dupliquee).
    DatabaseManager(const DatabaseManager &) = delete;
    DatabaseManager &operator=(const DatabaseManager &) = delete;

    /**
     * @brief Ouvre la base de donnees et execute les migrations si necessaire.
     * @return true si la base est prete a l'emploi.
     */
    bool open();

    /**
     * @brief Ferme proprement la connexion a la base de donnees.
     */
    void close();

    bool isOpen() const;

    QString databasePath() const;
    QString lastError() const;

    QSqlDatabase database() const;

private:
    bool runMigrations();
    bool executeSqlScript(const QString &sqlFilePath);

    QString m_databasePath;
    QString m_connectionName;
    QString m_lastError;
};

} // namespace database

#endif // DATABASE_DATABASEMANAGER_H
