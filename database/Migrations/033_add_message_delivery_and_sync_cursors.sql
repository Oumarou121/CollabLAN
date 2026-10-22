-- Migration #033 : file d'envoi des messages et synchronisation incrementale.
--
-- delivery_status : 'pending' tant que le serveur n'a pas accuse reception du
-- message (poste hors connexion, ou envoi en cours), 'sent' ensuite. Les
-- messages deja en base sont consideres comme envoyes (aucun renvoi).
--
-- SyncCursors : dernier identifiant de SyncLog recu d'un serveur, par
-- utilisateur (le serveur filtre le journal selon l'utilisateur identifie).
-- Permet de ne demander que la suite du journal a chaque connexion.

ALTER TABLE Messages ADD COLUMN delivery_status TEXT NOT NULL DEFAULT 'sent';

CREATE INDEX IF NOT EXISTS idx_messages_delivery_status ON Messages(delivery_status);

CREATE TABLE IF NOT EXISTS SyncCursors (
    server_key   TEXT NOT NULL,
    user_uuid    TEXT NOT NULL DEFAULT '',
    last_log_id  INTEGER NOT NULL DEFAULT 0,
    updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (server_key, user_uuid)
);
