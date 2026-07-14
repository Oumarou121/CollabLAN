---
name: Whole-subfolder moves are consolidated into one DirectoryRename op
description: shareFolder() still detects renames per file (needed for correct SharedFiles bookkeeping); the network broadcast and receiver-side apply are what get batched into a single operation for a whole-subtree move.
---

**Problem (debrief #6):** moving/renaming a subfolder with N files produced
N individual `Rename` `SharedFileChange` entries. Each got persisted as its
own `SyncOperations` row (needed for offline catch-up correctness — kept
as-is) AND broadcast as its own `folder_op` message, and the receiver did
N separate `QFile::rename()` calls. For a folder with hundreds of files,
one drag-and-drop became hundreds of network messages and disk operations.

**Fix, scoped to the two expensive layers (network + disk), not the DB
journal:**

- `FolderSyncService::onLocalFolderReindexed()` groups pending `Rename` ops
  by `(oldParentDir, newParentDir)`. A group of 2+ files broadcasts ONE
  `folder_op` with `op_type: "DirectoryRename"` (`old_relative_path`/
  `relative_path` are DIRECTORY paths here, not file paths) instead of one
  message per file. A lone rename (group size 1) still broadcasts normally.
- Receiver's `FolderSyncService::applyRemoteDirectoryRename()` does ONE
  `QDir::rename()` for the whole subtree (fast path), then loops in-memory
  over affected `SharedFiles` rows to update `relative_path` + insert one
  `SyncOperations` row each (cheap DB bookkeeping, no extra disk I/O — this
  preserves per-file replay/catch-up correctness).
- Falls back to per-file `applyRemoteRename()` if the source subfolder
  doesn't exist locally yet, or the target already exists (avoids silently
  clobbering local content via a single bulk rename).

**Deliberately NOT changed:** `SyncOperations` schema/rows stay per-file
(no `DirectoryRename` value there), so `handleFolderCatchupBatch()` (which
reads from that table) is untouched and still replays per-file — catch-up
is the less latency-sensitive path, so this was not worth a schema
migration. History UI (`SharedFolderView.qml`) therefore still lists one
line per file for a directory move; only real-time network chatter and
receiver disk I/O were consolidated.
