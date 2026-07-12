-- Migration 017 : remplace definitivement sender_id/recipient_id (comptes
-- Users locaux, INTEGER) par sender_uuid/recipient_uuid (TEXT, Users.uuid)
-- sur la table Transfers.
--
-- Pourquoi : sender_id/recipient_id restent NULL pour la quasi-totalite
-- des transferts P2P LAN, un pair decouvert sur le reseau n'ayant pas
-- systematiquement de compte utilisateur local associe (voir migrations
-- #012 et #016 : peer_machine_id apportait deja un identifiant fiable
-- pour le POSTE, cette migration fait de meme pour le COMPTE eventuel en
-- s'alignant sur Users.uuid, deja utilise comme identifiant stable
-- inter-postes depuis la migration #010). Garder id integer AUTOINCREMENT
-- comme cle primaire locale pour ces colonnes n'apportait rien et
-- obligeait TransferRepository/TransferService/TransferManager a jongler
-- avec un sentinel -1 "inconnu" en plus du NULL SQL.
--
-- SQLite ne supporte pas DROP COLUMN sur une contrainte REFERENCES
-- (deja le cas ici : plus de FK, cf. migration #012), mais on reconstruit
-- quand meme la table pour supprimer proprement sender_id/recipient_id
-- plutot que de les laisser trainer inutilisees.

CREATE TABLE Transfers_new (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_uuid     TEXT,
    recipient_uuid  TEXT,
    file_name       TEXT NOT NULL,
    file_size       INTEGER NOT NULL,
    file_path       TEXT,
    peer_address    TEXT,
    peer_name       TEXT,
    peer_machine_id TEXT,
    status          TEXT NOT NULL DEFAULT 'pending',
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Backfill : retrouve l'UUID de chaque compte via l'ancien sender_id/
-- recipient_id (Users.id -> Users.uuid). Un id sans correspondance (ou
-- NULL) donne NULL dans la nouvelle colonne, comme avant.
INSERT INTO Transfers_new (
    id, sender_uuid, recipient_uuid, file_name, file_size, file_path,
    peer_address, peer_name, peer_machine_id, status, created_at
)
SELECT
    t.id,
    su.uuid,
    ru.uuid,
    t.file_name,
    t.file_size,
    t.file_path,
    t.peer_address,
    t.peer_name,
    t.peer_machine_id,
    t.status,
    t.created_at
FROM Transfers t
LEFT JOIN Users su ON su.id = t.sender_id
LEFT JOIN Users ru ON ru.id = t.recipient_id;

DROP TABLE Transfers;
ALTER TABLE Transfers_new RENAME TO Transfers;

CREATE INDEX IF NOT EXISTS idx_transfers_sender_uuid ON Transfers(sender_uuid);
CREATE INDEX IF NOT EXISTS idx_transfers_recipient_uuid ON Transfers(recipient_uuid);
CREATE INDEX IF NOT EXISTS idx_transfers_peer_address ON Transfers(peer_address);
CREATE INDEX IF NOT EXISTS idx_transfers_peer_machine_id ON Transfers(peer_machine_id);
