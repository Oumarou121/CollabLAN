---
name: FolderSyncService transfer correlation
description: How incoming file transfers are matched back to the folder-sync request that triggered them, and a QtTest limitation this creates.
---

`FolderSyncService` (`core/Sync/FolderSyncService`) tracks pending remote-file requests in a hash keyed by `"<ownerMachineId>::<fileName>"` (basename only, not full relative path) because `TransferService::transferStarted` only reports the file's basename, not its folder-relative path. When a transfer starts, this pending entry is promoted to an "active by transferKey" hash so `onTransferCompleted` can look it up in O(1) and call `integrateReceivedFile()`.

**Why:** the key had to be something derivable from both sides — the requester only knows the relative path when it asks, but the responder's `TransferService` only surfaces the filename when the transfer begins.

**How to apply:** if two pending requests for files with the same basename in different subfolders from the same peer are ever needed concurrently, this keying scheme will collide — would need to extend the correlation key or thread the relative path through `TransferService` itself.

Separately: some of `FolderSyncService`'s private helpers (e.g. `makeConflictPath`, a `static` method) are not registered with Qt's meta-object system, so they cannot be invoked via `QMetaObject::invokeMethod` from tests. Test them indirectly through the public/slot entry points that call them (e.g. the conflict-integration test), not directly.
