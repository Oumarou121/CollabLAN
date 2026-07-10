-- Migration 006 : Ajout de la table AuthorizedMachines pour la gestion des machines autorisées (issue #68)

CREATE TABLE IF NOT EXISTS AuthorizedMachines (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    ip_address    TEXT NOT NULL UNIQUE,  -- Adresse IP de la machine
    hostname      TEXT,                    -- Nom d'hôte (optionnel)
    authorized    INTEGER NOT NULL DEFAULT 1,  -- 1 = autorisée, 0 = révoquée
    added_by      INTEGER REFERENCES Users(id),  -- ID de l'admin qui a ajouté/revoké
    added_at      TEXT NOT NULL DEFAULT (datetime('now')),
    reason        TEXT                     -- Raison de l'autorisation/ révocation
);

-- Index pour optimiser les requêtes fréquentes
CREATE INDEX IF NOT EXISTS idx_authorized_machines_ip ON AuthorizedMachines(ip_address);
CREATE INDEX IF NOT EXISTS idx_authorized_machines_authorized ON AuthorizedMachines(authorized);

-- Par défaut, aucune restriction : toutes les machines sont autorisées.
-- Les administrateurs peuvent ajouter des restrictions en ajoutant des entrées
-- avec authorized = 0 pour bloquer des machines spécifiques.
