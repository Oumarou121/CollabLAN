-- Migration initiale : creation des tables principales
-- Voir docs/Cahier_des_charges.pdf et docs/ARCHITECTURE.md

CREATE TABLE IF NOT EXISTS Users (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    name           TEXT NOT NULL UNIQUE,
    ip_address     TEXT NOT NULL DEFAULT '',
    status         TEXT NOT NULL DEFAULT 'offline',
    is_admin       INTEGER NOT NULL DEFAULT 0,
    password_hash  TEXT NOT NULL DEFAULT '',
    password_salt  TEXT NOT NULL DEFAULT '',
    created_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS Groups (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL,
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS Messages (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_id     INTEGER NOT NULL REFERENCES Users(id),
    group_id      INTEGER REFERENCES Groups(id),
    recipient_id  INTEGER REFERENCES Users(id),
    content       TEXT NOT NULL,
    sent_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS Transfers (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_id     INTEGER NOT NULL REFERENCES Users(id),
    recipient_id  INTEGER NOT NULL REFERENCES Users(id),
    file_name     TEXT NOT NULL,
    file_size     INTEGER NOT NULL,
    status        TEXT NOT NULL DEFAULT 'pending',
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS AuditLogs (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type    TEXT NOT NULL,
    description   TEXT,
    user_id       INTEGER REFERENCES Users(id),
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS Settings (
    key           TEXT PRIMARY KEY,
    value         TEXT
);
