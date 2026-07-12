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
