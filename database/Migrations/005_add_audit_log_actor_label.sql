-- Migration 005 : ajoute une colonne d'acteur "libre" au journal d'audit.
--
-- 001_initial_schema.sql definit AuditLogs.user_id comme une reference
-- vers Users(id), ce qui suppose un utilisateur authentifie connu. Or
-- l'issue #62 exige aussi d'auditer des evenements sans utilisateur
-- authentifie (ex: tentative de connexion refusee d'un poste inconnu du
-- LAN). actor_label porte alors une identification lisible de l'acteur
-- (adresse IP, nom de poste...) quand user_id est NULL.

ALTER TABLE AuditLogs ADD COLUMN actor_label TEXT;
