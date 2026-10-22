-- Migration #037 : synchronisation des dossiers partages fiable.
--
-- SharedFiles.synced_hash : derniere version de ce fichier echangee avec le
-- reseau (recue, ou retenue apres un conflit). Un fichier dont le contenu sur
-- disque differe de cette version a ete modifie localement depuis : c'est ce
-- qui distingue une simple mise a jour d'un vrai conflit.
--
-- SyncOperations.base_hash : version dont part une modification (empreinte
-- precedente du fichier chez son auteur). Un destinataire qui a exactement
-- cette version peut avancer sans conflit.
-- SyncOperations.author_uuid : auteur reel de l'operation (rattrapage, noms des
-- copies de conflit).
--
-- FolderAccessRevocations.keep_files : retrait sans effacement des fichiers du
-- membre (arret du partage par le proprietaire, ou membre qui quitte le dossier).
--
-- FolderBroadcastCursors : derniere operation locale diffusee, par dossier.
-- Auparavant en memoire : chaque redemarrage rediffusait 500 operations.

ALTER TABLE SharedFiles ADD COLUMN synced_hash TEXT;
ALTER TABLE SyncOperations ADD COLUMN base_hash TEXT;
ALTER TABLE SyncOperations ADD COLUMN author_uuid TEXT;
ALTER TABLE FolderAccessRevocations ADD COLUMN keep_files INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS FolderBroadcastCursors (
    folder_id    INTEGER PRIMARY KEY REFERENCES SharedFolders(id) ON DELETE CASCADE,
    last_op_id   INTEGER NOT NULL DEFAULT 0
);
