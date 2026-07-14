-- Migration 024 : ajout de la colonne exclude_patterns sur SharedFolders
-- (debrief point #4, sync selective).
--
-- Motifs glob (separes par des virgules, ex: "*.log, build, drafts/*")
-- exclus de l'indexation/sync pour CE dossier partage, en plus des
-- exclusions codees en dur (isExcludedRelativePath()). Colonne LOCALE a
-- ce poste : non synchronisee entre pairs -- chaque poste peut avoir ses
-- propres motifs pour le "meme" dossier partage logique (le local_path
-- lui-meme est deja local par design, cf. migration 020).
--
-- Defaut '' (chaine vide) plutot que NULL : SharedFolderRepository lit
-- systematiquement cette colonne via QVariant::toString(), qui traite
-- NULL et '' de la meme facon cote Qt, mais '' evite une distinction
-- NULL-vs-vide inutile dans le reste du code (parseExcludePatterns()
-- attend une QString, pas un optionnel).

ALTER TABLE SharedFolders ADD COLUMN exclude_patterns TEXT NOT NULL DEFAULT '';
