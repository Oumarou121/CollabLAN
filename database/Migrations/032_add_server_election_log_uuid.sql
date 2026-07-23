-- Identifiant global d'une entree ServerElectionLog, necessaire pour la
-- diffuser entre postes (server_election_event) et l'appliquer de facon
-- idempotente cote reception (cf. ServerElectionRepository::applyRemoteLogEntry).
-- Meme pattern que 027_add_audit_event_uuid.sql pour AuditLogs.event_uuid.
ALTER TABLE ServerElectionLog ADD COLUMN log_uuid TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_server_election_log_log_uuid ON ServerElectionLog(log_uuid);
