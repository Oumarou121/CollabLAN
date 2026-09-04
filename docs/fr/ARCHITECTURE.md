# Architecture technique — LocaLink

## Architecture en couches

Le logiciel adopte une architecture en couches :

```
                Interface Qt Quick/QML
                         │
                         ▼
                 Logique métier (C++23)
                         │
         ┌───────────────┴───────────────┐
         ▼                               ▼
 Communication réseau             Base de données
   UDP / TCP / WebSocket             SQLite
       WebRTC / OpenSSL
```

1. **Présentation** — Interface utilisateur en Qt Quick/QML
2. **Logique métier** — C++23, aucune dépendance graphique
3. **Communication réseau** — UDP, TCP, WebSocket, WebRTC, OpenSSL
4. **Données** — SQLite

## Technologies

| Technologie | Utilisation |
|---|---|
| C++23 | Langage principal |
| Qt 6 | Framework principal |
| Qt Quick / QML | Interface graphique |
| SQLite | Base de données locale |
| UDP | Découverte automatique des machines |
| TCP | Transfert de fichiers |
| WebSocket | Messagerie en temps réel |
| WebRTC | Appels vocaux |
| OpenSSL | Chiffrement et authentification |
| CMake | Compilation |

Le logiciel fonctionne en mode **Peer-to-Peer** ou en mode **Serveur local**, entièrement sur réseau local. Toutes les communications sont authentifiées, chiffrées et limitées aux machines autorisées (voir le [Cahier des charges](Cahier_des_charges.pdf) pour le détail des contraintes).

## Structure du projet

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

Point d'entrée de l'application : initialisation de Qt, chargement de QML, configuration générale, démarrage des services.

Exemples : `main.cpp`, `Application.cpp`, `Application.h`

### ui/

Interface graphique complète en Qt Quick/QML (responsabilité Développeur 1).

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

Chaque dossier contient les fichiers QML d'un écran ou de composants réutilisables.

### core/

Logique métier de l'application (responsabilité Développeur 3) : gestion des utilisateurs, messagerie, notifications, journal d'audit, gestion des groupes, permissions.

Aucune interface graphique ne doit être présente dans ce dossier.

### network/

Communications réseau (responsabilité Développeur 2).

```
network/
├── Discovery/   → découverte UDP
├── Messaging/   → WebSocket
├── Transfer/    → TCP
├── Voice/       → WebRTC
└── Security/    → chiffrement OpenSSL
```

### database/

Gestion de SQLite (responsabilité Développeur 3).

```
database/
├── DatabaseManager
├── Repositories
├── Migrations
└── SQL Scripts
```

Responsabilités : création des tables, requêtes SQL, sauvegarde, restauration.

Tables principales : `Users`, `Messages`, `Groups`, `Transfers`, `AuditLogs`, `Settings`. Le détail des spécifications est dans le [Cahier des charges](Cahier_des_charges.pdf).

### models/

Objets métier manipulés par l'application : `User`, `Message`, `Conversation`, `Transfer`, `Notification`, `AuditLog`, `Group`, `Settings`.

### services/

Services transverses utilisés par plusieurs modules : `NotificationService`, `AudioService`, `FileService`, `SettingsService`, `LoggerService`.

### resources/

Ressources graphiques : `icons/`, `images/`, `sounds/`, `translations/`, `fonts/`, `styles/`.

### tests/

Tests unitaires et d'intégration : `UnitTests/`, `IntegrationTests/`, `NetworkTests/`.

### docs/

Documentation du projet : cahier des charges, diagrammes UML, documentation technique et utilisateur.

## Compilation

**Linux**

```bash
mkdir build
cd build
cmake ..
cmake --build .
```

**Windows** — Qt Creator ou Visual Studio 2022

**Dépendances** — Qt 6, CMake, OpenSSL, SQLite

## Pour aller plus loin

- Organisation de l'équipe et responsabilités : [TEAM.md](TEAM.md)
- Versions et évolutions prévues : [ROADMAP.md](ROADMAP.md)
- Workflow Git et conventions : [../CONTRIBUTING.md](../CONTRIBUTING.md)
