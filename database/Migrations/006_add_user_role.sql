-- Migration 006 : Ajout de la colonne role dans la table Users (issue #67)

ALTER TABLE Users ADD COLUMN role TEXT NOT NULL DEFAULT 'user';

-- Mettre à jour l'utilisateur admin par défaut pour avoir le rôle admin
UPDATE Users SET role = 'admin' WHERE name = 'admin';
