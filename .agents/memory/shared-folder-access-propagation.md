---
name: Shared folder access grants and network propagation
description: How SharedFolder access control (who can see a shared folder) is granted and propagated across accounts/machines, and the offline catch-up pattern used.
---

Creating a shared folder now takes an explicit list of authorized user ids + a
read/write flag (`SharedFolderManager::createFolder`); access rows are stored
in `SharedFolderAccess` (owner has implicit access, never a row). Folder
visibility (`SharedFolderContext::refresh()`) is filtered by
`SharedFolderManager::getAccessibleFolders(userId)` — never list all folders
to all local users again, that was the original bug (over-shared locally,
never shared across machines).

Cross-machine propagation reuses `FolderSyncService`'s existing protocol
rather than inventing a new one: one message type, `folder_access_granted`,
piggybacks folder creation (metadata-only, empty `localPath`,
`registerRemoteFolder()`) onto the access grant, since a folder with no
external grantees needs no network announcement at all.

**Why:** granting access is the only externally-visible event; a folder with
zero grantees is meaningless to announce. Piggybacking keeps protocol surface
minimal, matching the app's existing per-feature dedicated-message-type style
(`folder_op`, `folder_hello`, etc.) instead of a generic replication path.

**How to apply:**
- The SERVER relays `folder_access_granted` it receives from a CLIENT to all
  other clients (clients can't reach each other directly) — same hub pattern
  as the rest of `FolderSyncService`.
- Offline catch-up piggybacks on the existing `folder_hello`/
  `folder_catchup_batch` exchange: the hello now also carries
  `last_access_id` (cursor into `SharedFolderAccess.id`, mirrors
  `SyncOperationRepository`'s `last_op_id` pattern exactly), and the catchup
  batch gained an `access_grants` array alongside `operations`. Receiving
  side replays each entry through the same `handleFolderAccessGranted()` used
  for live announces (idempotent via `registerRemoteFolder`/`grantAccess`
  upsert).
- Not implemented: enforcement of read vs write permission at the actual
  file-sync layer (grants are metadata/visibility only), and no UI to
  view/revoke existing grants after creation.
