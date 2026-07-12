---
name: "Parameter count mismatch" really means "unknown column in prepare()"
description: Qt/SQLite named-parameter binding reports a misleading "Parameter count mismatch" when query.prepare() silently failed because the SQL references a column that doesn't exist in the table.
---

When `QSqlQuery::prepare()` is given SQL referencing a column that isn't in the actual table schema, SQLite's prepare step fails, but the code path typically doesn't check `prepare()`'s return value — it just calls `bindValue()` (no-ops against a failed prepare) and then `exec()`, which reports `"Parameter count mismatch"`. That message is misleading: it looks like a binding-count bug, but the real cause is a schema mismatch between the SQL and the table it targets.

**Why:** hit this across several unit test suites (`test_messagerepository`, `test_grouprepository`, `test_groupmanager`, `test_messagingmanager`) that hand-roll `CREATE TABLE Messages/Groups/Conversations` fixtures instead of running real migrations. The fixtures were written before migrations added `uuid` (Messages/Groups/Conversations) and `conversation_id` (Groups) columns, so repository code that legitimately inserts those columns failed prepare() against the stale fixture schema.

**How to apply:** if you see `"Parameter count mismatch"` from a Qt/SQLite query with named placeholders whose bind count visibly matches the placeholder count, suspect a missing column in the target table before suspecting the binding code. For hand-rolled test schemas, prefer letting `DatabaseManager` run the real migrations over ad hoc `CREATE TABLE`, or keep the ad hoc fixture schema in lockstep with the latest migration for that table.
