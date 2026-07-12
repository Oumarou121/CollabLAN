-- Migration 013 : ajout de la table CallHistory (historique des appels vocaux).
--
-- Constat : network::VoiceService gere l'appel entierement en memoire
-- (CallState, adresse du correspondant...) et ne persiste jamais rien ;
-- core::AuditManager::logCall() existe mais n'est appele nulle part. Au
-- final, aucun utilisateur ne dispose d'un historique de ses appels,
-- meme au sein d'une seule session. Cette table corrige cela.
--
-- Chaque poste CollabLAN a sa propre base SQLite locale (architecture
-- P2P sur LAN) : CallHistory persiste donc, du point de vue de CE poste
-- uniquement, les appels emis/recus. local_user_id reste volontairement
-- NULLABLE (jamais NOT NULL) : la migration 012 a deja corrige exactement
-- ce probleme sur Transfers, ou une contrainte NOT NULL sur une reference
-- utilisateur faisait echouer silencieusement l'insertion des qu'aucun
-- compte local n'etait resolu (PRAGMA foreign_keys=ON est actif dans
-- toute l'application).
--
-- status vaut 'in_progress' a la creation de l'entree (des la premiere
-- offre/tentative), puis est mis a jour a la fin de l'appel par
-- core::CallHistoryManager : 'completed' | 'missed' | 'rejected' |
-- 'cancelled' | 'failed' (voir models::CallStatus).

CREATE TABLE IF NOT EXISTS CallHistory (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    call_uuid        TEXT NOT NULL DEFAULT '',
    local_user_id    INTEGER REFERENCES Users(id),
    direction        TEXT NOT NULL,                      -- 'outgoing' | 'incoming'
    peer_address     TEXT NOT NULL,
    peer_name        TEXT,                                -- snapshot du nom au moment de l'appel, NULL si non resolu
    status           TEXT NOT NULL DEFAULT 'in_progress',
    started_at       TEXT NOT NULL DEFAULT (datetime('now')),
    connected_at     TEXT,                                 -- NULL si la session audio n'a jamais ete etablie
    ended_at         TEXT,                                 -- NULL tant que l'appel est en cours
    duration_seconds INTEGER                               -- NULL si non applicable (jamais connecte / en cours)
);

CREATE INDEX IF NOT EXISTS idx_call_history_started_at ON CallHistory(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_history_local_user_id ON CallHistory(local_user_id);
CREATE INDEX IF NOT EXISTS idx_call_history_status ON CallHistory(status);
