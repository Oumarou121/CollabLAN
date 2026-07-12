-- Migration 003 : Mise à jour de la table Messages pour correspondre au code
-- Le code utilise conversationId au lieu de sender_id/group_id/recipient_id

-- Renommer la table Messages existante
ALTER TABLE Messages RENAME TO Messages_old;

-- Créer la nouvelle table Messages avec le bon schéma
CREATE TABLE IF NOT EXISTS Messages (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    conversationId INTEGER NOT NULL REFERENCES Conversations(id),
    senderId      INTEGER NOT NULL REFERENCES Users(id),
    content       TEXT NOT NULL,
    timestamp     TEXT NOT NULL DEFAULT (datetime('now')),
    is_read       INTEGER NOT NULL DEFAULT 0
);

-- Migrer les données de l'ancienne table si nécessaire
-- Note: Cette migration est simplifiée car l'ancienne structure était incompatible
-- Les données existantes ne peuvent pas être migrées automatiquement

-- Supprimer l'ancienne table
DROP TABLE IF EXISTS Messages_old;
