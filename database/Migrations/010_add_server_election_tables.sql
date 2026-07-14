-- Migration 010 : Architecture hybride avec bascule automatique de serveur (HYBRID_SERVER_FAILOVER.md)
-- Ajoute le suivi du rôle courant du poste (SERVER / CLIENT / TEMP_SERVER) et l'historique des bascules.

CREATE TABLE IF NOT EXISTS ServerElection (
    id                  INTEGER PRIMARY KEY CHECK (id = 1),  -- une seule ligne (singleton)
    current_role        TEXT NOT NULL DEFAULT 'CLIENT',       -- SERVER | CLIENT | TEMP_SERVER
    epoch               INTEGER NOT NULL DEFAULT 0,
    active_server_ip    TEXT,
    active_server_uuid  TEXT,
    priority_weight     INTEGER NOT NULL DEFAULT 100,         -- plus petit = plus prioritaire pour devenir TEMP_SERVER
    last_heartbeat_seen TEXT
);

-- Ligne singleton initiale : poste CLIENT par défaut, epoch 0.
INSERT OR IGNORE INTO ServerElection (id, current_role, epoch, priority_weight)
VALUES (1, 'CLIENT', 0, 100);

-- Historique des bascules, utile pour audit et debug (AdminView.qml)
CREATE TABLE IF NOT EXISTS ServerElectionLog (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    event          TEXT NOT NULL,      -- 'HEARTBEAT_LOST' | 'TEMP_PROMOTED' | 'SERVER_RECONCILED' | 'SERVER_RESTORED'
    epoch          INTEGER NOT NULL,
    machine_uuid   TEXT NOT NULL,
    created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_server_election_log_created_at ON ServerElectionLog(created_at);
