# Technical Architecture — LocaLink

## Layered Architecture

The software follows a layered architecture:

```
                Qt Quick/QML Interface
                         │
                         ▼
                Business Logic (C++23)
                         │
         ┌───────────────┴───────────────┐
         ▼                               ▼
   Network Communication              Database
   UDP / TCP / WebSocket               SQLite
       WebRTC / OpenSSL
```

1. **Presentation** — User interface in Qt Quick/QML
2. **Business logic** — C++23, no graphical dependency
3. **Network communication** — UDP, TCP, WebSocket, WebRTC, OpenSSL
4. **Data** — SQLite

## Technologies

| Technology | Usage |
|---|---|
| C++23 | Main language |
| Qt 6 | Main framework |
| Qt Quick / QML | Graphical interface |
| SQLite | Local database |
| UDP | Automatic machine discovery |
| TCP | File transfer |
| WebSocket | Real-time messaging |
| WebRTC | Voice calls |
| OpenSSL | Encryption and authentication |
| CMake | Build system |

The software runs in **Peer-to-Peer** mode or **Local Server** mode, entirely on the local network. All communications are authenticated, encrypted, and restricted to authorized machines (see the [Requirements Specification](Cahier_des_charges.pdf) for the full constraints).

## Project Structure

```
LocaLink/
│
├── app/
├── ui/
├── core/
├── network/
├── database/
├── models/
├── services/
├── resources/
├── tests/
├── docs/
├── CMakeLists.txt
└── README.md
```

### app/

Application entry point: Qt initialization, QML loading, general configuration, service startup.

Examples: `main.cpp`, `Application.cpp`, `Application.h`

### ui/

Full graphical interface in Qt Quick/QML (Developer 1's responsibility).

```
ui/
├── Login/
├── Home/
├── Chat/
├── Users/
├── FileTransfer/
├── Call/
├── Settings/
├── Admin/
├── Components/
└── Themes/
```

Each folder contains the QML files for a screen or reusable components.

### core/

Application business logic (Developer 3's responsibility): user management, messaging, notifications, audit log, group management, permissions.

No graphical interface code should be present in this folder.

### network/

Network communications (Developer 2's responsibility).

```
network/
├── Discovery/   → UDP discovery
├── Messaging/   → WebSocket
├── Transfer/    → TCP
├── Voice/       → WebRTC
└── Security/    → OpenSSL encryption
```

### database/

SQLite management (Developer 3's responsibility).

```
database/
├── DatabaseManager
├── Repositories
├── Migrations
└── SQL Scripts
```

Responsibilities: table creation, SQL queries, backup, restore.

Main tables: `Users`, `Messages`, `Groups`, `Transfers`, `AuditLogs`, `Settings`. Full specification details are in the [Requirements Specification](Cahier_des_charges.pdf).

### models/

Business objects used by the application: `User`, `Message`, `Conversation`, `Transfer`, `Notification`, `AuditLog`, `Group`, `Settings`.

### services/

Cross-cutting services used by several modules: `NotificationService`, `AudioService`, `FileService`, `SettingsService`, `LoggerService`.

### resources/

Graphical resources: `icons/`, `images/`, `sounds/`, `translations/`, `fonts/`, `styles/`.

### tests/

Unit and integration tests: `UnitTests/`, `IntegrationTests/`, `NetworkTests/`.

### docs/

Project documentation: requirements specification, UML diagrams, technical and user documentation.

## Build

**Linux**

```bash
mkdir build
cd build
cmake ..
cmake --build .
```

**Windows** — Qt Creator or Visual Studio 2022

**Dependencies** — Qt 6, CMake, OpenSSL, SQLite

## Related Documents

- Team organization and responsibilities: [TEAM.md](TEAM.md)
- Planned versions and developments: [ROADMAP.md](ROADMAP.md)
- Git workflow and conventions: [../CONTRIBUTING.md](../CONTRIBUTING.md)
