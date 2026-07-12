---
name: FolderSyncService receiver-side completeness
description: When extending FolderSyncService's incoming-message handling, check both handleFolderOp (live) and handleFolderCatchupBatch (offline catch-up) — logic added to one is easy to forget in the other.
---

`FolderSyncService` has two entry points that both process the same op-type space (Create/Update/Delete/Rename) but at different times: `handleFolderOp` for live broadcasts and `handleFolderCatchupBatch` for the Release-7 offline-catchup replay. They started out with duplicated per-op-type branching that only covered Create/Update — Delete and Rename were received and re-emitted as signals but never applied to the local filesystem/DB, even though `SharedFileRepository::markDeleted`/`renameFile` already existed and were fully implemented, just never called.

**Why:** it's easy to add handling to the live path and forget the catch-up path (or vice versa) since they're separate methods with near-identical branching logic.

**How to apply:** when adding a new op-type behavior to one of these handlers, grep for the other handler's op-type branches and mirror the change. Consider consolidating the branch logic into one shared private method if a third call site appears.
