-- Migration #038 : index pour les lectures faites par l'interface.
--
-- Messages n'avait aucun index sur conversationId : le dernier message et le
-- nombre de non-lus de chaque conversation (liste des discussions, badges
-- relus toutes les 5 s) parcouraient toute la table. L'index porte aussi sur
-- l'ordre d'affichage (datetime(timestamp), id) : les derniers messages d'une
-- conversation se lisent sans trier toute la conversation.
CREATE INDEX IF NOT EXISTS idx_messages_conversation_time ON Messages(conversationId, datetime(timestamp), id);

-- Accuses, modifications et suppressions retrouvent un message par son uuid.
CREATE INDEX IF NOT EXISTS idx_messages_uuid ON Messages(uuid);

-- Conversations d'un utilisateur (participant1_id = ? OR participant2_id = ?).
CREATE INDEX IF NOT EXISTS idx_conversations_participant1 ON Conversations(participant1_id);
CREATE INDEX IF NOT EXISTS idx_conversations_participant2 ON Conversations(participant2_id);

-- Nombre de non-lus d'une conversation : index couvrant (expediteur, etat
-- supprime, uuid pour les accuses) -- le parcours ne relit plus chaque ligne
-- de la table.
CREATE INDEX IF NOT EXISTS idx_messages_unread_scan ON Messages(conversationId, senderId, deleted_at, uuid);
