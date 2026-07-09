# Team Organization

The project is developed by a team of **three developers**, each responsible for a domain and a dedicated `feature/*` branch.

| Developer   | Domain                                | Responsibilities                                                                                                                                                                            | Associated Branch                     |
| ------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------- |
| Developer 1 | Graphical interface                    | Qt Quick/QML, graphical components, navigation, themes, animations, UX/UI                                                                                                                 | `feature/ui`                          |
| Developer 2 | Network communication + Database | Network discovery (UDP), messaging (WebSocket), file sharing (TCP), voice calls (WebRTC), security (OpenSSL), SQLite database (DatabaseManager, Repositories, migrations) | `feature/network`, `feature/database` |
| Developer 3 | Business logic                         | User management, audit, administration, settings                                                                                                                                | `feature/core`                        |

The `feature/docs` branch (documentation) is shared by the whole team: each member documents the modules they are responsible for.

For details on the content of each branch, see [../CONTRIBUTING.md](../CONTRIBUTING.md).
For the folder structure corresponding to each domain, see [ARCHITECTURE.md](ARCHITECTURE.md#project-structure).
