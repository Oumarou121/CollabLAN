<p align="center">
  <img src="resources/logo.png" alt="CollabLAN Logo" width="180"/>
</p>

<h1 align="center">CollabLAN</h1>

<p align="center">
Collaboration software running entirely on a local area network (LAN), with no dependency on the Internet.
</p>

---

## Overview

**CollabLAN** lets users on the same local network automatically discover one another, exchange messages, share files, receive notifications, and make voice calls — all without an Internet connection.

The software is aimed at businesses, schools, administrations, and laboratories looking for a local, secure, and high-performance communication solution.

For the full requirements and constraints, see the [Requirements Specification](docs/Cahier_des_charges.pdf).

## Features (v1.0)

- Automatic user discovery
- Individual and group messaging
- File and folder sharing
- Real-time notifications
- Voice calls
- Audit log
- Administration and user management

Planned future developments (v1.1, v2.0...) are detailed in the [Roadmap](docs/ROADMAP.md).

## Technologies

C++23 · Qt 6 (Qt Quick/QML) · SQLite · UDP/TCP/WebSocket · WebRTC · OpenSSL · CMake

The architecture details (layers, folder structure, role of each module) are described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Build

```bash
mkdir build
cd build
cmake ..
cmake --build .
```

Requirements: Qt 6, CMake, OpenSSL. Build tested on Linux, Windows (Qt Creator / Visual Studio 2022), and macOS.

## Team

Project developed by a team of three developers. Role and responsibility breakdown: see [docs/TEAM.md](docs/TEAM.md).

## Contributing

The Git workflow and branch/commit conventions are described in [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

| Document | Content |
|---|---|
| [docs/Cahier_des_charges.pdf](docs/Cahier_des_charges.pdf) | Requirements, constraints, functional specifications |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Logical architecture, folder structure, technical stack |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Versions and planned developments |
| [docs/TEAM.md](docs/TEAM.md) | Team organization and responsibilities |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Git workflow, branch and commit conventions |

## License

MIT
