-- Migration #039 : identite des postes et adresses lisibles.
--
-- AuthorizedClients.last_user_uuid : dernier compte vu sur ce poste (annonces
-- de decouverte). L'interface affiche le nom de cette personne, puis le nom du
-- poste, meme quand le poste est hors ligne -- auparavant son adresse.
ALTER TABLE AuthorizedClients ADD COLUMN last_user_uuid TEXT NOT NULL DEFAULT '';

-- Adresses IPv4 enregistrees au format IPv6 par les sockets double pile
-- ("::ffff:192.168.1.21") : ramenees a "192.168.1.21". Elles etaient affichees
-- telles quelles comme nom de poste et empechaient de reconnaitre un poste
-- en ligne (la decouverte utilise la forme IPv4).
UPDATE AuthorizedClients SET ip_address = substr(ip_address, 8) WHERE ip_address LIKE '::ffff:%';
UPDATE AuthorizedClients SET last_ip_address = substr(last_ip_address, 8) WHERE last_ip_address LIKE '::ffff:%';
UPDATE TrustedServers SET ip_address = substr(ip_address, 8) WHERE ip_address LIKE '::ffff:%';
UPDATE TrustedServers SET last_ip_address = substr(last_ip_address, 8) WHERE last_ip_address LIKE '::ffff:%';
UPDATE CallHistory SET peer_address = substr(peer_address, 8) WHERE peer_address LIKE '::ffff:%';
UPDATE Transfers SET peer_address = substr(peer_address, 8) WHERE peer_address LIKE '::ffff:%';
UPDATE AuditLogs SET actor_label = replace(actor_label, '::ffff:', ''),
                     description = replace(description, '::ffff:', '')
 WHERE actor_label LIKE '%::ffff:%' OR description LIKE '%::ffff:%';
