-- Migration 002 : Ajout de la table Conversations
-- Cette table est nécessaire pour le système de messagerie

CREATE TABLE IF NOT EXISTS Conversations (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    type              TEXT NOT NULL DEFAULT 'individual', -- 'individual' ou 'group'
    name              TEXT NOT NULL,
    participant1_id   INTEGER REFERENCES Users(id),
    participant2_id   INTEGER REFERENCES Users(id),
    created_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Ajouter la table GroupMembers pour les groupes
CREATE TABLE IF NOT EXISTS GroupMembers (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id  INTEGER NOT NULL REFERENCES Groups(id),
    user_id   INTEGER NOT NULL REFERENCES Users(id),
    UNIQUE(group_id, user_id)
);
