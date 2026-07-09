# Guide de contribution et organisation Git

## Objectif

Ce document décrit les règles de travail de l'équipe afin de garantir un développement organisé, limiter les conflits de fusion (merge conflicts) et assurer la qualité du code.

Pour la répartition des rôles entre les trois développeurs, voir [docs/TEAM.md](docs/TEAM.md).

---

## Organisation des branches

Le dépôt Git est organisé autour de cinq types de branches `feature/*`, toutes fusionnées dans `develop` :

```
main
│
develop
│
├── feature/ui         → Développeur 1
├── feature/network    → Développeur 2
├── feature/database   → Développeur 2
├── feature/core       → Développeur 3
└── feature/docs       → équipe entière
```

### main

Contient uniquement les versions stables du projet. Aucun développement direct n'est autorisé sur cette branche.

### develop

Sert à intégrer les nouvelles fonctionnalités. Toutes les branches `feature/*` y sont fusionnées après validation. Une fois plusieurs fonctionnalités validées, `develop` est fusionnée dans `main` pour publier une nouvelle version (voir [docs/ROADMAP.md](docs/ROADMAP.md)).

### feature/ui

QML, composants graphiques, navigation, thèmes, animations.

### feature/network

UDP, TCP, WebSocket, WebRTC, OpenSSL.

### feature/core

Gestion des utilisateurs, services, notifications, audit, paramètres.

### feature/database

Tables SQLite, requêtes SQL, repositories, sauvegarde, migration.

### feature/docs

README, cahier des charges, UML, documentation technique.

---

## Workflow de développement

Chaque nouvelle fonctionnalité suit le processus suivant :

1. Mettre à jour la branche `develop`
2. Créer une nouvelle branche `feature`
3. Développer la fonctionnalité
4. Tester les modifications
5. Effectuer un commit
6. Pousser la branche sur GitHub
7. Créer une Pull Request
8. Faire relire le code par au moins un autre membre de l'équipe
9. Fusionner dans `develop`

```
          main
           ▲
           │
        develop
     ▲     ▲      ▲
     │     │      │
feature/ui  feature/network  feature/core
```

---

## Convention de nommage des branches

```
feature/nom-fonctionnalite
bugfix/nom-correctif
hotfix/nom-correctif
release/v1.0
docs/documentation
```

Exemples :

```
feature/chat
feature/file-transfer
feature/voice-call
feature/settings
bugfix/login
release/v1.0
```

---

## Convention des messages de commit

```
feat: nouvelle fonctionnalité
fix: correction d'un bug
docs: modification de la documentation
refactor: amélioration du code
style: mise en forme
test: ajout ou modification de tests
chore: tâches techniques
```

Exemples :

```
feat(chat): ajout de la messagerie privée
feat(network): découverte automatique des machines
fix(database): correction de la sauvegarde SQLite
docs: mise à jour du README
refactor(core): amélioration de la gestion des utilisateurs
```

---

## Règles de développement

- Une seule fonctionnalité par branche.
- Ne jamais développer directement sur `main`.
- Toujours synchroniser sa branche avec `develop` avant de commencer.
- Tester les modifications avant chaque push.
- Les Pull Requests doivent être revues par au moins un autre membre de l'équipe.
- Respecter les conventions de codage C++ et Qt.
- Documenter les nouvelles fonctionnalités.

---

## Outils utilisés

Git · GitHub · CMake · Qt Creator · Visual Studio Code · Qt 6 · C++23
