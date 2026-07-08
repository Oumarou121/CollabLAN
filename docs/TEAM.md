# Organisation de l'équipe

Le projet est développé par une équipe de **trois développeurs**, chacun responsable d'un domaine et d'une branche `feature/*` dédiée.

| Développeur | Domaine | Responsabilités | Branche associée |
|---|---|---|---|
| Développeur 1 | Interface graphique | Qt Quick/QML, composants graphiques, navigation, thèmes, animations, UX/UI | `feature/ui` |
| Développeur 2 | Communication réseau | Découverte réseau (UDP), messagerie (WebSocket), partage de fichiers (TCP), appels vocaux (WebRTC), sécurité (OpenSSL) | `feature/network` |
| Développeur 3 | Logique métier | Gestion des utilisateurs, base de données SQLite, audit, administration, paramètres | `feature/core`, `feature/database` |

La branche `feature/docs` (documentation) est partagée par l'ensemble de l'équipe : chacun documente les modules dont il est responsable.

Pour le détail du contenu de chaque branche, voir [../CONTRIBUTING.md](../CONTRIBUTING.md).
Pour la structure des dossiers correspondant à chaque domaine, voir [ARCHITECTURE.md](ARCHITECTURE.md#structure-du-projet).
