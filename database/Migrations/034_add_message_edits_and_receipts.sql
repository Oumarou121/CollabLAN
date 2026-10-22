-- Migration #034 : modification/suppression de messages et accuses "remis"/"lu".
--
-- edited_at / deleted_at : dernier changement du contenu par son auteur. Un
-- message supprime garde sa ligne (ordre du fil, accuses) mais perd son texte.
--
-- MessageReceipts : pour chaque message et chaque destinataire (uuid), l'heure a
-- laquelle il a ete remis sur un de ses postes et l'heure a laquelle il l'a lu.
-- C'est aussi l'etat "lu" de l'utilisateur local (propre a chaque utilisateur,
-- et non plus un seul indicateur par poste). pending_send : accuse produit ici
-- et pas encore transmis au serveur (renvoye a la reconnexion).
--
-- Les messages deja lus avant cette migration sont marques lus pour tout le
-- monde (user_uuid '*'), sinon ils redeviendraient non lus.

ALTER TABLE Messages ADD COLUMN edited_at TEXT;
ALTER TABLE Messages ADD COLUMN deleted_at TEXT;

CREATE TABLE IF NOT EXISTS MessageReceipts (
    message_uuid  TEXT NOT NULL,
    user_uuid     TEXT NOT NULL,
    delivered_at  TEXT,
    read_at       TEXT,
    pending_send  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (message_uuid, user_uuid)
);

CREATE INDEX IF NOT EXISTS idx_message_receipts_pending ON MessageReceipts(pending_send);

INSERT OR IGNORE INTO MessageReceipts (message_uuid, user_uuid, delivered_at, read_at, pending_send)
SELECT uuid, '*', timestamp, timestamp, 0 FROM Messages
WHERE is_read = 1 AND uuid IS NOT NULL AND uuid <> '';
