---
name: Qt AUTOMOC requires headers in target sources
description: A new Q_OBJECT class's header must be part of the CMake target's globbed/listed sources, or AUTOMOC silently skips it.
---

`core/CMakeLists.txt` (and similarly other targets) originally only globbed `*.cpp` files, not headers. Qt's AUTOMOC discovers `Q_OBJECT` classes by scanning the manifest of files CMake tracks for the target — if a new class's `.h` isn't in that manifest, AUTOMOC never generates its moc file, and you get missing-vtable/undefined-reference-to-`vtable for X` linker errors that look unrelated to moc at first glance.

**Why:** hit this when adding a new `Q_OBJECT` class (`FolderSyncService`) under `core/` — the build compiled cleanly but failed to link because AUTOMOC hadn't processed the new header.

**How to apply:** when adding a new QObject-derived class to an existing CMake target, verify the target's source glob/list includes headers (not just `.cpp`), matching how existing `Q_OBJECT` classes in that target are wired (e.g. check how `network/CMakeLists.txt` does it). Adding a manual `#include "Foo.moc"` at the end of the `.cpp` is a workaround but the header-inclusion fix is preferred since it matches the rest of the codebase.
