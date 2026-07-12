-- Migration 015 : ajoute l'identite du correspondant a l'historique des
-- transferts (peer_address/peer_name), sur le meme modele que CallHistory
-- (migration 013).
--
-- Constat : la table Transfers ne conservait jusqu'ici AUCUNE information
-- sur l'autre poste de l'echange - seulement sender_id/recipient_id, qui
-- referencent des comptes utilisateurs *locaux* et restent a -1 (NULL) des
-- qu'un des deux postes n'a pas de compte associe, ce qui est le cas
-- courant en P2P LAN (voir migration #012). Consequence : impossible de
-- savoir, dans l'historique, avec QUI un fichier a ete echange, et donc
-- impossible de regrouper les transferts par correspondant dans l'UI.
--
-- Simple ajout de colonnes nullables (pas de contrainte de cle etrangere,
-- donc pas besoin de reconstruire la table comme l'avait exige la
-- migration #012).

ALTER TABLE Transfers ADD COLUMN peer_address TEXT;
ALTER TABLE Transfers ADD COLUMN peer_name TEXT;

CREATE INDEX IF NOT EXISTS idx_transfers_peer_address ON Transfers(peer_address);
