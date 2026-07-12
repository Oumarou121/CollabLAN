-- Migration 020 : gestion des permissions d'acces aux dossiers partages
-- (SharedFolderAccess) + suivi de la machine d'origine d'un dossier
-- partage replique depuis un autre poste (colonne origin_machine_id).
--
-- SharedFolderAccess : accorde a un utilisateur (autre que le
-- proprietaire, qui a toujours acces complet implicitement) un droit
-- 'read' ou 'write' sur un dossier partage. En l'absence de ligne pour
-- (folder_id, user_id), l'utilisateur n'a AUCUN acces (sauf s'il est
-- proprietaire ou administrateur) -- cf. core::SharedFolderManager,
-- surcharges verifiant les permissions (issues plan permissions B1/B2).
-- granted_by trace qui a accorde le droit (toujours le proprietaire en
-- v1), utile pour un futur audit ; nullable pour ne pas bloquer une
-- ligne dont l'auteur du don d'acces aurait ete supprime depuis.
--
-- origin_machine_id : les SharedFolders decrivent un chemin LOCAL a
-- chaque poste (local_path) -- un dossier partage cree sur un autre
-- poste et replique ici via SyncLog/diffusion temps reel (issues A1/A2)
-- n'a donc pas de contenu reel sur ce disque, seulement des metadonnees.
-- origin_machine_id retient l'UUID DiscoveryService::localId() de la
-- machine qui possede REELLEMENT les fichiers, pour permettre au module
-- de transfert (issue A3) de savoir a qui adresser une demande de
-- fichier plutot que d'essayer de lire un local_path qui n'a alors aucun
-- sens sur ce poste. Vide (defaut) pour un dossier cree localement --
-- "vide" signifie ici "cette machine EST l'origine".

CREATE TABLE IF NOT EXISTS SharedFolderAccess (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id   INTEGER NOT NULL REFERENCES SharedFolders(id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES Users(id) ON DELETE CASCADE,
    permission  TEXT NOT NULL DEFAULT 'read',
    granted_by  INTEGER,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(folder_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_shared_folder_access_folder ON SharedFolderAccess(folder_id);
CREATE INDEX IF NOT EXISTS idx_shared_folder_access_user ON SharedFolderAccess(user_id);

ALTER TABLE SharedFolders ADD COLUMN origin_machine_id TEXT;
