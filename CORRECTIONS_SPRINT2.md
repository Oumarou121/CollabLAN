# CollabLAN — Corrections apportées après vérification (Sprint 0/1/2)

Vérification effectuée : compilation complète (CMake + Qt 6.4 + OpenSSL) et
exécution de la suite de tests (`ctest`). Etat initial : build en échec (1
erreur de compilation), puis 6 suites de tests sur 13 en échec une fois le
build corrigé. Etat final : **build propre, 13/13 suites de tests passantes**.

## Bugs corrigés

### 1. Erreur de compilation — `network/Messaging/MessagingService.cpp`
`QWebSocket::errorOccurred` n'existe pas dans toutes les versions de Qt6
(absent en Qt 6.4). Remplacé par la surcharge portable
`QOverload<QAbstractSocket::SocketError>::of(&QWebSocket::error)`.

### 2. Bug critique — `database/DatabaseManager.cpp`
Le chemin de repli pour localiser le dossier `Migrations/` était construit
avec `QDir(__FILE__)`, qui traite le chemin du fichier source comme un
dossier — ce chemin n'existe jamais sur le disque, donc `dir.exists()`
retournait toujours `false`. **Conséquence : aucune migration SQL n'était
jamais appliquée**, la base de données restait vide (pas de table `Users`,
`Messages`, etc.), ce qui faisait planter en cascade tous les tests
dépendant du schéma (UserManager, UserRepository, MessagingManager,
GroupManager...).
Corrigé avec `QFileInfo(__FILE__).dir()`, qui retourne le vrai dossier
contenant le fichier source.

### 3. Injection SQL / crash sur apostrophe — `database/Repositories/MessageRepository.cpp`
`MessageRepository::insert()` construisait la requête `INSERT` par
concaténation de chaînes (`'%3'` avec le contenu du message injecté
directement). Toute apostrophe dans le contenu (très fréquent : "l'ami",
"it's"...) cassait la requête SQL, et un contenu malveillant pouvait
altérer la requête (injection SQL). Corrigé avec une requête préparée
(`bindValue`).

### 4. Même bug — `core/MessagingManager.cpp` (`sendMessage`)
Même défaut dans l'insertion du message en local avant envoi réseau.
Corrigé avec une requête préparée.

### 5. Sérialisation JSON manuelle fragile — `core/MessagingManager.cpp`
Le payload réseau envoyé était construit par concaténation de chaînes
(`"{\"content\":\"%3\"}"`), cassant dès que le contenu contenait un
guillemet. Remplacé par `QJsonObject` + `QJsonDocument`.

### 6. Fonctionnalité manquante (TODO) — réception des messages réseau
`app/Application.cpp` recevait les messages du réseau (`MessagingServer::
messageReceived`) mais se contentait de les logguer (`qDebug()`) sans les
traiter — TODO explicite dans le code.
Ajout de `MessagingManager::receiveMessage(const QString &jsonPayload)` :
parse le JSON, valide les champs, persiste le message en base (sans le
renvoyer sur le réseau) et émet `messageReceived` (ce qui déclenche
`NotificationManager::onMessageReceived`, donc une notification UI).
`Application.cpp` appelle maintenant cette méthode au lieu de se contenter
d'un log.

### 7. Tests obsolètes — `tests/UnitTests/test_databasemanager.cpp`
Deux assertions vérifiaient `schemaVersion() == 2`, écrites quand seules
2 migrations existaient. Il y en a maintenant 4 (Sprint 2/3 ont ajouté
`002_add_conversations_table.sql`, `002_add_user_password.sql`,
`003_update_messages_table.sql`). Mis à jour à `4`.

### 8. Test fragile (piège QSignalSpy) — `tests/UnitTests/test_messagingservice.cpp`
`disconnectEmitsSignal()` échouait de façon systématique (pas flaky) car
le signal `disconnected()` peut être émis de façon synchrone dans
`QWebSocket::close()` selon la plateforme : le compteur du spy était déjà
à 1 au moment d'appeler `wait()`, qui attend une *nouvelle* émission et
finissait donc toujours en timeout. Corrigé en ne ré-attendant que si le
signal n'a pas déjà été reçu.

### 9. Warnings QML répétés sur Windows — style non-natif requis
En testant l'appli lancée sur Windows (`app/Debug/CollabLAN.exe`), la console
affichait un avertissement pour quasiment chaque `Button`/`Label` de chaque
vue (`LoginView`, `HomeView`, `UsersView`, `ChatView`, `ConversationsView`,
`CreateGroupView`...) :
```
The current style does not support customization of this control
(property: "background"/"contentItem"...).
```
Cause : toutes les vues QML personnalisent `background`/`contentItem` sur des
`Button`/`Label` de Qt Quick Controls, ce qui n'est possible qu'avec un style
non-natif (`Basic`, `Fusion`, `Material`...). Aucun style n'était forcé nulle
part dans le code, donc l'appli utilisait le style natif de la plateforme
(`Windows` style sous Windows), qui ignore silencieusement ces
personnalisations (couleurs/formes du thème non appliquées) et logue un
avertissement par contrôle.
Corrigé : `QQuickStyle::setStyle("Basic")` est maintenant appelé au tout
début de `main()`, avant la création de `QGuiApplication` (le style doit
être fixé avant l'instanciation du premier contrôle Qt Quick). Modules
`QuickControls2` ajoutés au `find_package` et au `target_link_libraries` de
`app/`. Reste surchargeable via la variable d'environnement
`QT_QUICK_CONTROLS_STYLE` si besoin de tester un autre style.

## Note (pas un bug de code)

Le log Windows montre aussi `qml: CrÚer groupe: SSS membres: [2,3]` au lieu
de `Créer groupe`. Le fichier source (`CreateGroupView.qml`) contient bien
`"Créer groupe:"` en UTF-8 correct — ce n'est donc pas un bug du code, mais
un affichage tronqué par la page de code de la console Windows (cmd/PowerShell
n'interprète pas nativement l'UTF-8 émis par `console.log`/`qDebug`). Pour un
affichage correct dans le terminal, lancer `chcp 65001` avant l'exécutable,
ou utiliser Windows Terminal (UTF-8 par défaut). Aucune correction de code
nécessaire.

## Tests ajoutés

- `test_messagingmanager.cpp` : `receiveMessage_persistsAndEmitsSignal`,
  `receiveMessage_survivesApostropheInContent` (non-régression du bug #3/#4),
  `receiveMessage_rejectsInvalidJson`, `receiveMessage_rejectsUnknownType`.
- `test_messagerepository.cpp` : `insert_survivesApostropheInContent`
  (non-régression du bug #3).

## Résultat final

```
100% tests passed, 0 tests failed out of 13
```

## Non modifié (hors périmètre Sprint 0-2, normal à ce stade)

Les modules/fichiers suivants restent des squelettes (`// TODO`) car ils
appartiennent aux Sprints 3 à 5 et n'ont pas encore été attaqués :
`TransferService`, `VoiceService`, `PermissionManager`, `AuditManager`,
`SettingsRepository`, `AuditLogRepository`, `TransferRepository`,
`FileService`, `LoggerService`, `AudioService`. Ce n'est pas une anomalie.
