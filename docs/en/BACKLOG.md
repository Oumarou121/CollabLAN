# Backlog — CollabLAN

## Purpose of this document

This document lists the project tasks organized by sprint, with the breakdown among the three developers (see [TEAM.md](TEAM.md)). Each task can be converted into a GitHub Issue and tracked via a board (GitHub Projects).

Legend: **D1** = UI (Qt Quick/QML) · **D2** = Network + Database · **D3** = Core (business logic)

---

## Sprint 0 — Foundations

**Goal**: the skeleton builds, the DB initializes, basic navigation between 2 screens.

- [ ] `DatabaseManager`: SQLite opening + running `001_initial_schema.sql` (D2)
- [ ] DB connection tested (clean open/close) (D2)
- [ ] Network modules CMake builds successfully (D2)
- [ ] Choice of WebSocket library (e.g. Qt WebSockets) (D2)
- [ ] Choice of WebRTC library (e.g. libdatachannel) (D2)
- [ ] Basic Login → Home navigation (D1)
- [ ] Global application of `Themes/Light.qml` (D1)
- [ ] Verify `cmake --build .` on Linux + Windows (All)

---

## Sprint 1 — Network Discovery + Local Authentication

**Goal**: Alice logs in, sees Bilal/Chaima appear in the list in real time.

- [ ] `DiscoveryService`: UDP broadcast announcement + listening (D2)
- [ ] Timeout / disconnection handling in `DiscoveryService` (D2)
- [ ] `SecurityService`: per-machine certificate/key generation (OpenSSL) (D2)
- [ ] `SecurityService`: basic TLS handshake between two machines (D2)
- [ ] `UserManager`: creation, authentication, user status (D3)
- [ ] `UserRepository`: user CRUD in the database (D2)
- [ ] `Settings` (model + repository): machine name, language, theme, download folder (D2)
- [ ] `LoginView.qml` wired to `UserManager` (D1)
- [ ] `UsersView.qml`: list of discovered machines in real time (D1)
- [ ] `NetworkTests` for `DiscoveryService` (D2)
- [ ] `UnitTests` for `UserManager` (D3)

---

## Sprint 2 — Messaging (individual + group)

**Goal**: working individual and group messaging, persistent history, notifications.

- [ ] `MessagingService` (WebSocket): sending/receiving messages (D2)
- [ ] `MessagingService` integration over an encrypted channel via `SecurityService` (D2)
- [ ] `MessagingManager`: business logic for individual conversations (D3)
- [ ] `GroupManager`: group business logic (creation, adding/removing members) (D3)
- [ ] `MessageRepository`: message history persistence (D2)
- [ ] `GroupRepository`: group persistence (D2)
- [ ] `NotificationManager` + `NotificationService`: "new message" trigger (D3)
- [ ] `ChatView.qml`: individual conversation (D1)
- [ ] `ChatView.qml`: group conversation + group creation (D1)
- [ ] Integration test: sending a message from PC-A → PC-B (All)

---

## Sprint 3 — File Sharing + Full Notifications

**Goal**: reliable file sharing with resume support, complete system notifications.

- [ ] `TransferService` (TCP): chunked file transfer (D2)
- [ ] `TransferService`: resume after network interruption (D2)
- [ ] `TransferRepository`: transfer history + status (D2)
- [ ] `AudioService`: notification sounds (D3)
- [ ] `FileTransferView.qml`: file selection + progress bar (D1)
- [ ] `NotificationService` integration in the UI (toasts/sound) for all events (D1)
- [ ] Test: large file transfer with a simulated network outage (All)

---

## Sprint 4 — Voice Calls + Audit Log

**Goal**: working voice calls, fully reviewable audit trail.

- [ ] `VoiceService` (WebRTC): call signaling (D2)
- [ ] `VoiceService`: P2P audio session establishment (D2)
- [ ] `AuditManager`: event logging (connections, messages, transfers, calls, refusals) (D3)
- [ ] `AuditLogRepository`: audit log persistence (D2)
- [ ] `CallView.qml`: incoming/outgoing call, real-time status (D1)
- [ ] `AdminView.qml`: viewing and exporting the audit log (D1)
- [ ] End-to-end integration test on the 3-machine scenario (see [HOW_IT_WORKS.md](HOW_IT_WORKS.md)) (All)

---

## Sprint 5 — Administration + Stabilization (beta → v1.0)

**Goal**: stable, releasable v1.0.

- [ ] `PermissionManager`: role management (admin/user) (D3)
- [ ] `PermissionManager`: authorized/revoked machine management (D3)
- [ ] Complete `AdminView.qml`: users, authorized machines, global settings (D1)
- [ ] `SecurityService` hardening: rejection + audit of unauthorized machines (D2)
- [ ] Bug fixes reported from previous sprints (All)
- [ ] Load testing (3+ simultaneous machines) (All)
- [ ] Full cross code review (All)
- [ ] Documentation update (`feature/docs`) (All)
- [ ] Merge `develop` → `main`, tag `v1.0` (Project lead)

---

## Cross-Cutting Watch Points

- Define the network ↔ core interfaces as early as Sprint 1 (e.g. method signatures between `MessagingService` and `MessagingManager`) to avoid blockers in Sprints 2–3.
- Plan for UI-side (D1) mocks/stubs so as not to be blocked waiting on D2/D3's work.
- Mandatory code review before any merge into `develop` (see [../CONTRIBUTING.md](../CONTRIBUTING.md)).
- Recheck compliance with the [Requirements Specification](Cahier_des_charges.pdf) at the end of each sprint.

---

## Related Documents

- [ROADMAP.md](ROADMAP.md) — planned versions and developments
- [TEAM.md](TEAM.md) — breakdown of responsibilities
- [ARCHITECTURE.md](ARCHITECTURE.md) — logical architecture and code structure
- [HOW_IT_WORKS.md](HOW_IT_WORKS.md) — detailed operating scenario
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — Git workflow and conventions
