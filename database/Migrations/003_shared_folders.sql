-- Migration 003 : fonctionnalite "Shared Folder" (partage de dossiers,
-- inspire du partage de dossiers Windows, avec synchronisation entre
-- postes du reseau local). Voir docs/ARCHITECTURE.md.

CREATE TABLE IF NOT EXISTS SharedFolders (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL,
    local_path    TEXT NOT NULL,
    owner_id      INTEGER NOT NULL REFERENCES Users(id),
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    is_active     INTEGER NOT NULL DEFAULT 1
);

-- Un meme fichier (chemin relatif) n'existe qu'une fois par dossier partage.
CREATE TABLE IF NOT EXISTS SharedFiles (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id      INTEGER NOT NULL REFERENCES SharedFolders(id),
    relative_path  TEXT NOT NULL,
    hash           TEXT NOT NULL DEFAULT '',
    size           INTEGER NOT NULL DEFAULT 0,
    last_modified  TEXT NOT NULL DEFAULT (datetime('now')),
    version        INTEGER NOT NULL DEFAULT 1,
    deleted        INTEGER NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sharedfiles_folder_path
    ON SharedFiles(folder_id, relative_path);

-- Historique des operations (Create/Update/Delete/Rename), utilise pour
-- rattraper un poste qui revient en ligne apres une coupure.
CREATE TABLE IF NOT EXISTS SyncOperations (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    type          TEXT NOT NULL,
    file_id       INTEGER NOT NULL REFERENCES SharedFiles(id),
    version       INTEGER NOT NULL,
    machine_id    TEXT NOT NULL,
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_syncoperations_file ON SyncOperations(file_id);
