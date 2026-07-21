-- Identifiant global d'un evenement d'audit, partageable entre bases.
ALTER TABLE AuditLogs ADD COLUMN event_uuid TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_audit_logs_event_uuid ON AuditLogs(event_uuid);
