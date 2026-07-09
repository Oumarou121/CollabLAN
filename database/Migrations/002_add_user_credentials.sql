-- Migration 002 : identifiants locaux sur Users
-- (necessaire pour UserManager/UserRepository : creation et
-- authentification d'un utilisateur local).
--
-- NOTE : les colonnes password_hash / password_salt sont deja presentes
-- dans 001_initial_schema.sql (elles y avaient ete ajoutees directement).
-- Cette migration ne fait donc plus que garantir l'unicite du nom
-- d'utilisateur ; les anciens ALTER TABLE ADD COLUMN ont ete retires car
-- ils provoquaient une erreur "duplicate column name" au demarrage.
--
-- On n'edite jamais une migration deja appliquee (001_initial_schema.sql) :
-- toute evolution de schema passe par un nouveau fichier numerote.

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_name_unique ON Users(name);
