-- Migration 012 : colonnes de synchronisation stables pour Users.
-- uuid sert de record_uuid inter-postes ; updated_at permet un LWW ligne entiere v1.

ALTER TABLE Users ADD COLUMN updated_at TEXT;
ALTER TABLE Users ADD COLUMN uuid TEXT;

UPDATE Users
SET updated_at = COALESCE(NULLIF(updated_at, ''), created_at, datetime('now'))
WHERE updated_at IS NULL OR updated_at = '';

UPDATE Users
SET uuid = lower(hex(randomblob(16)))
WHERE uuid IS NULL OR uuid = '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_uuid_unique ON Users(uuid);