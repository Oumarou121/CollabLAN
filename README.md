<p align="center">
  <img src="ui/Assets/logo.png" alt="CollabLAN Logo" width="180"/>
</p>

<h1 align="center">CollabLAN</h1>

<p align="center">
Application de collaboration d'équipe fonctionnant entièrement sur réseau local (LAN), sans dépendance à Internet.
</p>

<p align="center">
C++23 · Qt 6 / QML · SQLite · UDP · TCP · WebSocket · WebRTC · OpenSSL (TLS)
</p>

---

## Présentation

**CollabLAN** permet aux membres d'un même réseau local de se découvrir automatiquement, d'échanger des messages (individuels et de groupe), de partager des fichiers et des dossiers synchronisés, de passer des appels vocaux et de suivre l'activité du réseau via un journal d'audit — le tout sans connexion Internet et sans serveur central obligatoire.

Le logiciel s'adresse aux petites équipes, établissements scolaires, administrations ou laboratoires souhaitant une solution de communication locale, chiffrée de bout en bout entre postes autorisés, et résiliente aux pannes.

## Fonctionnalités

### Communication

- **Découverte automatique** des postes présents sur le réseau (annonces UDP)
- **Messagerie individuelle et de groupe**, en temps réel (WebSocket), avec historique local (SQLite)
- **Appels vocaux** peer-to-peer (WebRTC), avec signalisation et gestion de l'état de l'appel
- **Notifications** locales pour les messages, transferts, connexions/déconnexions et appels entrants

### Fichiers

- **Transfert de fichiers point à point** (TCP), par blocs, avec reprise automatique après coupure réseau et vérification d'intégrité
- **Dossiers partagés synchronisés** entre postes : détection des changements (ajout/modification/suppression), watcher de système de fichiers, historique de synchronisation, permissions par dossier

### Sécurité et administration

- Toutes les connexions entre postes sont **authentifiées par certificat et chiffrées (TLS/OpenSSL)**
- **Liste blanche cryptographique des machines autorisées**, avec trois états (`pending` / `authorized` / `revoked`) : une machine inconnue est toujours mise en attente et refusée par défaut ; seul un administrateur, depuis une machine déjà autorisée, peut faire passer une machine en `authorized`. Bootstrap automatique de la première machine admin sur une base vide
- **Gestion des comptes utilisateurs** (rôles, statuts, mots de passe hashés)
- **Journal d'audit** consultable et exportable (connexions, messages, transferts, appels, tentatives refusées)
- **Paramètres globaux** (nom du poste, thème, langue, dossier de téléchargement par défaut)

### Résilience réseau (architecture hybride)

- Le réseau peut fonctionner en **pair-à-pair pur** ou avec un **poste élu serveur temporaire**
- **Élection de serveur** déterministe par heartbeat UDP (`ElectionService`) : en cas de panne du serveur, un nouveau poste est élu automatiquement (priorité + UUID comme départage), sans intervention manuelle
- **Réconciliation post-panne** (`SyncService`) : à la reconnexion, les postes échangent leurs journaux de synchronisation pour rattraper les événements manqués pendant la bascule

## Architecture technique

```
                Interface Qt Quick/QML  (ui/)
                         │
                         ▼
                 Logique métier C++23   (core/)
                         │
         ┌───────────────┴───────────────┐
         ▼                               ▼
   Communication réseau              Base de données
   (network/)                        (database/)
   UDP · TCP · WebSocket
   WebRTC · TLS (OpenSSL)                SQLite
```

| Couche               | Rôle                                                                                                           | Dossier                |
| -------------------- | -------------------------------------------------------------------------------------------------------------- | ---------------------- |
| Présentation         | Interface utilisateur Qt Quick/QML                                                                             | `ui/`                  |
| Application          | Point d'entrée, câblage des services                                                                           | `app/`                 |
| Logique métier       | Gestion utilisateurs, messagerie, groupes, permissions, audit, dossiers partagés — aucune dépendance graphique | `core/`                |
| Réseau               | Découverte, messagerie, transfert, appels, sécurité, élection/synchro                                          | `network/`             |
| Services transverses | Audio, fichiers, notifications, logs, paramètres                                                               | `services/`            |
| Données              | Modèles métier + accès SQLite                                                                                  | `models/`, `database/` |

### Modules réseau (`network/`)

| Module      | Protocole       | Rôle                                                                        |
| ----------- | --------------- | --------------------------------------------------------------------------- |
| `Discovery` | UDP broadcast   | Annonce et détection des postes présents sur le réseau                      |
| `Messaging` | WebSocket (TLS) | Messagerie temps réel, serveur et client                                    |
| `Transfer`  | TCP             | Transfert de fichiers par blocs, avec reprise                               |
| `Voice`     | WebRTC          | Signalisation et flux audio des appels                                      |
| `Security`  | OpenSSL         | Handshake TLS, empreintes de certificats, `TrustedPeerStore`                |
| `Election`  | UDP             | Élection déterministe du serveur temporaire, détection de panne (heartbeat) |
| `Sync`      | WebSocket       | Réconciliation des journaux après bascule de serveur                        |

### Base de données (`database/`)

SQLite, gérée par `DatabaseManager` avec un système de migrations versionnées (`database/Migrations/`, une trentaine de scripts appliqués automatiquement à l'ouverture). Tables principales : `Users`, `Messages`, `Groups`/`GroupMembers`, `Conversations`, `Transfers`, `AuditLogs`, `AuthorizedMachines`, `ServerElection`, `SyncLog`/`SyncOperations`, `SharedFolders`/`SharedFiles`/`SharedFolderAccess`, `CallHistory`, `UserSessions`, `Settings`. Chaque table a son `Repository` dédié (`database/Repositories/`).

### Interface (`ui/`)

Écrans Qt Quick/QML : `Login`, `Home`, `Chat` (conversations, création de groupe), `Users`, `FileTransfer`, `SharedFolder`, `Call`, `Settings`, `Admin` (machines autorisées, journal d'audit, gestion des utilisateurs), avec une bibliothèque de composants réutilisables (`Components/`) et un système de thèmes clair/sombre (`Themes/`).

## Structure du projet

```
CollabLAN/
├── app/            # Point d'entrée : main.cpp, Application.cpp
├── ui/             # Interface Qt Quick/QML
├── core/           # Logique métier (managers, modèles QML, Sync/ pour les dossiers partagés)
├── network/        # Discovery, Messaging, Transfer, Voice, Security, Election, Sync
├── database/        # DatabaseManager, Repositories, Migrations
├── models/         # Objets métier (User, Message, Group, Transfer, AuthorizedMachine, ...)
├── services/       # Services transverses (Audio, File, Notification, Logger, Settings)
├── tests/          # Tests unitaires et d'intégration (Qt Test)
├── docs/           # Documentation détaillée (en/ et fr/)
└── CMakeLists.txt
```

## Compilation

Prérequis : **Qt 6** (Core, Gui, Quick, Qml, QuickControls2, Network, Sql, Test, WebSockets, Multimedia), **CMake ≥ 3.20**, **OpenSSL**, compilateur **C++23**.

```bash
mkdir build
cd build
cmake ..
cmake --build .
```

Testé sous Linux, Windows (Qt Creator / Visual Studio 2022) et macOS.

## Tests

Le projet compte une trentaine d'exécutables de tests (Qt Test) couvrant les repositories, les managers métier, les services réseau et plusieurs scénarios d'intégration (reprise de transfert après coupure, bascule de serveur, synchronisation multi-nœuds des dossiers partagés).

```bash
cd build
ctest --output-on-failure
```

## Modes de fonctionnement

- **Pair-à-pair** : chaque poste est à la fois client et serveur, les échanges se font directement entre postes.
- **Serveur local / hybride avec bascule automatique** : un poste peut jouer le rôle de serveur central ; en cas de panne, `ElectionService` élit automatiquement un remplaçant et `SyncService` réconcilie l'historique à la reconnexion des autres postes.

Dans les deux modes, aucune communication (message, fichier, appel) n'est possible entre deux postes tant que leurs certificats ne sont pas mutuellement approuvés via la liste des machines autorisées.

## Documentation

| Document                                                                                                    | Contenu                                                   |
| ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| [docs/fr/ARCHITECTURE.md](docs/fr/ARCHITECTURE.md) · [docs/en/ARCHITECTURE.md](docs/en/ARCHITECTURE.md)     | Architecture logique et structure du code                 |
| [docs/fr/FONCTIONNEMENT.md](docs/fr/FONCTIONNEMENT.md) · [docs/en/HOW_IT_WORKS.md](docs/en/HOW_IT_WORKS.md) | Déroulement des échanges réseau, scénario poste par poste |
| [docs/fr/ROADMAP.md](docs/fr/ROADMAP.md) · [docs/en/ROADMAP.md](docs/en/ROADMAP.md)                         | Versions et évolutions prévues                            |
| [docs/fr/BACKLOG.md](docs/fr/BACKLOG.md) · [docs/en/BACKLOG.md](docs/en/BACKLOG.md)                         | Backlog détaillé                                          |
| [docs/fr/TEAM.md](docs/fr/TEAM.md) · [docs/en/TEAM.md](docs/en/TEAM.md)                                     | Organisation de l'équipe et responsabilités               |
| [CONTRIBUTING.md](CONTRIBUTING.md) / [CONTRIBUTING.fr.md](CONTRIBUTING.fr.md)                               | Workflow Git, conventions de branches et de commits       |

## Équipe

Projet développé par une équipe de trois développeurs, chacun responsable d'un domaine (interface, réseau/base de données, logique métier) sur une branche `feature/*` dédiée. Détail dans [docs/fr/TEAM.md](docs/fr/TEAM.md).

## Licence

MIT — voir [LICENSE](LICENSE).
