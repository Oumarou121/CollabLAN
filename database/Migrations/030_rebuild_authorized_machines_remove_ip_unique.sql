CREATE TABLE AuthorizedMachines_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ip_address TEXT NOT NULL DEFAULT '',
    hostname TEXT,
    authorized INTEGER NOT NULL DEFAULT 1,
    added_by INTEGER REFERENCES Users(id),
    added_at TEXT NOT NULL DEFAULT (datetime('now')),
    reason TEXT,
    machine_uuid TEXT,
    certificate_fingerprint TEXT,
    last_ip_address TEXT
);

INSERT INTO AuthorizedMachines_new (
    id,
    ip_address,
    hostname,
    authorized,
    added_by,
    added_at,
    reason,
    machine_uuid,
    certificate_fingerprint,
    last_ip_address
)
SELECT
    id,
    ip_address,
    hostname,
    authorized,
    added_by,
    added_at,
    reason,
    machine_uuid,
    certificate_fingerprint,
    last_ip_address
FROM AuthorizedMachines;

DROP TABLE AuthorizedMachines;

ALTER TABLE AuthorizedMachines_new RENAME TO AuthorizedMachines;

CREATE INDEX IF NOT EXISTS idx_authorized_machines_ip
ON AuthorizedMachines(ip_address);

CREATE INDEX IF NOT EXISTS idx_authorized_machines_authorized
ON AuthorizedMachines(authorized);

CREATE UNIQUE INDEX IF NOT EXISTS idx_authorized_machines_uuid
ON AuthorizedMachines(machine_uuid)
WHERE machine_uuid IS NOT NULL AND machine_uuid <> '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_authorized_machines_certificate
ON AuthorizedMachines(certificate_fingerprint)
WHERE certificate_fingerprint IS NOT NULL AND certificate_fingerprint <> '';

CREATE INDEX IF NOT EXISTS idx_authorized_machines_machine_uuid
ON AuthorizedMachines(machine_uuid);