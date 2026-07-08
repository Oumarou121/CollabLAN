<p align="center">
  <img src="resources/logo.png" alt="CollabLAN Logo" width="180"/>
</p>

<h1 align="center">CollabLAN</h1>

<p align="center">
Logiciel de collaboration fonctionnant entièrement sur réseau local (LAN), sans dépendance à Internet.
</p>

---

## Présentation

**CollabLAN** permet aux utilisateurs d'un même réseau local de se découvrir automatiquement, d'échanger des messages, de partager des fichiers, de recevoir des notifications et de passer des appels vocaux — le tout sans connexion Internet.

Le logiciel s'adresse aux entreprises, établissements scolaires, administrations et laboratoires souhaitant une solution de communication locale, sécurisée et performante.

Pour le détail des besoins et contraintes, voir le [Cahier des charges](docs/Cahier_des_charges.pdf).

## Fonctionnalités (v1.0)

- Découverte automatique des utilisateurs
- Messagerie individuelle et de groupe
- Partage de fichiers et dossiers
- Notifications en temps réel
- Appels vocaux
- Journal d'audit
- Administration et gestion des utilisateurs

La suite des évolutions prévues (v1.1, v2.0...) est détaillée dans la [Roadmap](docs/ROADMAP.md).

## Technologies

C++23 · Qt 6 (Qt Quick/QML) · SQLite · UDP/TCP/WebSocket · WebRTC · OpenSSL · CMake

Le détail de l'architecture (couches, structure des dossiers, rôle de chaque module) est décrit dans [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Compilation

```bash
mkdir build
cd build
cmake ..
cmake --build .
```

Prérequis : Qt 6, CMake, OpenSSL. Compilation testée sous Linux, Windows (Qt Creator / Visual Studio 2022) et macOS.

## Équipe

Projet développé par une équipe de trois développeurs. Répartition des rôles et responsabilités : voir [docs/TEAM.md](docs/TEAM.md).

## Contribuer

Le workflow Git, les conventions de branches et de commits sont décrits dans [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

| Document | Contenu |
|---|---|
| [docs/Cahier_des_charges.pdf](docs/Cahier_des_charges.pdf) | Besoins, contraintes, spécifications fonctionnelles |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture logique, structure des dossiers, stack technique |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Versions et évolutions prévues |
| [docs/TEAM.md](docs/TEAM.md) | Organisation de l'équipe et responsabilités |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow Git, conventions de branches et de commits |

## Licence

MIT
