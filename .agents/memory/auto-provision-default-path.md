---
name: Auto-provision default local path for remote shared folders
description: registerRemoteFolder() leaves localPath empty by design (migration #020); provisionDefaultLocalPath() now fills it automatically instead of leaving the folder empty until the user manually picks a path via setFolderLocalPath().
---

**Before:** a remote SharedFolder (received via `folder_access_granted` /
catch-up) sat with `local_path = ''` until the user opened the UI and
explicitly chose a folder (`SharedFolderContext::setFolderLocalPath()` →
`SharedFolderManager::updateFolderLocalPath()` → `requestFolderResync()`).
Until then, `handleFolderCatchupBatch()`'s placeholder branch just recorded
metadata (0-byte rows) — no content ever downloaded, and the folder
appeared empty in the UI for an indeterminate time.

**Now:** `SharedFolderManager::provisionDefaultLocalPath(folderId)`:
- Only touches remote folders (`!isLocalOrigin()`) with an empty
  `localPath`; no-op (returns the existing path) otherwise — a
  locally-created folder always already has one, chosen at `createFolder()`.
- Target: `QStandardPaths::DocumentsLocation + "/CollabLAN Shared
  Folders/<sanitized name>"`. Sanitizes Windows-forbidden characters
  (`\/:*?"<>|` → `_`).
- Disambiguates collisions as `"<name> (2)"`, `"(3)"`, ... checking both
  disk existence AND every other known `SharedFolder.localPath()` (a
  disk-only check would miss a name reserved by another folder processed in
  the same batch but not yet `mkpath()`'d — order matters when
  auto-provisioning several folders back-to-back, e.g. a big catch-up).

Wired into `Application.cpp`'s `accessGrantedLocal` handler (already the
place that fires the "new shared folder" notification for the *local*
user specifically) — auto-provision there, then call
`FolderSyncService::requestFolderResync()` same as the manual
`setFolderLocalPath()` path, then fire a second notification
(`NotificationManager::onFolderAutoProvisioned`) telling the user WHERE the
content is landing, since the explicit "choose a folder" consent gesture is
gone.

**Deliberately NOT done:** no global on/off setting for this behavior yet
(discussed, deferred) — every remote folder is auto-provisioned
unconditionally for now.
