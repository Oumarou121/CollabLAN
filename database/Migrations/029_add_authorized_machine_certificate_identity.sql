ALTER TABLE AuthorizedMachines ADD COLUMN certificate_fingerprint TEXT;
ALTER TABLE AuthorizedMachines ADD COLUMN last_ip_address TEXT;
UPDATE AuthorizedMachines SET last_ip_address = ip_address WHERE last_ip_address IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_authorized_machines_certificate ON AuthorizedMachines(certificate_fingerprint) WHERE certificate_fingerprint IS NOT NULL AND certificate_fingerprint <> '';
CREATE INDEX IF NOT EXISTS idx_authorized_machines_machine_uuid ON AuthorizedMachines(machine_uuid);
