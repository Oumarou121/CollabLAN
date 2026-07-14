-- Migration 013 : colonnes uuid stables pour Messages, Groups et Conversations
-- (HYBRID_SERVER_FAILOVER.md section 7 : la reconciliation post-panne ne peut
-- utiliser l'id local AUTOINCREMENT comme record_uuid, deux bases SQLite
-- independantes n'ayant aucune raison de faire coincider leurs ids).
--
-- Meme principe que la migration 012 pour Users : on ajoute une colonne
-- uuid, on la remplit pour les lignes deja existantes, puis on pose un
-- index unique. Sans cette migration, GroupRepository::insert()/getById()/
-- findByUuid() et SyncLogRepository::applyMessageEntry()/
-- ensureConversationByUuid() referencent une colonne "uuid" qui n'existe
-- jamais en base.

ALTER TABLE Conversations ADD COLUMN uuid TEXT;

UPDATE Conversations
SET uuid = lower(hex(randomblob(16)))
WHERE uuid IS NULL OR uuid = '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_uuid_unique ON Conversations(uuid);

ALTER TABLE Groups ADD COLUMN uuid TEXT;

UPDATE Groups
SET uuid = lower(hex(randomblob(16)))
WHERE uuid IS NULL OR uuid = '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_groups_uuid_unique ON Groups(uuid);

ALTER TABLE Messages ADD COLUMN uuid TEXT;

UPDATE Messages
SET uuid = lower(hex(randomblob(16)))
WHERE uuid IS NULL OR uuid = '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_uuid_unique ON Messages(uuid);
