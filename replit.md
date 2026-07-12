# CollabLAN

## Overview
CollabLAN is a LAN-only (no internet required) collaboration desktop app: user discovery, 1:1/group messaging, file sharing, real-time notifications, voice calls, audit log, and admin/user management.

- **Language/stack:** C++23, Qt 6 (Qt Quick/QML), SQLite (via Qt Sql), UDP/TCP/WebSocket, WebRTC, OpenSSL, CMake
- **Type:** Native Qt desktop GUI application — not a web app. It will not render in Replit's browser preview.
- Imported from GitHub; original French-language project docs live in `docs/` (see `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/TEAM.md`).

## Building on Replit
System dependencies installed via Nix: `cmake`, `qt6.qtbase`, `qt6.qtdeclarative`, `qt6.qttools`, `qt6.qtwebsockets`, `openssl`, `pkg-config`, `gcc`, `ninja`.

```bash
mkdir -p build && cd build
cmake -G Ninja ..
ninja
```

This builds the `CollabLAN` app binary (`build/app/CollabLAN`) plus all unit test executables under `build/tests/`. Since there's no display in this environment, run the GUI binary or Qt-based tests with an offscreen platform plugin:

```bash
QT_QPA_PLATFORM=offscreen ctest --test-dir build --output-on-failure
```

No workflow is configured since this is a desktop GUI app with no web server component — nothing to preview in the browser.

## Known issue (pre-existing, not fixed here)
`database::DatabaseManager::pendingMigrationFiles()` falls back to a `__FILE__`-relative path to locate `database/Migrations/*.sql` when it can't find migrations next to the built binary. With Ninja, `__FILE__` expands to a **relative** path (e.g. `DatabaseManager.cpp`), so that fallback silently resolves to nothing unless the process's current working directory happens to line up. This causes `schemaVersion() == 0` and several `UserRepository`/`UserManager` test failures (6/7 `test_usermanager`, 3/10 `test_databasemanager`, 8/13 `test_userrepository`) when tests are run via `ctest` from `build/`. Core logic (discovery, security/TLS, peers model) tests pass. Fixing this would mean hardening the migrations path resolution (e.g. embed migrations as Qt resources via the existing `database.qrc`, which currently only registers migration 001 and is missing 002) — flagged as a follow-up rather than changed here, since the ask was to get the project compiling.

## Running the app itself
`build/app/CollabLAN` is a Qt Quick GUI binary. It needs a display (or `QT_QPA_PLATFORM=offscreen`/`xvfb` for headless smoke-testing) and is not exposed through Replit's web preview.
