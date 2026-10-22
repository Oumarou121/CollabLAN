-- Migration #036 : rattrapage du journal d'audit et des retraits d'acces.
--
-- AuditLogs.pending_send : evenement enregistre ailleurs que sur le serveur
-- officiel (client, serveur de secours) et pas encore confirme par lui
-- ("audit_ack") ; transmis a la reconnexion. Les evenements deja en base ne
-- sont pas renvoyes.
--
-- FolderAccessRevocations : retraits d'acces a un dossier partage connus de
-- ce poste. Le serveur les rejoue au rattrapage ("folder_catchup_batch") : un
-- poste absent au moment du retrait le rattrape a son retour (auparavant il
-- gardait le dossier indefiniment). Un nouvel acces efface le retrait.

ALTER TABLE AuditLogs ADD COLUMN pending_send INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS FolderAccessRevocations (
    folder_uuid  TEXT NOT NULL,
    user_uuid    TEXT NOT NULL,
    revoked_at   TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (folder_uuid, user_uuid)
);
