-- Migration #031 : introduit un vrai etat pending/authorized/revoked pour
-- les machines (voir plan "Machines autorisees avec etat pending/authorized/revoked").
--
-- La colonne `authorized` est conservee pour compatibilite ascendante avec
-- le code existant, mais `status` devient la source de verite metier :
--   - authorized = 1                                  -> status = 'authorized'
--   - authorized = 0 + raison "autorisation requise"   -> status = 'pending'
--   - authorized = 0 (autre raison)                    -> status = 'revoked'

ALTER TABLE AuthorizedMachines ADD COLUMN status TEXT NOT NULL DEFAULT 'authorized';

UPDATE AuthorizedMachines
SET status = CASE
    WHEN authorized = 1 THEN 'authorized'
    WHEN authorized = 0 AND reason LIKE '%autorisation requise%' THEN 'pending'
    ELSE 'revoked'
END;

CREATE INDEX IF NOT EXISTS idx_authorized_machines_status
ON AuthorizedMachines(status);
