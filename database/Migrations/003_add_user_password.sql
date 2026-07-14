-- Migration 003 : garantit l'unicite du nom d'utilisateur (identifiant
-- de connexion). Les colonnes password_hash/password_salt existent deja
-- depuis 001_initial_schema.sql. Le compte admin par defaut est seede
-- au demarrage de l'application (voir Application::initialize()) plutot
-- qu'en dur ici, afin que son hash soit toujours produit par
-- core::PasswordHasher (salt genere aleatoirement, jamais une valeur
-- statique dans le SQL).

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_name_unique ON Users(name);