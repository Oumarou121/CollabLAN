-- Migration 018 : ajout du module "Shared Folder" (partage de dossiers
-- façon explorateur Windows, cf. docs de conception fournies).
--
-- SharedFolders : un dossier local partage par ce poste. local_path est
-- l'emplacement reel sur le disque de CE poste (chaque poste peut avoir
-- un chemin local different pour le meme dossier partage logique, d'ou
-- l'usage d'un uuid stable plutot que le chemin comme identifiant
-- inter-postes).
--
-- SharedFiles : snapshot des fichiers connus d'un SharedFolder. relative_path
-- est le chemin relatif a la racine du dossier partage (ex: "Docs/cahier.pdf"),
-- independant du chemin absolu local. hash/size/last_modified/version
-- permettent de detecter des changements sans redemarrer une synchronisation
-- complete. deleted est un "tombstone" (suppression logique) plutot qu'un
-- DELETE physique, necessaire pour propager une suppression aux autres
-- postes lors d'une future synchronisation reseau.
--
-- SyncOperations : historique des operations (Create/Update/Delete/Rename)
-- sur les fichiers partages, utilise par un futur SyncEngine/FolderWatcher
-- pour permettre a un poste revenu en ligne de rejouer les operations
-- manquees. Aucune logique de synchronisation reseau n'est branchee dans
-- cette migration : elle prepare uniquement le modele de donnees.

CREATE TABLE IF NOT EXISTS SharedFolders (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid          TEXT NOT NULL UNIQUE,
    name          TEXT NOT NULL,
    local_path    TEXT NOT NULL,
    owner_id      INTEGER REFERENCES Users(id),
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    is_active     INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_shared_folders_owner_id ON SharedFolders(owner_id);

CREATE TABLE IF NOT EXISTS SharedFiles (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id      INTEGER NOT NULL REFERENCES SharedFolders(id) ON DELETE CASCADE,
    relative_path  TEXT NOT NULL,
    hash           TEXT NOT NULL DEFAULT '',
    size           INTEGER NOT NULL DEFAULT 0,
    last_modified  TEXT NOT NULL DEFAULT (datetime('now')),
    version        INTEGER NOT NULL DEFAULT 1,
    deleted        INTEGER NOT NULL DEFAULT 0,
    UNIQUE(folder_id, relative_path)
);

CREATE INDEX IF NOT EXISTS idx_shared_files_folder_id ON SharedFiles(folder_id);

CREATE TABLE IF NOT EXISTS SyncOperations (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    type         TEXT NOT NULL, -- 'Create' | 'Update' | 'Delete' | 'Rename'
    file_id      INTEGER NOT NULL REFERENCES SharedFiles(id) ON DELETE CASCADE,
    version      INTEGER NOT NULL DEFAULT 1,
    machine_id   TEXT NOT NULL DEFAULT '',
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sync_operations_file_id ON SyncOperations(file_id);
