-- Migration 012 : corrige la persistance de l'historique des transferts.
--
-- Deux problemes constates en usage reel (transferts LAN entre postes sans
-- compte utilisateur correspondant cote destinataire) :
--
-- 1. sender_id/recipient_id etaient "NOT NULL REFERENCES Users(id)". Or
--    core::TransferContext::sendFile() ne peut jamais resoudre de
--    recipientId pour un poste decouvert sur le reseau (aucun compte
--    utilisateur associe a un pair distant) et transmet -1 dans ce cas.
--    Avec PRAGMA foreign_keys=ON (actif dans toute l'application), chaque
--    INSERT avec sender_id/recipient_id = -1 echouait silencieusement la
--    contrainte de cle etrangere : TransferRepository::create() renvoyait
--    -1 et TransferManager abandonnait l'enregistrement (voir son
--    qWarning()). Resultat : la quasi-totalite des transferts reseau
--    n'atteignaient jamais la table Transfers, donc aucun historique,
--    meme pendant la session en cours (independamment du redemarrage).
--    Ces colonnes deviennent nullables : un expediteur/destinataire
--    "inconnu" est desormais stocke comme NULL plutot que refuse.
--
-- 2. Aucune colonne ne conservait l'emplacement du fichier sur le disque
--    (chemin source pour un envoi, chemin de destination pour une
--    reception), rendant impossible un bouton "ouvrir le dossier
--    contenant le fichier" sur un transfert de l'historique.

CREATE TABLE Transfers_new (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_id     INTEGER REFERENCES Users(id),
    recipient_id  INTEGER REFERENCES Users(id),
    file_name     TEXT NOT NULL,
    file_size     INTEGER NOT NULL,
    file_path     TEXT,
    status        TEXT NOT NULL DEFAULT 'pending',
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO Transfers_new (id, sender_id, recipient_id, file_name, file_size, status, created_at)
SELECT id, sender_id, recipient_id, file_name, file_size, status, created_at FROM Transfers;

DROP TABLE Transfers;
ALTER TABLE Transfers_new RENAME TO Transfers;
