---
name: Null QString bound to NOT NULL SQLite column
description: QSqlQuery::bindValue with a default-constructed (null) QString violates NOT NULL constraints even when the column has a DEFAULT, because binding an explicit value overrides the column default.
---

Binding a default-constructed `QString()` (which is null, not just empty) via
`QSqlQuery::bindValue` sends SQL `NULL` to the driver. If the target column is
`NOT NULL` — even with a `DEFAULT ''` clause — the insert/update fails,
because an explicit bound value always overrides the column default.

**Why:** Model POCOs often leave string fields default-constructed until
explicitly set (e.g. a `hash` field before the first hash computation). Code
that inserts these models directly hits this if it doesn't normalize null
QStrings before binding.

**How to apply:** In repository `create()`/`update()` methods, coalesce with
`field.isNull() ? QStringLiteral("") : field` before `bindValue()` for any
string column that is `NOT NULL` in the schema, rather than relying on the
column's SQL default.
