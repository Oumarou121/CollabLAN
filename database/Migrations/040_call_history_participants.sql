-- Migration #040 : appels de groupe.
--
-- Un appel de groupe (4 personnes au plus) tient sur une seule ligne du
-- journal : participants liste les adresses de toutes les autres personnes
-- de l'appel (invitees ou rencontrees), separees par des virgules.
-- peer_address reste le premier correspondant (celui qu'on a appele, ou qui
-- a invite). Vide pour les appels a deux enregistres avant cette migration.
ALTER TABLE CallHistory ADD COLUMN participants TEXT NOT NULL DEFAULT '';
