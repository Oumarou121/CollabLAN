-- Les decisions TLS sont directionnelles : la confiance d'un client envers
-- un serveur ne doit jamais etre synchronisee ni partagee avec la liste des
-- clients admis par ce serveur.

CREATE TABLE IF NOT EXISTS AuthorizedClients (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    machine_uuid            TEXT,
    certificate_fingerprint TEXT NOT NULL UNIQUE,
    ip_address              TEXT NOT NULL DEFAULT '',
    last_ip_address         TEXT NOT NULL DEFAULT '',
    hostname                TEXT NOT NULL DEFAULT '',
    authorized              INTEGER NOT NULL DEFAULT 0,
    status                  TEXT NOT NULL DEFAULT 'pending',
    added_by                INTEGER REFERENCES Users(id),
    added_at                TEXT NOT NULL DEFAULT (datetime('now')),
    reason                  TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_authorized_clients_status
ON AuthorizedClients(status);

CREATE TABLE IF NOT EXISTS TrustedServers (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    server_uuid             TEXT,
    certificate_fingerprint TEXT NOT NULL UNIQUE,
    ip_address              TEXT NOT NULL DEFAULT '',
    last_ip_address         TEXT NOT NULL DEFAULT '',
    hostname                TEXT NOT NULL DEFAULT '',
    status                  TEXT NOT NULL DEFAULT 'pending',
    first_seen_at           TEXT NOT NULL DEFAULT (datetime('now')),
    last_seen_at            TEXT NOT NULL DEFAULT (datetime('now')),
    reason                  TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_trusted_servers_status
ON TrustedServers(status);
