# Fonctionnement de LocaLink

## Objectif du document

Ce document décrit **comment LocaLink fonctionne concrètement** une fois déployé sur un réseau local, à travers un scénario de référence impliquant **trois postes**. Il complète le [Cahier des charges](Cahier_des_charges.pdf) (besoins) et l'[ARCHITECTURE.md](ARCHITECTURE.md) (structure du code) en expliquant le déroulement réel des échanges réseau, poste par poste, fonctionnalité par fonctionnalité.

---

## Scénario de référence

On considère trois ordinateurs connectés au même réseau local (même sous-réseau, ex. Wi-Fi ou switch d'entreprise) :

```
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│     PC-A      │      │     PC-B      │      │     PC-C      │
│  Alice        │      │  Bilal        │      │  Chaima       │
│  192.168.1.10 │      │  192.168.1.11 │      │  192.168.1.12 │
└───────┬───────┘      └───────┬───────┘      └───────┬───────┘
        │                      │                      │
        └──────────────┬───────┴──────────┬───────────┘
                        │   Réseau local (LAN)         │
                        └───────────────────────────────┘
```

Chaque poste exécute une instance de LocaLink. Il n'y a **aucune connexion Internet** requise. Le mode utilisé ici est le mode **Peer-to-Peer** (chaque poste est à la fois client et serveur) ; le mode **Serveur local** fonctionne sur le même principe mais avec un poste faisant office de serveur central.

---

## 1. Démarrage de l'application

Au lancement, chaque instance de LocaLink :

1. Charge les paramètres locaux (nom du poste, langue, thème, dossier de téléchargement — voir `Settings`).
2. Initialise le module `Security` (OpenSSL) : génère ou charge le certificat/clé du poste.
3. Démarre les services réseau : écoute UDP (découverte), écoute TCP (transferts), serveur WebSocket (messagerie).
4. Lance le module `Discovery`, qui commence à annoncer et à écouter la présence des autres machines.

À cet instant, PC-A, PC-B et PC-C tournent chacun indépendamment, sans encore se connaître.

---

## 2. Découverte automatique (UDP)

**Protocole : UDP (broadcast/multicast)**

1. PC-A envoie périodiquement un **paquet UDP broadcast** sur le réseau local contenant : son identifiant, son nom de poste, son adresse IP, son statut (en ligne).
2. PC-B et PC-C, à l'écoute sur le même port UDP, reçoivent ce paquet et l'ajoutent à leur **liste des utilisateurs connectés**.
3. Symétriquement, PC-B et PC-C envoient eux aussi leurs propres annonces, que PC-A reçoit.
4. Si un poste se déconnecte (fermeture de l'app ou timeout sans annonce), les autres postes le retirent de leur liste et affichent une **notification de déconnexion**.

```
PC-A  ── UDP broadcast (annonce) ──►  PC-B, PC-C
PC-B  ── UDP broadcast (annonce) ──►  PC-A, PC-C
PC-C  ── UDP broadcast (annonce) ──►  PC-A, PC-B
```

Résultat : Alice voit dans son interface Bilal et Chaima « en ligne », et inversement.

---

## 3. Authentification et sécurité

**Protocole : OpenSSL (TLS) au-dessus de TCP/WebSocket**

Avant tout échange de contenu (message, fichier, appel), une **poignée de main sécurisée** a lieu entre les deux postes concernés :

1. Le poste initiateur (ex. PC-A) établit une connexion chiffrée (TLS) vers le poste destinataire (PC-B).
2. Les certificats sont vérifiés : seules les **machines autorisées** (liste gérée par l'administration) peuvent établir une session.
3. Une fois la session validée, tous les échanges entre PC-A et PC-B (messages, fichiers, voix) transitent chiffrés sur ce canal.

Si PC-C n'est pas autorisé par l'administrateur du réseau (ex. machine non approuvée), toute tentative de connexion est rejetée et enregistrée dans le journal d'audit comme tentative refusée.

---

## 4. Messagerie (individuelle et de groupe)

**Protocole : WebSocket (sur connexion chiffrée)**

### Message individuel

1. Alice (PC-A) ouvre une conversation avec Bilal (PC-B) et tape un message.
2. Le message est envoyé via **WebSocket** directement à PC-B (canal déjà authentifié à l'étape 3).
3. PC-B reçoit le message, l'affiche dans l'interface, l'enregistre dans l'historique local (SQLite), et déclenche une **notification**.
4. Un accusé de réception peut être renvoyé à PC-A (statut « reçu » / « lu »).

### Message de groupe

1. Alice crée un groupe incluant Bilal et Chaima.
2. Lorsqu'elle envoie un message au groupe, LocaLink diffuse le message **en parallèle** vers PC-B et PC-C via WebSocket.
3. Chaque poste reçoit, affiche et enregistre le message dans l'historique du groupe.

```
PC-A ──message──► PC-B   (conversation individuelle)

PC-A ──message──┬─► PC-B
                 └─► PC-C   (conversation de groupe)
```

---

## 5. Partage de fichiers

**Protocole : TCP**

1. Chaima (PC-C) sélectionne un fichier à envoyer à Alice (PC-A).
2. LocaLink ouvre une **connexion TCP dédiée** entre PC-C et PC-A pour ce transfert (distincte du canal de messagerie).
3. Le fichier est transféré par blocs (chunks) ; une **barre de progression** est affichée en temps réel sur les deux postes.
4. En cas d'interruption (perte réseau, fermeture de l'app), le transfert peut être **repris** à partir du dernier bloc reçu, sans repartir de zéro.
5. À la fin du transfert, PC-A reçoit une **notification** et le fichier est déposé dans le dossier de téléchargement configuré (`Settings`).
6. L'opération est enregistrée dans le journal d'audit des deux côtés (émission / réception).

```
PC-C ── connexion TCP dédiée ── envoi du fichier (par blocs) ──► PC-A
                                        │
                                progression + reprise possible
```

---

## 6. Notifications

Chaque événement significatif déclenche une notification locale sur le poste concerné :

| Événement | Déclenché par |
|---|---|
| Nouveau message | Réception WebSocket |
| Transfert de fichier terminé / échoué | Module `Transfer` (TCP) |
| Utilisateur connecté / déconnecté | Module `Discovery` (UDP) |
| Appel entrant | Module `Voice` (WebRTC) |

Exemple : quand Bilal (PC-B) reçoit un message d'Alice pendant que la fenêtre de chat n'est pas active, une notification système apparaît (son + alerte visuelle, selon les `Settings`).

---

## 7. Appels vocaux

**Protocole : WebRTC**

1. Alice (PC-A) lance un appel vers Bilal (PC-B).
2. PC-B reçoit une **notification d'appel entrant** avec les options répondre / refuser.
3. Si Bilal répond, une session **WebRTC** est établie directement entre PC-A et PC-B pour le flux audio (peer-to-peer, faible latence, adapté au LAN).
4. L'état de l'appel (en cours, terminé, refusé, manqué) est affiché en temps réel sur les deux interfaces.
5. À la fin de l'appel, l'événement (durée, participants) est enregistré dans le journal d'audit.

```
PC-A ── invitation d'appel (signalisation) ──► PC-B
PC-A ◄──────── flux audio WebRTC ────────────► PC-B
```

---

## 8. Journal d'audit

Chaque poste (ou le serveur local, en mode Serveur) enregistre localement dans SQLite (table `AuditLogs`) :

- Connexions / déconnexions (depuis `Discovery`)
- Messages envoyés/reçus (métadonnées, pas nécessairement le contenu)
- Transferts de fichiers (émission/réception, succès/échec)
- Appels (durée, participants, statut)
- Tentatives de connexion refusées (machines non autorisées)

Un administrateur (ex. Alice, si elle a le rôle admin) peut consulter et **exporter** ces journaux depuis l'écran d'administration.

---

## 9. Administration

Un utilisateur avec droits d'administration peut, depuis son poste :

- Gérer la liste des **machines autorisées** sur le réseau (accepter/révoquer PC-B, PC-C…)
- Gérer les **comptes utilisateurs** et leurs permissions
- Consulter le **journal d'audit** de l'ensemble des postes visibles
- Modifier les **paramètres globaux** applicables à l'équipe/l'organisation

---

## Résumé des flux réseau par fonctionnalité

| Fonctionnalité | Protocole | Type de connexion |
|---|---|---|
| Découverte des postes | UDP | Broadcast/multicast |
| Messagerie (individuelle/groupe) | WebSocket | Point à point (ou diffusion pour les groupes) |
| Partage de fichiers | TCP | Connexion dédiée par transfert |
| Appels vocaux | WebRTC | Peer-to-peer direct |
| Sécurité (chiffrement/auth) | OpenSSL (TLS) | Sous-jacent à WebSocket/TCP |
| Stockage local (historique, audit) | SQLite | Local à chaque poste |

---

## Documents liés

- [Cahier des charges](Cahier_des_charges.pdf) — besoins et contraintes fonctionnelles
- [ARCHITECTURE.md](ARCHITECTURE.md) — architecture logique et structure du code
- [TEAM.md](TEAM.md) — répartition des responsabilités
- [ROADMAP.md](ROADMAP.md) — évolutions prévues (v1.1, v2.0)
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — workflow Git et conventions
