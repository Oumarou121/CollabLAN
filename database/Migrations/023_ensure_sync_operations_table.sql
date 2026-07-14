-- Migration 023 : garantit la presence de la table SyncOperations (et de son
-- index) independamment de l'historique d'application de la migration 020.
--
-- CONTEXTE DU BUG CORRIGE : le systeme de migration (DatabaseManager) suit
-- les fichiers deja executes PAR NOM DE FICHIER (table schema_migrations),
-- jamais par contenu. Si, sur un poste donne, "018_add_shared_folders.sql"
-- a ete marque comme applique AVANT que la definition de SyncOperations n'y
-- soit ajoutee (ou pour toute autre raison ou ce CREATE TABLE precis n'a pas
-- pris sur cette base), la table SyncOperations n'existe tout simplement pas
-- sur ce poste -- alors que SharedFolders/SharedFiles, definis plus haut
-- dans le meme fichier, existent bien. Consequence observee : le journal
-- "Historique" d'un dossier partage reste perpetuellement vide (aucune
-- ligne ne peut jamais etre inseree dans une table qui n'existe pas), sans
-- la moindre erreur visible cote UI puisque les appels a
-- SyncOperationRepository::insert() echouaient silencieusement (voir aussi
-- le correctif apporte a FolderSyncService pour logger ces echecs).
--
-- CREATE TABLE IF NOT EXISTS est idempotent : sans effet si la table existe
-- deja avec la bonne definition (poste non affecte), et corrige les postes
-- affectes sans toucher a leurs autres tables.

CREATE TABLE IF NOT EXISTS SyncOperations (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    type               TEXT NOT NULL, -- 'Create' | 'Update' | 'Delete' | 'Rename'
    file_id            INTEGER NOT NULL REFERENCES SharedFiles(id) ON DELETE CASCADE,
    old_relative_path  TEXT,
    version            INTEGER NOT NULL DEFAULT 1,
    machine_id         TEXT NOT NULL DEFAULT '',
    created_at         TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sync_operations_file_id ON SyncOperations(file_id);
