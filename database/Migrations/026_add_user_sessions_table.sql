-- Migration 026 : ajout de la table UserSessions pour "Se souvenir de moi"
-- (auto-login silencieux au demarrage, sans re-saisir le mot de passe).
--
-- Contrairement a Users, cette table n'est PAS synchronisee entre les
-- postes (pas d'entree dans SyncLog/SyncOperationRepository) : une session
-- persistante n'a de sens que sur la machine physique ou elle a ete creee
-- (cf. QSettings local, core::SettingsModel.rememberedSessionToken). Chaque
-- poste gere donc ses propres lignes UserSessions dans sa base locale.
--
-- Seul le hash SHA-256 du jeton est stocke (jamais le jeton en clair) :
-- meme un acces en lecture a la base ne permet pas de rejouer une session.
-- Le jeton brut n'existe que cote client (QSettings) et transite en memoire
-- le temps de l'appel C++ qui le genere (core::UserManager).

CREATE TABLE IF NOT EXISTS UserSessions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id       INTEGER NOT NULL REFERENCES Users(id) ON DELETE CASCADE,
    token_hash    TEXT NOT NULL UNIQUE,   -- SHA-256(jeton), jamais le jeton brut
    device_label  TEXT,                    -- Libelle optionnel (nom de poste)
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at    TEXT NOT NULL            -- Duree de vie fixe a la creation (30 jours)
);

CREATE INDEX IF NOT EXISTS idx_user_sessions_token_hash ON UserSessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON UserSessions(user_id);
