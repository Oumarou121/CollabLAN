#ifndef DATABASE_SETTINGSREPOSITORY_H
#define DATABASE_SETTINGSREPOSITORY_H

#include <QSqlDatabase>
#include <QString>

#include "models/Settings.h"

namespace database {

/**
 * @brief Acces aux donnees de la table Settings (cle/valeur).
 *
 * La table Settings stocke chaque parametre sous la forme d'une paire
 * (key, value). Ce repository expose une API haut niveau basee sur
 * models::Settings (load/save) ainsi qu'un acces generique cle/valeur
 * pour d'eventuels parametres futurs.
 */
class SettingsRepository {
public:
    explicit SettingsRepository(QSqlDatabase database);
    ~SettingsRepository();

    /**
     * @brief Recharge les parametres depuis la base.
     *
     * Toute cle absente de la table est remplacee par sa valeur par
     * defaut (voir models::Settings::defaults()).
     */
    models::Settings load() const;

    /**
     * @brief Persiste l'ensemble des parametres (upsert clé par clé).
     * @return true si toutes les cles ont ete ecrites avec succes.
     */
    bool save(const models::Settings &settings);

    /**
     * @brief Lecture generique d'une valeur par sa cle.
     * @return la valeur stockee, ou defaultValue si la cle est absente.
     */
    QString getValue(const QString &key, const QString &defaultValue = QString()) const;

    /**
     * @brief Ecriture generique d'une valeur (insert ou update).
     */
    bool setValue(const QString &key, const QString &value);

    QString lastError() const;

private:
    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_SETTINGSREPOSITORY_H
