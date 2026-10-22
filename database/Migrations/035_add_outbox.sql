-- Migration #035 : file d'attente des changements a transmettre au serveur.
--
-- Modification/suppression d'un message, creation et changements de groupe :
-- appliques tout de suite sur ce poste, puis transmis au serveur, a la
-- reconnexion si besoin. Une ligne reste tant que le serveur n'en a pas
-- accuse reception (change_id). requires_official : a ne transmettre qu'au
-- serveur officiel (un serveur de secours ne connait pas forcement le groupe).
-- user_uuid : le serveur n'accepte un changement que de son auteur, identifie
-- sur la connexion ; ceux d'un autre utilisateur du poste attendent son login.

CREATE TABLE IF NOT EXISTS Outbox (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    change_id          TEXT NOT NULL UNIQUE,
    user_uuid          TEXT NOT NULL DEFAULT '',
    payload_json       TEXT NOT NULL,
    requires_official  INTEGER NOT NULL DEFAULT 0,
    created_at         TEXT NOT NULL DEFAULT (datetime('now'))
);
