-- Migration 016 : ajoute l'UUID stable du pair (peer_machine_id) a
-- l'historique des transferts.
--
-- Constat : sender_id/recipient_id restent NULL des qu'un des deux postes
-- n'a pas de compte Users local (cas courant en P2P LAN, voir migration
-- #012) - ce n'est pas un bug, TransferContext::sendFile() ne peut tout
-- simplement pas resoudre d'ID utilisateur pour un pair decouvert sur le
-- reseau. La migration #015 a ajoute peer_address/peer_name pour identifier
-- quand meme le correspondant, mais une adresse IP n'est pas stable
-- (DHCP, multi-interfaces) et un nom peut changer.
--
-- peer_machine_id comble ce manque : c'est l'UUID DiscoveryService::localId()
-- du pair, deja transmis dans l'en-tete du protocole de transfert (voir
-- TransferService::encodeHeader(), core::TransferManager::resolvePeerName())
-- mais jusqu'ici jamais persiste. Contrairement a sender_id/recipient_id,
-- il est renseigne pour la quasi-totalite des transferts LAN via
-- decouverte, cote reception comme cote emission.
--
-- Colonne nullable, pas de contrainte de cle etrangere (meme logique que
-- peer_address/peer_name, migration #015) : pas besoin de reconstruire la
-- table.

ALTER TABLE Transfers ADD COLUMN peer_machine_id TEXT;

CREATE INDEX IF NOT EXISTS idx_transfers_peer_machine_id ON Transfers(peer_machine_id);
