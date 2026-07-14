-- Migration 021 : ajoute la colonne uuid a SharedFolders pour les
-- installations qui ont applique une version anterieure de la migration
-- 018 (avant l'ajout de la colonne uuid). Sans ca, SharedFolderRepository::
-- insert() (qui fait INSERT INTO SharedFolders (uuid, name, local_path,
-- owner_id, is_active) ...) echoue a la preparation de la requete
-- ("no such column: uuid"), non testee par le code, ce qui remonte plus
-- loin comme un trompeur "Parameter count mismatch" / "nombre de
-- parametres incorrect" des que bindValue()/exec() sont appeles sur la
-- requete non preparee.
--
-- SQLite ne permet pas d'ajouter une colonne UNIQUE directement via
-- ALTER TABLE ADD COLUMN : on ajoute la colonne (nullable), on la
-- remplit pour les lignes existantes avec un identifiant unique, puis on
-- cree un index UNIQUE separement (equivalent fonctionnel a UNIQUE).
--
-- Si la colonne existe deja (installations a jour, migration 020 dans
-- sa version courante), cette migration est censee etre un no-op sur
-- l'INDEX seulement -- mais ALTER TABLE ADD COLUMN echouerait si la
-- colonne existe deja. C'est attendu : sur une base a jour, ce fichier
-- ne devrait de toute facon jamais s'executer, la colonne existant deja
-- depuis la migration 020.

ALTER TABLE SharedFolders ADD COLUMN uuid TEXT;

UPDATE SharedFolders
SET uuid = lower(hex(randomblob(16)))
WHERE uuid IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_shared_folders_uuid ON SharedFolders(uuid);