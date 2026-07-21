ALTER TABLE AuthorizedMachines ADD COLUMN machine_uuid TEXT;
UPDATE AuthorizedMachines SET machine_uuid = lower(hex(randomblob(16))) WHERE machine_uuid IS NULL OR machine_uuid = '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_authorized_machines_uuid ON AuthorizedMachines(machine_uuid);
