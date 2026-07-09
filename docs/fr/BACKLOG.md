# Backlog — CollabLAN

## Objectif du document

Ce document liste les tâches du projet organisées par sprint, avec la répartition entre les trois développeurs (voir [TEAM.md](TEAM.md)). Chaque tâche peut être convertie en Issue GitHub et suivie via un board (GitHub Projects).

Légende : **D1** = UI (Qt Quick/QML) · **D2** = Réseau + Base de données · **D3** = Core (logique métier)

---

## Sprint 0 — Fondations

**Objectif** : le squelette compile, la DB s'initialise, navigation basique entre 2 écrans.

- [ ] `DatabaseManager` : ouverture SQLite + exécution de `001_initial_schema.sql` (D2)
- [ ] Connexion DB testée (ouverture/fermeture propre) (D2)
- [ ] CMake des modules réseau qui compile (D2)
- [ ] Choix de la librairie WebSocket (ex. Qt WebSockets) (D2)
- [ ] Choix de la librairie WebRTC (ex. libdatachannel) (D2)
- [ ] Navigation de base Login → Home (D1)
- [ ] Application de `Themes/Light.qml` globalement (D1)
- [ ] Vérifier `cmake --build .` sur Linux + Windows (Tous)

---

## Sprint 1 — Découverte réseau + Authentification locale

**Objectif** : Alice se connecte, voit Bilal/Chaima apparaître dans la liste en temps réel.

- [ ] `DiscoveryService` : annonce + écoute UDP broadcast (D2)
- [ ] Gestion du timeout / déconnexion dans `DiscoveryService` (D2)
- [ ] `SecurityService` : génération certificat/clé par poste (OpenSSL) (D2)
- [ ] `SecurityService` : handshake TLS basique entre deux postes (D2)
- [ ] `UserManager` : création, authentification, statut utilisateur (D3)
- [ ] `UserRepository` : CRUD utilisateur en base (D2)
- [ ] `Settings` (modèle + repository) : nom du poste, langue, thème, dossier de téléchargement (D2)
- [ ] `LoginView.qml` branché sur `UserManager` (D1)
- [ ] `UsersView.qml` : liste des postes découverts en temps réel (D1)
- [ ] Tests `NetworkTests` pour `DiscoveryService` (D2)
- [ ] Tests `UnitTests` pour `UserManager` (D3)

---

## Sprint 2 — Messagerie (individuelle + groupe)

**Objectif** : messagerie individuelle et de groupe fonctionnelle, historique persistant, notifications.

- [ ] `MessagingService` (WebSocket) : envoi/réception de message (D2)
- [ ] Intégration `MessagingService` sur canal chiffré via `SecurityService` (D2)
- [ ] `MessagingManager` : logique métier conversation individuelle (D3)
- [ ] `GroupManager` : logique métier groupe (création, ajout/retrait membres) (D3)
- [ ] `MessageRepository` : persistance de l'historique des messages (D2)
- [ ] `GroupRepository` : persistance des groupes (D2)
- [ ] `NotificationManager` + `NotificationService` : déclenchement "nouveau message" (D3)
- [ ] `ChatView.qml` : conversation individuelle (D1)
- [ ] `ChatView.qml` : conversation de groupe + création de groupe (D1)
- [ ] Test d'intégration : envoi message PC-A → PC-B (Tous)

---

## Sprint 3 — Partage de fichiers + Notifications complètes

**Objectif** : partage de fichiers fiable avec reprise, notifications systèmes complètes.

- [ ] `TransferService` (TCP) : transfert de fichier par blocs (D2)
- [ ] `TransferService` : reprise après interruption réseau (D2)
- [ ] `TransferRepository` : historique + statut des transferts (D2)
- [ ] `AudioService` : sons de notification (D3)
- [ ] `FileTransferView.qml` : sélection fichier + barre de progression (D1)
- [ ] Intégration `NotificationService` dans l'UI (toasts/son) sur tous les événements (D1)
- [ ] Test : transfert de gros fichier avec coupure réseau simulée (Tous)

---

## Sprint 4 — Appels vocaux + Journal d'audit

**Objectif** : appels vocaux fonctionnels, audit complet consultable.

- [ ] `VoiceService` (WebRTC) : signalisation d'appel (D2)
- [ ] `VoiceService` : établissement de session audio P2P (D2)
- [ ] `AuditManager` : enregistrement des événements (connexions, messages, transferts, appels, refus) (D3)
- [ ] `AuditLogRepository` : persistance du journal d'audit (D2)
- [ ] `CallView.qml` : appel entrant/sortant, statuts en temps réel (D1)
- [ ] `AdminView.qml` : consultation et export du journal d'audit (D1)
- [ ] Test d'intégration bout-en-bout sur le scénario des 3 postes (voir [FONCTIONNEMENT.md](FONCTIONNEMENT.md)) (Tous)

---

## Sprint 5 — Administration + Stabilisation (bêta → v1.0)

**Objectif** : v1.0 stable et publiable.

- [ ] `PermissionManager` : gestion des rôles (admin/utilisateur) (D3)
- [ ] `PermissionManager` : gestion des machines autorisées/révoquées (D3)
- [ ] `AdminView.qml` complet : utilisateurs, machines autorisées, paramètres globaux (D1)
- [ ] Durcissement `SecurityService` : rejet + audit des machines non autorisées (D2)
- [ ] Correction de bugs remontés des sprints précédents (Tous)
- [ ] Tests de charge (3+ postes simultanés) (Tous)
- [ ] Revue de code croisée complète (Tous)
- [ ] Mise à jour de la documentation (`feature/docs`) (Tous)
- [ ] Merge `develop` → `main`, tag `v1.0` (Chef de projet)

---

## Points de vigilance transverses

- Définir les interfaces réseau ↔ core dès le Sprint 1 (ex. signature des méthodes entre `MessagingService` et `MessagingManager`) pour éviter les blocages en Sprint 2-3.
- Prévoir des mocks/stubs côté UI (D1) pour ne pas être bloqué en attendant le travail de D2/D3.
- Revue de code obligatoire avant tout merge dans `develop` (voir [../CONTRIBUTING.md](../CONTRIBUTING.md)).
- Revérifier la conformité au [Cahier des charges](Cahier_des_charges.pdf) à chaque fin de sprint.

---

## Documents liés

- [ROADMAP.md](ROADMAP.md) — versions et évolutions prévues
- [TEAM.md](TEAM.md) — répartition des responsabilités
- [ARCHITECTURE.md](ARCHITECTURE.md) — architecture logique et structure du code
- [FONCTIONNEMENT.md](FONCTIONNEMENT.md) — scénario de fonctionnement détaillé
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — workflow Git et conventions
