-- Migration 004 : Lie chaque groupe a une conversation, pour reutiliser
-- telle quelle la messagerie (Messages.conversationId) pour les groupes.
--
-- NB : 001_initial_schema.sql cree Groups(id, name, created_at) SANS
-- colonne owner_id, alors que core/GroupManager.cpp (INSERT INTO Groups
-- (name, owner_id) ...) et core/GroupModel en dependent depuis le debut.
-- Sans cette colonne, GroupManager::createGroup() echoue des le premier
-- INSERT sur une base "reelle" (hors tests, qui recreent la table a la
-- main). On la rajoute ici avec cette migration puisqu'elle touche deja
-- Groups.

ALTER TABLE Groups ADD COLUMN owner_id INTEGER NOT NULL DEFAULT 0;

ALTER TABLE Groups ADD COLUMN conversation_id INTEGER REFERENCES Conversations(id);
