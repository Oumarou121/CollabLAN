# CollabLAN

## Overview
CollabLAN is a C++23 / Qt 6 (Qt Quick/QML) desktop application for LAN-only
collaboration (presence discovery, messaging, file sharing, notifications,
voice calls). It uses SQLite for storage, UDP/TCP/WebSocket + WebRTC for
networking, OpenSSL for crypto, and CMake as the build system. It is a native
desktop app, not a web app — there is no browser preview in Replit; everything
is built and verified from the shell.

See `README.md` / `docs/ARCHITECTURE.md` for the original project docs (French).

## Running on Replit
System dependencies installed via Nix: `cmake`, `qt6.full`, `openssl`,
`pkg-config`, `gcc13`, `ninja`.

Build (out-of-tree, in `build/`):
```bash
mkdir -p build && cd build
cmake .. -GNinja -DCMAKE_BUILD_TYPE=Release
ninja
```

Run the app binary (headless container — needs a display/X server to actually
show the Qt Quick UI, so this is for local/desktop use, not Replit preview):
```bash
./build/app/CollabLAN
```

Run the test suite:
```bash
cd build && ctest --output-on-failure
```

## Status
- Project builds cleanly (217/217 targets) after fixing a case-sensitivity bug:
  several `#include "Database/Repositories/..."` paths didn't match the actual
  lowercase `database/Repositories/` directory. This worked on the original
  (likely case-insensitive Windows/macOS) dev machine but failed on Linux;
  fixed by lowercasing the includes.
- 20/26 test binaries pass. 6 fail on pre-existing app bugs unrelated to the
  Replit environment: `test_databasemanager`, `test_messagingmanager`,
  `test_groupmanager`, `test_messagerepository`, `test_grouprepository`,
  `test_synclogrepository` — mostly SQL "Parameter count mismatch" errors in
  repository insert code and a stale expected schema version in the DB
  manager tests (expects 11, migrations now produce 18). These look like bugs
  in the app code / test suite, not Replit setup issues.

## User preferences
None recorded yet.
