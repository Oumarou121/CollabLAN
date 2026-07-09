# Organisation de l'équipe

Le projet est développé par une équipe de **trois développeurs**, chacun responsable d'un domaine et d'une branche `feature/*` dédiée.

| Développeur   | Domaine                                | Responsabilités                                                                                                                                                                            | Branche associée                      |
| ------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------- |
| Développeur 1 | Interface graphique                    | Qt Quick/QML, composants graphiques, navigation, thèmes, animations, UX/UI                                                                                                                 | `feature/ui`                          |
| Développeur 2 | Communication réseau + Base de données | Découverte réseau (UDP), messagerie (WebSocket), partage de fichiers (TCP), appels vocaux (WebRTC), sécurité (OpenSSL), base de données SQLite (DatabaseManager, Repositories, migrations) | `feature/network`, `feature/database` |
| Développeur 3 | Logique métier                         | Gestion des utilisateurs, audit, administration, paramètres                                                                                                                                | `feature/core`                        |

La branche `feature/docs` (documentation) est partagée par l'ensemble de l'équipe : chacun documente les modules dont il est responsable.

Pour le détail du contenu de chaque branche, voir [../CONTRIBUTING.md](../CONTRIBUTING.md).
Pour la structure des dossiers correspondant à chaque domaine, voir [ARCHITECTURE.md](ARCHITECTURE.md#structure-du-projet).
