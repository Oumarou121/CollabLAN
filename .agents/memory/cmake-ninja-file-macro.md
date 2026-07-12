---
name: cmake-ninja-file-macro
description: Why __FILE__-based runtime path lookups silently fail when a CMake project is built with Ninja on Replit.
---

When a CMake project on Replit is configured with `-G Ninja`, the compiler is invoked with a
relative path to each source file, so the C/C++ `__FILE__` macro expands to a relative path
instead of an absolute one. Runtime code that derives a directory from `__FILE__` (e.g.
`QDir(__FILE__).filePath("../some-data-dir")`) then resolves relative to the process's current
working directory, not the source tree, and silently fails to find files unless the working
directory happens to line up.

**Why:** discovered while building a Qt6/CMake project — a data-folder fallback lookup used
`__FILE__` and silently found nothing under `ctest`, causing confusing failures with no error
message.

**How to apply:** when diagnosing "file not found" / "feature silently no-ops" bugs in a
CMake+Ninja build here, check whether the code uses `__FILE__` for anything beyond logging.
Prefer resources embedded via the build system (e.g. Qt `.qrc`) or paths derived from a known
install root instead of `__FILE__`-relative lookups.
