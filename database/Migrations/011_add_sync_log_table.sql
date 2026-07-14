-- Migration 011 : Journal de synchronisation pour la reconciliation post-panne
-- (HYBRID_SERVER_FAILOVER.md, section 3 : "Les tables SyncLog / PeerSyncState / colonnes
-- uuid, updated_at, origin_machine_id du document precedent sont reutilisees telles quelles :
-- c'est ce qui permet la reconciliation a la reprise.")
--
-- Le document SYNC_ARCHITECTURE_PROPOSAL.md (P2P) n'est pas present dans ce depot ; ce
-- schema est une reconstruction minimale mais suffisante pour le protocole de reconciliation
-- decrit en section 7 : chaque ecriture faite par un TEMP_SERVER pendant une panne est
-- journalisee ici, puis rejouee (LWW horodate + lamport_clock) par le SERVER officiel a son
-- retour, via sync_request / sync_batch / sync_ack (SyncService).

CREATE TABLE IF NOT EXISTS SyncLog (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_uuid         TEXT NOT NULL UNIQUE,   -- identifiant stable de l'entree (dedup a la fusion)
    table_name         TEXT NOT NULL,          -- table applicative concernee (Messages, Groups, ...)
    record_uuid        TEXT NOT NULL,          -- identifiant de l'enregistrement modifie
    operation          TEXT NOT NULL,          -- 'INSERT' | 'UPDATE' | 'DELETE'
    payload_json       TEXT,                   -- etat complet de l'enregistrement (JSON), NULL pour DELETE
    lamport_clock      INTEGER NOT NULL DEFAULT 0,  -- horloge logique pour departager les conflits LWW
    epoch              INTEGER NOT NULL,       -- epoch (ServerElection) durant lequel l'ecriture a eu lieu
    origin_machine_id  TEXT NOT NULL,          -- machine_uuid ayant produit l'ecriture (le TEMP_SERVER en panne)
    updated_at         TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sync_log_epoch ON SyncLog(epoch);
CREATE INDEX IF NOT EXISTS idx_sync_log_origin ON SyncLog(origin_machine_id);
CREATE INDEX IF NOT EXISTS idx_sync_log_record ON SyncLog(table_name, record_uuid);

-- Dernier epoch connu de chaque pair distant deja reconcilie, pour eviter de
-- redemander/rejouer deux fois le meme lot en cas de sync_request repete.
CREATE TABLE IF NOT EXISTS PeerSyncState (
    machine_uuid       TEXT PRIMARY KEY,
    last_synced_epoch  INTEGER NOT NULL DEFAULT 0,
    last_synced_at     TEXT
);
