-- Migration 004 : Ajout de la table AuditLogs pour le journal d'audit (issue #65)

CREATE TABLE IF NOT EXISTS AuditLogs (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp     TEXT NOT NULL DEFAULT (datetime('now')),
    event_type   TEXT NOT NULL,           -- Type d'événement (ex: "connection", "message", "transfer", "call")
    description  TEXT,                    -- Description lisible de l'événement
    user_id      INTEGER REFERENCES Users(id),  -- ID de l'utilisateur authentifié (optionnel)
    actor_label  TEXT,                    -- Étiquette de l'acteur (adresse IP, nom de poste, etc.)
    details      TEXT                      -- Détails supplémentaires au format JSON (optionnel)
);

-- Index pour optimiser les requêtes fréquentes
CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON AuditLogs(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_event_type ON AuditLogs(event_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON AuditLogs(user_id);
