-- Migration : authentification locale des utilisateurs (issue #16)
-- Ajoute le hash du mot de passe sur Users et garantit l'unicite du nom
-- d'utilisateur, utilise comme identifiant de connexion par LoginView/UserManager.

ALTER TABLE Users ADD COLUMN password_hash TEXT NOT NULL DEFAULT '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_name ON Users(name);

-- Compte admin par defaut, utile en developpement/demo tant qu'aucun
-- ecran d'inscription n'existe. Mot de passe : "admin123"
-- (hash = sha256(salt + password), format stocke par core::PasswordHasher).
INSERT OR IGNORE INTO Users (name, ip_address, status, is_admin, password_hash)
VALUES (
    'admin',
    '127.0.0.1',
    'offline',
    1,
    'c9f1a3e7b2d4406f9a0c1e5f7b3d9a21:5ee16163c2e1f0f2df2715adb063f5642f467b21250c8304bbbe65b793a525bf'
);
