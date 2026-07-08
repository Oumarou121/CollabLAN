# Contribution Guide and Git Organization

## Purpose

This document describes the team's working rules to ensure organized development, limit merge conflicts, and maintain code quality.

For the breakdown of roles among the three developers, see [docs/TEAM.md](docs/TEAM.md).

---

## Branch Organization

The Git repository is organized around five `feature/*` branch types, all merged into `develop`:

```
main
│
develop
│
├── feature/ui         → Developer 1
├── feature/network    → Developer 2
├── feature/database   → Developer 2
├── feature/core       → Developer 3
└── feature/docs       → whole team
```

### main

Contains only stable versions of the project. No direct development is allowed on this branch.

### develop

Used to integrate new features. All `feature/*` branches are merged into it after validation. Once several features have been validated, `develop` is merged into `main` to publish a new version (see [docs/ROADMAP.md](docs/ROADMAP.md)).

### feature/ui

QML, graphical components, navigation, themes, animations.

### feature/network

UDP, TCP, WebSocket, WebRTC, OpenSSL.

### feature/core

User management, services, notifications, audit, settings.

### feature/database

SQLite tables, SQL queries, repositories, backup, migration.

### feature/docs

README, requirements specification, UML, technical documentation.

---

## Development Workflow

Each new feature follows this process:

1. Update the `develop` branch
2. Create a new `feature` branch
3. Develop the feature
4. Test the changes
5. Make a commit
6. Push the branch to GitHub
7. Create a Pull Request
8. Have the code reviewed by at least one other team member
9. Merge into `develop`

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

## Branch Naming Convention

```
feature/feature-name
bugfix/fix-name
hotfix/fix-name
release/v1.0
docs/documentation
```

Examples:

```
feature/chat
feature/file-transfer
feature/voice-call
feature/settings
bugfix/login
release/v1.0
```

---

## Commit Message Convention

```
feat: new feature
fix: bug fix
docs: documentation change
refactor: code improvement
style: formatting
test: adding or modifying tests
chore: technical tasks
```

Examples:

```
feat(chat): add private messaging
feat(network): automatic machine discovery
fix(database): fix SQLite backup
docs: update README
refactor(core): improve user management
```

---

## Development Rules

- One feature per branch only.
- Never develop directly on `main`.
- Always sync your branch with `develop` before starting.
- Test your changes before every push.
- Pull Requests must be reviewed by at least one other team member.
- Follow C++ and Qt coding conventions.
- Document new features.

---

## Tools Used

Git · GitHub · CMake · Qt Creator · Visual Studio Code · Qt 6 · C++23
