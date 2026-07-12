---
name: SQLite migrations need manual idempotency
description: SQLite lacks ADD COLUMN IF NOT EXISTS, so migration runners must guard against re-adding columns that a later/earlier migration already created.
---

SQLite has no `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`. If a migration file
unconditionally runs `ALTER TABLE t ADD COLUMN c`, and any other migration
(earlier or later) already created that column on a fresh install, every
fresh install fails at that migration and the app can never initialize its
database — not just a test failure, a total app-startup blocker.

**Why:** Found this in CollabLAN (Qt6/C++ project): migration 018 already
created `SharedFolders.uuid`, but a later migration 019 (written to backfill
the column for old installs) unconditionally re-added it, so it always failed
with "duplicate column name" on any fresh DB.

**How to apply:** When a migration runner executes a statement and gets a
"duplicate column name" error on an `ADD COLUMN` statement, treat it as a
no-op/skip rather than aborting the whole migration — don't just patch the
one SQL file, since the same pattern can recur in future migrations.
