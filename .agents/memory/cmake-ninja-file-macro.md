---
name: cmake-ninja-file-macro
description: Why __FILE__-based runtime path lookups silently fail when a CMake project is built with Ninja on Replit.
---

When a CMake project on Replit is configured with `-G Ninja`, the compiler is invoked with a
relative path to each source file, so the C/C++ `__FILE__` macro expands to something like
`DatabaseManager.cpp` instead of an absolute path. Any runtime code that uses `__FILE__` to derive
a directory (e.g. `QDir(__FILE__).filePath("../some-data-dir")`) will resolve relative to the
process's current working directory instead of the source tree, and will silently fail to find
files unless the working directory happens to line up.

**Why:** discovered while building a Qt6/CMake project (CollabLAN) — a migrations-folder fallback
lookup used `__FILE__` and silently returned zero pending migrations under `ctest`, causing
widespread, confusing test failures with no error message.

**How to apply:** when diagnosing "file not found" / "feature silently no-ops" bugs in a CMake+Ninja
build here, check whether the code uses `__FILE__` for anything beyond logging. Prefer resources
embedded via the build system (e.g. Qt `.qrc` files) or paths derived from a known install root
instead of `__FILE__`-relative lookups.
