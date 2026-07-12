# CollabLAN

## Overview
CollabLAN is a C++23 / Qt 6 (Qt Quick/QML) desktop application for LAN-only
collaboration (presence discovery, messaging, file sharing, notifications,
voice calls). It uses SQLite for storage, UDP/TCP/WebSocket + WebRTC for
networking, OpenSSL for crypto, and CMake as the build system. It is a native
desktop app, not a web app — there is no browser preview in Replit; everything
is built and verified from the shell.

See `README.md` / `docs/ARCHITECTURE.md` for the original project docs (French).

## Running on Replit
System dependencies installed via Nix: `cmake`, `qt6.full`, `openssl`,
`pkg-config`, `gcc13`, `ninja`.

Build (out-of-tree, in `build/`):
```bash
mkdir -p build && cd build
cmake .. -GNinja -DCMAKE_BUILD_TYPE=Release
ninja
```

Run the app binary (headless container — needs a display/X server to actually
show the Qt Quick UI, so this is for local/desktop use, not Replit preview):
```bash
./build/app/CollabLAN
```

Run the test suite:
```bash
cd build && ctest --output-on-failure
```

## Status
- Project builds cleanly (all targets, app + 26 test binaries) after fixing a
  case-sensitivity bug: several `#include "Database/Repositories/..."` paths
  didn't match the actual lowercase `database/Repositories/` directory. This
  worked on the original (likely case-insensitive Windows/macOS) dev machine
  but failed on Linux; fixed by lowercasing the includes.
- Fixed a DB-init bug that blocked the app from ever starting on a fresh
  install: migration `019_add_shared_folders_uuid_column.sql` unconditionally
  ran `ALTER TABLE SharedFolders ADD COLUMN uuid`, but migration 018 already
  creates that column, so 019 always failed with "duplicate column name" and
  `DatabaseManager::open()` returned false on every run. SQLite has no
  `ADD COLUMN IF NOT EXISTS`, so `DatabaseManager::applyMigrationFile()` now
  treats a "duplicate column name" error on an `ADD COLUMN` statement as a
  no-op instead of aborting the migration. Verified the app binary starts
  cleanly end-to-end (DB opens/migrates, TLS cert loads, messaging/transfer/
  voice services bind their ports) via `QT_QPA_PLATFORM=offscreen`.
- 20/26 test binaries pass. 6 fail on pre-existing app/test bugs unrelated to
  Replit setup: `test_databasemanager` (two tests assert a stale expected
  schema version of 11; migrations now produce 20), `test_messagingmanager`,
  `test_groupmanager`, `test_messagerepository`, `test_grouprepository`,
  `test_synclogrepository` — mostly SQL "Parameter count mismatch" errors in
  repository insert code. Proposed as a follow-up task rather than fixed here
  (out of scope for project setup).

## Release 8 — Intégration des fichiers reçus + gestion des conflits

**Nouveau dans `core/Sync/FolderSyncService`** :

Quand `TransferService` reçoit un fichier déclenché par un `folder_file_request` :

1. `onTransferStarted` corrèle le `transferKey` avec la `PendingFileTransfer` enregistrée lors du `requestRemoteFile()`.
2. `onTransferCompleted` appelle `integrateReceivedFile()` qui :
   - Calcule le SHA-256 du fichier reçu.
   - **Détection de conflit** : si un fichier local avec un hash différent existe déjà → renomme l'entrant en `nom (machineId_courte).ext` et émet `conflictDetected`.
   - Copie le fichier vers son chemin cible dans le dossier partagé.
   - `SharedFileRepository::upsert` → enregistre le fichier dans `SharedFiles`.
   - `SyncOperationRepository::insert` → journal de la Create/Update.
   - Émet `fileIntegrated(folderUuid, relativePath, wasConflict)`.

Connexions ajoutées dans `app/Application.cpp` :
- `TransferService::transferStarted` → `FolderSyncService::onTransferStarted`
- `TransferService::transferCompleted` → `FolderSyncService::onTransferCompleted`

Tests : 14 tests (10 protocole + 4 intégration/conflit), tous verts.

## Releases 4–7 — Synchronisation réseau LAN en temps réel

**Nouveau : `core/Sync/FolderSyncService`** (branché dans `app/Application.cpp`)

Protocole dédié sur le canal WebSocket existant (port 12345) :
- `folder_op` — diffusion d'un changement de fichier (Create/Update/Delete/Rename)
- `folder_hello` — envoyé à chaque connexion au serveur avec le dernier `op_id` connu
- `folder_catchup_batch` — réponse du serveur avec les opérations manquées
- `folder_file_request` — demande de transfert d'un fichier précis (servi via `TransferService`)

Flux Release 5/6 (temps réel) :
1. `SyncEngine::folderReindexed` → `FolderSyncService::onLocalFolderReindexed`
2. `FolderSyncService` lit les nouvelles `SyncOperation` via `SyncOperationRepository::getByFolderId`
3. Broadcast `folder_op` à tous les pairs (SERVER via `broadcastMessage`, CLIENT via `sendMessageToServer`)
4. Pair récepteur → envoie `folder_file_request` si le fichier est absent/périmé
5. Propriétaire → `TransferService::sendFile` vers l'IP du demandeur

Flux Release 7 (rattrapage hors-ligne) :
1. `MessagingService::connected` → `folder_hello` avec `latestId()` local
2. SERVER reçoit `folder_hello` → `getSinceId` sur tous ses dossiers → `folder_catchup_batch`
3. CLIENT reçoit `folder_catchup_batch` → demande les fichiers manquants

Tests : `test_foldersyncservice` (10 tests, tous verts).

## Suite après Release 8 — Delete/Rename distants + filtre d'exclusion (Release 9 partielle)

Deux lacunes identifiées en reprenant le travail interrompu ont été comblées :

**core/Sync/FolderSyncService** — jusqu'ici `handleFolderOp` et
`handleFolderCatchupBatch` n'appliquaient que Create/Update côté récepteur ;
un Delete ou Rename distant était reçu (signal `remoteOpReceived` émis) mais
jamais appliqué au système de fichiers ni à la base locale. Ajout de
`applyRemoteDelete()` (supprime le fichier sur disque, `markDeleted()` en
base, journalise un `FileSyncOperation` Delete) et `applyRemoteRename()`
(renomme sur disque, `renameFile()` en base, journalise un Rename) — les deux
méthodes de `SharedFileRepository` existaient déjà mais n'étaient jamais
appelées.

**core/SharedFolderManager::shareFolder()** — aucun filtre d'exclusion
n'existait : `.git`, `.tmp`, fichiers de verrouillage (`~$*.docx`,
`.~lock.*`), `Thumbs.db`, `.DS_Store`, etc. étaient indexés et donc
synchronisés comme n'importe quel fichier utilisateur. Ajout d'un filtre
`isExcludedRelativePath()` (dossiers `.git`/`.svn`/`.hg`/`node_modules`/
`__pycache__`, fichiers système connus, verrous d'éditeurs, extensions
`.tmp`/`.temp`/`.obj`/`.o`/`.swp`/`.bak`/`.crdownload`/`.part`).

Tests : 2 nouveaux cas dans `test_foldersyncservice` (Delete et Rename
distants appliqués correctement) + 1 nouveau cas dans
`test_sharedfoldermanager` (fichiers techniques exclus de l'indexation).

## Correction des 6 derniers échecs de tests — suite complète à 31/31

Les 6 échecs préexistants (`test_databasemanager`, `test_messagingmanager`,
`test_groupmanager`, `test_messagerepository`, `test_grouprepository`,
`test_synclogrepository`) n'étaient **pas** des bugs applicatifs : le code
de production (`MessageRepository`, `GroupRepository`, `GroupManager`)
fonctionne correctement contre une base migrée normalement. Deux causes
racines distinctes, toutes deux côté tests :

1. **Schémas de table ad hoc obsolètes.** Plusieurs tests recréent
   `Messages`/`Groups`/`Conversations` à la main (`CREATE TABLE` en dur)
   plutôt que de laisser `DatabaseManager` appliquer les vraies migrations.
   Ces schémas maison avaient été écrits avant l'ajout des colonnes
   `uuid` (migration 011) et `conversation_id` (migration 004) : `query.
   prepare()` échouait alors silencieusement (colonne inconnue), et
   `exec()` renvoyait "Parameter count mismatch" — un message trompeur qui
   masque la vraie cause (colonne manquante, pas un problème de binding).
   Corrigé en alignant chaque `CREATE TABLE` de test sur le schéma réel.
2. **Attentes obsolètes dans `test_synclogrepository`.** Les payloads JSON
   de test utilisaient encore des identifiants locaux (`senderId`,
   `conversationId`, `ownerId`, `memberIds`) alors que
   `SyncLogRepository::applyMessageEntry/applyGroupEntry` résolvent
   désormais tout par uuid stable inter-poste (`senderUuid`,
   `conversationUuid`, `ownerUuid`, `memberUuids`) depuis la migration 011.
   Corrigé : payloads réécrits en uuid, utilisateur de test seedé avec un
   uuid, assertions relogées sur les uuid stables plutôt que sur des id
   locaux supposés (l'AUTOINCREMENT local ne coïncide jamais avec l'id de
   la machine d'origine, par design).
3. **Version de schéma figée dans `test_databasemanager`.** `schemaVersion()`
   compte les fichiers `*.sql` appliqués ; le test attendait encore 11
   alors que 21 migrations existent désormais. Mis à jour à 21.

Suite complète : **31/31 tests passent**, aucune régression.

## Release 2 / 3 — Détection des changements + Journal de synchronisation
All C++ components were already implemented. The following gaps were closed:

**core/SharedFolderContext.cpp / .h**
- Connected `SharedFolderManager::folderShared` → `SharedFolderContext::refresh()`
  so the folder tile file count updates automatically after FolderWatcher triggers
  a reindex (no manual navigation required).
- Added `folderReindexed(folderId, changeCount)` signal forwarded from
  `SyncEngine::folderReindexed`; QML listens to this to auto-refresh the file
  list and sync history panel without user interaction.

**ui/SharedFolder/SharedFolderView.qml**
- Added `refreshHistory()` and automatic calls after watcher-triggered reindex.
- Added "Historique" toggle button that swaps the file list for a sync history
  panel showing Create / Update / Delete / Rename operations (type badge,
  relative path, old path for renames, version, timestamp).

**tests/** — 4 new test suites (30+ test cases):
- `test_sharedfoldermanager.cpp`: Create/Update/Delete/Rename detection, error
  handling.
- `test_syncoperationrepository.cpp`: insert, getByFolderId (with relativePath
  join), getSinceId (pagination for Release 7 catch-up), latestId.
- `test_folderwatcher.cpp`: idempotent watch/unwatch, safe calls on unknown
  folders, debounce behaviour.
- `test_syncengine.cpp`: full reindexFolder pipeline, folderReindexed signal,
  historyForFolder ordering.

## User preferences
None recorded yet.
