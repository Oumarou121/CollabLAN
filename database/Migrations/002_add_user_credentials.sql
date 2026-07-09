-- Migration 002 : ajout des identifiants locaux sur Users
-- (necessaire pour UserManager/UserRepository : creation et
-- authentification d'un utilisateur local).
--
-- On n'edite jamais une migration deja appliquee (001_initial_schema.sql) :
-- toute evolution de schema passe par un nouveau fichier numerote.

ALTER TABLE Users ADD COLUMN password_hash TEXT NOT NULL DEFAULT '';
ALTER TABLE Users ADD COLUMN password_salt TEXT NOT NULL DEFAULT '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_name_unique ON Users(name);
