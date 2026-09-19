import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"

/*
 * SharedFolderView - Écran "Dossiers partagés" (module "Shared Folder",
 * 1ère tranche : créer/lister/supprimer des dossiers partagés, façon
 * explorateur de fichiers, sur le même principe visuel que
 * FileTransferView (grille de tuiles FolderTile).
 *
 * Pas de synchronisation réseau ici : "partager" un dossier ne fait
 * qu'indexer localement son contenu (SharedFolderManager::shareFolder(),
 * sans rien envoyer sur le réseau). Le compteur affiché sur chaque tuile
 * est donc le nombre de fichiers indexés localement, pas un statut de
 * synchronisation entre postes (ce dernier arrivera dans une itération
 * future avec FolderWatcher/SyncEngine).
 */
Item {
    id: root

    property var context: (typeof sharedFolderContext !== "undefined") ? sharedFolderContext : null

    signal backRequested()

    property string openedFolderUuid: ""
    property var openedFolderName: ""
    property var openedFolderId: -1
    property bool openedFolderIsLocalOrigin: true
    property var currentFiles: []
    property var browserItems: []
    property string browsedRelativePath: ""
    property var currentSyncHistory: []
    property bool showHistory: false

    // Ids des dossiers actuellement en cours d'indexation en arrière-plan
    // (cf. SyncEngine::reindexFolderAsync() / SharedFolderContext::
    // indexingStarted()) -- alimente l'indicateur "Indexation…" affiché
    // dans l'en-tête pendant que l'appli reste réactive. Un dossier est
    // retiré de cette liste dès que folderReindexed() arrive pour lui
    // (succès ou échec), cf. les deux Connections ci-dessous.
    property var indexingFolderIds: []

    // Ensemble des chemins relatifs en conflit pour le dossier actuellement ouvert.
    // Clé: relativePath  Valeur: chemin du fichier de conflit renommé.
    // Réinitialisé à l'ouverture d'un nouveau dossier.
    property var conflictedFiles: ({})

    // File d'attente des demandes de confirmation de partage (dossiers
    // distants reçus sans localPath) pas encore affichées : plusieurs
    // dossiers peuvent être reçus d'affilée, on les présente un par un
    // plutôt que d'empiler des dialogues.
    property var pendingShareConfirmations: []

    // Filtre rapide (rangee de chips, meme principe que FileTransferView -
    // remplace l'ancien panneau lateral ExplorerSidebar).
    property string activeFilter: "all"   // "all" | "mine" | "received"
    property string searchText: ""
    property string viewMode: "grid"      // "grid" | "list"

    function folderMatchesFilter(isLocalOrigin) {
        switch (root.activeFilter) {
        case "mine": return isLocalOrigin
        case "received": return !isLocalOrigin
        default: return true
        }
    }

    function folderMatchesSearch(name) {
        const q = root.searchText.trim().toLowerCase()
        if (q.length === 0) return true
        return name.toLowerCase().indexOf(q) !== -1
    }

    function itemMatchesSearch(item) {
        const q = root.searchText.trim().toLowerCase()
        if (q.length === 0) return true
        return item.name.toLowerCase().indexOf(q) !== -1
    }

    function hasActiveFilters() {
        return root.searchText.trim().length > 0 || root.activeFilter !== "all"
    }

    function resolveConflictFor(relativePath, conflictPath, resolution) {
        if (!root.context || root.openedFolderId < 0) {
            return false
        }

        const resolved = root.context.resolveConflict(
            root.openedFolderId, relativePath, conflictPath, resolution)
        if (resolved) {
            root.refreshFiles()
            root.refreshHistory()
        }
        return resolved
    }

    function filterIconColor(key) {
        switch (key) {
        case "mine": return Theme.primary
        case "received": return Theme.accent
        default: return Theme.textTertiary
        }
    }
    function filterIconGlyph(key) {
        switch (key) {
        case "mine": return "\uf015"     // home
        case "received": return "\uf063" // arrow-down
        default: return "\uf00a"         // th (tout)
        }
    }

    // Icone + couleur de fichier selon l'extension (meme logique que
    // FileTransferView.fileKindFor), utilisee dans la vue "fichiers" d'un
    // dossier partage. Glyphes Font Awesome 4.7.0.
    function fileKindFor(fileName) {
        const parts = (fileName || "").split(".")
        const ext = parts.length > 1 ? parts[parts.length - 1].toLowerCase() : ""
        switch (ext) {
        case "pdf":
            return { glyph: "\uf1c1", color: Theme.primary }
        case "doc": case "docx": case "odt": case "rtf": case "txt":
            return { glyph: "\uf0f6", color: Theme.primary }
        case "jpg": case "jpeg": case "png": case "gif": case "bmp": case "webp": case "svg":
            return { glyph: "\uf1c5", color: "#0EA5B7" }
        case "zip": case "rar": case "7z": case "tar": case "gz":
            return { glyph: "\uf1c6", color: "#D97706" }
        case "mp4": case "mov": case "avi": case "mkv": case "webm":
            return { glyph: "\uf1c8", color: "#E85C8A" }
        case "mp3": case "wav": case "flac": case "ogg": case "m4a":
            return { glyph: "\uf1c7", color: "#7C5CFF" }
        case "xls": case "xlsx": case "csv":
            return { glyph: "\uf1c3", color: Theme.success }
        case "ppt": case "pptx":
            return { glyph: "\uf1c4", color: Theme.warning }
        default:
            return { glyph: "\uf016", color: Theme.textSecondary }
        }
    }

    function showNextShareConfirmation() {
        if (shareConfirmDialog.visible || root.pendingShareConfirmations.length === 0) {
            return
        }
        const next = root.pendingShareConfirmations.shift()
        shareConfirmDialog.targetFolderId = next.folderId
        shareConfirmDialog.targetFolderName = next.folderName
        shareConfirmDialog.ownerName = next.ownerName
        shareConfirmDialog.suggestedPath = next.suggestedPath
        shareConfirmDialog.allowWrite = next.allowWrite
        shareConfirmDialog.open()
    }

    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 o"
        const units = ["o", "Ko", "Mo", "Go"]
        let value = bytes
        let unitIndex = 0
        while (value >= 1024 && unitIndex < units.length - 1) {
            value /= 1024
            unitIndex++
        }
        return (unitIndex === 0 ? value.toFixed(0) : value.toFixed(1)) + " " + units[unitIndex]
    }

    function openFolder(folderId, name, isLocalOrigin = true, uuid = "") {
        root.openedFolderId = folderId
        root.openedFolderName = name
        root.openedFolderIsLocalOrigin = isLocalOrigin
        root.openedFolderUuid = uuid
        root.showHistory = false
        root.conflictedFiles = {}   // reset des conflits a l'ouverture
        root.browsedRelativePath = ""
        root.refreshFiles()
        root.refreshHistory()
    }

    function refreshFiles() {
        if (root.context && root.openedFolderId >= 0) {
            root.currentFiles = root.context.filesForFolder(root.openedFolderId)
            const conflicts = root.context.getConflicts(root.openedFolderId)
            const conflictMap = {}
            for (let i = 0; i < conflicts.length; i++) {
                conflictMap[conflicts[i].relativePath] = conflicts[i].conflictPath
            }
            root.conflictedFiles = conflictMap
            root.rebuildFileBrowser()
        } else {
            root.currentFiles = []
            root.conflictedFiles = {}
            root.browserItems = []
        }
    }

    function rebuildFileBrowser() {
        const folders = {}
        const files = []
        const prefix = root.browsedRelativePath.length > 0 ? root.browsedRelativePath + "/" : ""
        const q = root.searchText.trim().toLowerCase()

        for (let i = 0; i < root.currentFiles.length; ++i) {
            const file = root.currentFiles[i]
            if (!file.relativePath.startsWith(prefix)) {
                continue
            }
            const remainingPath = file.relativePath.slice(prefix.length)
            const separatorIndex = remainingPath.indexOf("/")
            if (separatorIndex >= 0) {
                const name = remainingPath.slice(0, separatorIndex)
                const path = prefix + name
                if (q.length === 0 || name.toLowerCase().indexOf(q) !== -1) {
                    if (!folders[path]) {
                        folders[path] = { kind: "folder", name: name, path: path, count: 0 }
                    }
                    folders[path].count++
                }
            } else {
                if (q.length === 0 || remainingPath.toLowerCase().indexOf(q) !== -1) {
                    files.push({ kind: "file", name: remainingPath, relativePath: file.relativePath,
                                 size: file.size, version: file.version })
                }
            }
        }

        const folderItems = Object.keys(folders).map(function(path) { return folders[path] })
        folderItems.sort(function(left, right) { return left.name.localeCompare(right.name) })
        files.sort(function(left, right) { return left.name.localeCompare(right.name) })
        root.browserItems = folderItems.concat(files)
    }

    function openBrowserFolder(path) {
        root.browsedRelativePath = path
        root.rebuildFileBrowser()
    }

    function browserPathAt(index) {
        if (root.browsedRelativePath.length === 0) {
            return ""
        }
        return root.browsedRelativePath.split("/").slice(0, index + 1).join("/")
    }

    function goUpInBrowser() {
        const separatorIndex = root.browsedRelativePath.lastIndexOf("/")
        root.browsedRelativePath = separatorIndex >= 0
            ? root.browsedRelativePath.slice(0, separatorIndex)
            : ""
        root.rebuildFileBrowser()
    }

    function refreshHistory() {
        if (root.context && root.openedFolderId >= 0) {
            root.currentSyncHistory = root.context.syncHistoryForFolder(root.openedFolderId, 100)
        } else {
            root.currentSyncHistory = []
        }
    }

    // Rafraichissement automatique apres chaque reindexation declenchee par
    // FolderWatcher (Release 2) ou manuellement : l'utilisateur voit le
    // nouveau contenu + l'historique (Release 3) sans avoir a naviguer.
    Connections {
        target: root.context
        function onFolderReindexed(folderId, changeCount) {
            var idx = root.indexingFolderIds.indexOf(folderId)
            if (idx !== -1) {
                var stillIndexing = root.indexingFolderIds.slice()
                stillIndexing.splice(idx, 1)
                root.indexingFolderIds = stillIndexing
            }
            if (folderId === root.openedFolderId) {
                root.refreshFiles()
                root.refreshHistory()
            }
        }
        // Émis dès que l'indexation démarre en arrière-plan (avant que le
        // résultat ne soit connu) : ajoute folderId à la liste des
        // dossiers en cours d'indexation pour afficher l'indicateur.
        function onIndexingStarted(folderId) {
            if (root.indexingFolderIds.indexOf(folderId) === -1) {
                root.indexingFolderIds = root.indexingFolderIds.concat([folderId])
            }
        }
        // Un fichier reçu via le réseau (synchronisation d'un dossier
        // partagé, cf. FolderSyncService::fileIntegrated) doit rafraîchir
        // la liste des fichiers et l'historique immédiatement, sans que
        // l'utilisateur ait besoin de quitter puis rouvrir cet écran.
        function onFileReceived(folderUuid, relativePath) {
            if (folderUuid === root.openedFolderUuid) {
                root.refreshFiles()
                root.refreshHistory()
            }
        }
        // Un dossier partagé DISTANT vient d'être reçu pour la première
        // fois sans chemin local : demander confirmation avant de
        // provisionner quoi que ce soit sur le disque (au lieu de
        // l'auto-provisionner silencieusement). Plusieurs demandes peuvent
        // arriver d'affilée (plusieurs dossiers reçus en rafale) : on les
        // met en file et on les affiche une par une.
        function onFolderShareConfirmationRequested(folderId, folderName, ownerName, suggestedPath, allowWrite) {
            root.pendingShareConfirmations.push({
                folderId: folderId,
                folderName: folderName,
                ownerName: ownerName,
                suggestedPath: suggestedPath,
                allowWrite: allowWrite
            })
            root.showNextShareConfirmation()
        }
    }

    Component.onCompleted: {
        if (root.context) {
            root.context.refresh()
            root.context.folderFilterProxy.filterMode = root.activeFilter
            root.context.folderFilterProxy.searchText = root.searchText
        }
    }

    onActiveFilterChanged: if (root.context) root.context.folderFilterProxy.filterMode = root.activeFilter
    onSearchTextChanged: {
        if (root.context) root.context.folderFilterProxy.searchText = root.searchText
        root.rebuildFileBrowser()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    FolderDialog {
        id: folderPickerDialog
        title: qsTr("Choisir un dossier local à partager")
        currentFolder: createDialog.localPath.length > 0 ? createDialog.localPath
                       : ((typeof settingsModel !== "undefined" && settingsModel) ? settingsModel.defaultSharedFolderPath : "")
        onAccepted: {
            // selectedFolder est une URL (ex: "file:///C:/Users/..." sous Windows,
            // "file:///home/..." sous Linux/macOS). On ne peut pas juste retirer
            // "file://" : sous Windows il reste alors un "/" en trop devant la
            // lettre de lecteur ("/C:/Users/..."), ce qui rend le chemin invalide.
            let path = decodeURIComponent(selectedFolder.toString())
            path = path.replace(/^file:\/\//, "")
            if (/^\/[A-Za-z]:/.test(path)) {
                // Windows : "/C:/Users/..." -> "C:/Users/..."
                path = path.substring(1)
            }
            createDialog.localPath = path
        }
    }

    // ---- bannière de conflit (Release 8) ----
    // Affichée quand FolderSyncService détecte qu'un fichier reçu entre en
    // conflit avec un fichier local de même nom mais de contenu différent.
    Rectangle {
        id: conflictBanner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: conflictLabel.implicitHeight + Theme.spacingMedium
        color: "#C07000"   // ambre — distinct de la bannière d'erreur rouge
        visible: opacity > 0
        opacity: 0
        z: 11              // au-dessus de la bannière d'erreur (z=10)

        Label {
            id: conflictLabel
            anchors.centerIn: parent
            width: parent.width - Theme.spacingLarge
            color: "#FFFFFF"
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Timer {
            id: conflictTimer
            interval: 6000
            onTriggered: conflictBanner.opacity = 0
        }

        function show(relativePath, conflictPath) {
            conflictLabel.text = qsTr("⚠ Conflit : « %1 » reçu en conflit → renommé « %2 »")
                .arg(relativePath).arg(conflictPath)
            opacity = 1
            conflictTimer.restart()
        }
    }

    // ---- bannière d'erreur ----
    Rectangle {
        id: errorBanner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: errorLabel.implicitHeight + Theme.spacingMedium
        color: Theme.error
        visible: opacity > 0
        opacity: 0
        z: 10

        Label {
            id: errorLabel
            anchors.centerIn: parent
            width: parent.width - Theme.spacingLarge
            color: "#FFFFFF"
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Timer {
            id: errorTimer
            interval: 4000
            onTriggered: errorBanner.opacity = 0
        }

        function show(message) {
            errorLabel.text = message
            opacity = 1
            errorTimer.restart()
        }
    }

    Connections {
        target: root.context
        function onErrorOccurred(message) {
            errorBanner.show(message)
        }
        function onConflictDetected(folderUuid, relativePath, conflictPath) {
            // Enregistre le conflit (badge sur la ligne) et affiche la banniere.
            const updated = Object.assign({}, root.conflictedFiles)
            updated[relativePath] = conflictPath
            root.conflictedFiles = updated
            root.rebuildFileBrowser()
            conflictBanner.show(relativePath, conflictPath)
        }
    }

    // ---- dialogue de création (en 2 etapes : Dossier puis Partage) ----
    AppDialog {
        id: createDialog
        title: qsTr("Nouveau dossier partagé")
        headerIcon: "\uf07b"
        dialogWidth: 500
        // Hauteur calculee sur le contenu reel de l'etape affichee : les
        // ColumnLayout des etapes 1/2 sont visible:false en alternance et
        // sont donc exclus du calcul d'implicitHeight par ColumnLayout
        // (comportement standard QtQuick.Layouts), ce qui fait varier
        // naturellement la hauteur de la carte d'une etape a l'autre.
        dialogHeight: createDialogMainColumn.implicitHeight + Theme.spacingMedium * 2
        standardButtons: Dialog.NoButton
        busyText: qsTr("Indexation et partage en cours…")

        onClosed: busy = false

        property string localPath: ""
        // 1 = "Dossier" (nom, emplacement local, exclusions)
        // 2 = "Partage" (destinataires, permission)
        property int step: 1
        readonly property bool step1Valid: nameField.text.trim().length > 0 && createDialog.localPath.length > 0

        onOpened: {
            nameField.text = ""
            createDialog.step = 1
            // Le champ localPath reste vide par defaut : l'utilisateur doit
            // choisir explicitement un dossier via le selecteur.
            localPath = ""
            allowWriteCheckBox.checked = true
            excludePatternsField.text = ""
            reloadUsers()
        }

        function reloadUsers() {
            availableUsersModel.clear()
            if (!root.context) return
            const users = root.context.availableUsers()
            for (let i = 0; i < users.length; ++i) {
                availableUsersModel.append({
                    userId: users[i].userId,
                    username: users[i].username,
                    selected: false
                })
            }
        }

        ColumnLayout {
            id: createDialogMainColumn
            width: parent.width
            spacing: Theme.spacingMedium

            // ── Indicateur d'etape ──────────────────────────────────────
            AppStepper {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spacingXs
                steps: [qsTr("Dossier"), qsTr("Partage")]
                currentStep: createDialog.step
            }

            // ── Étape 1 : Dossier ────────────────────────────────────────
            ColumnLayout {
                id: step1Column
                Layout.fillWidth: true
                visible: createDialog.step === 1
                spacing: Theme.spacingMedium

                AppTextField {
                    id: nameField
                    Layout.fillWidth: true
                    label: qsTr("Nom du dossier partagé")
                    placeholderText: qsTr("ex : Documents projet")
                }

                Label {
                    text: qsTr("Dossier local à partager")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                FolderDropzone {
                    path: createDialog.localPath
                    onBrowseRequested: folderPickerDialog.open()
                    onPathDropped: function (droppedPath) { createDialog.localPath = droppedPath }
                }

                AppTextField {
                    id: excludePatternsField
                    Layout.fillWidth: true
                    label: qsTr("Exclure de la synchronisation (optionnel)")
                    placeholderText: qsTr("ex : *.log, node_modules, drafts/*")
                    helperText: qsTr("Motifs séparés par des virgules. S'applique en plus des exclusions par défaut (dossiers systèmes, fichiers temporaires…). Local à ce poste.")
                }
            }

            // ── Étape 2 : Partage ────────────────────────────────────────
            ColumnLayout {
                id: step2Column
                Layout.fillWidth: true
                visible: createDialog.step === 2
                spacing: Theme.spacingMedium

                Label {
                    text: qsTr("Partager avec")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }

                Rectangle {
                    Layout.fillWidth: true
                    // Hauteur adaptative au nombre d'utilisateurs (au lieu
                    // d'une hauteur fixe de 160px) : avec peu d'utilisateurs,
                    // une boite toujours haute de 160px laissait un grand
                    // espace vide entre le contenu et les boutons Suivant/
                    // Créer. On garde 160px comme MAXIMUM (scroll au-dela),
                    // et un minimum de 56px pour rester lisible/cliquable
                    // meme a 1 seul utilisateur ou aucun ("Aucun autre
                    // utilisateur").
                    Layout.preferredHeight: Math.max(56, Math.min(
                        usersListView.contentHeight + Theme.spacingSmall * 2, 160))
                    radius: Theme.radiusMedium
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: Theme.border

                    ListView {
                        id: usersListView
                        anchors.fill: parent
                        anchors.margins: Theme.spacingSmall
                        clip: true
                        spacing: 4
                        model: ListModel { id: availableUsersModel }

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: RowLayout {
                            width: usersListView.width
                            spacing: Theme.spacingSmall

                            AppCheckBox {
                                id: userCheckBox
                                checked: selected
                                onCheckedChanged: availableUsersModel.setProperty(index, "selected", checked)
                            }
                            Label {
                                Layout.fillWidth: true
                                text: username
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: availableUsersModel.count === 0
                        text: qsTr("Aucun autre utilisateur")
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                AppCheckBox {
                    id: allowWriteCheckBox
                    text: qsTr("Autoriser la modification (lecture/écriture)")
                    checked: true
                }
            }

            // ── Actions (differentes selon l'etape) ─────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingSmall

                Item { Layout.fillWidth: true }

                AppButton {
                    text: qsTr("Annuler")
                    variant: "ghost"
                    visible: createDialog.step === 1
                    onClicked: createDialog.close()
                }
                AppButton {
                    text: qsTr("Retour")
                    variant: "secondary"
                    visible: createDialog.step === 2
                    onClicked: createDialog.step = 1
                }
                AppButton {
                    text: qsTr("Suivant")
                    variant: "primary"
                    visible: createDialog.step === 1
                    enabled: createDialog.step1Valid
                    onClicked: createDialog.step = 2
                }
                AppButton {
                    text: qsTr("Créer")
                    variant: "primary"
                    visible: createDialog.step === 2
                    enabled: createDialog.step1Valid
                    onClicked: {
                        if (!root.context) return
                        createDialog.busy = true
                        var selectedUserIds = []
                        for (var i = 0; i < availableUsersModel.count; i++) {
                            if (availableUsersModel.get(i).selected) {
                                selectedUserIds.push(availableUsersModel.get(i).userId)
                            }
                        }
                        if (root.context.createFolder(nameField.text.trim(), createDialog.localPath,
                                                       selectedUserIds, allowWriteCheckBox.checked,
                                                       excludePatternsField.text.trim())) {
                            createDialog.close()
                        } else {
                            createDialog.busy = false
                        }
                    }
                }
            }
        }
    }

    // ---- dialogue de modification des motifs d'exclusion (debrief point #4) ----
    AppDialog {
        id: editExcludePatternsDialog
        title: qsTr("Exclusions — %1").arg(editExcludePatternsDialog.targetFolderName)
        headerIcon: "\uf05e"
        dialogWidth: 420
        // Hauteur calculee sur le contenu reel (mainColumn.implicitHeight),
        // meme pattern que AdminView.qml : sans ca, height retombe sur
        // Popup.implicitHeight qui ne remonte pas correctement celui du
        // ColumnLayout enfant (cf. commentaire dans AppDialog.qml).
        dialogHeight: mainColumn.implicitHeight + Theme.spacingMedium * 2
        standardButtons: Dialog.NoButton

        property int targetFolderId: -1
        property string targetFolderName: ""
        property var impactedPaths: []
        // Motifs representes sous forme de chips (plutot qu'un seul champ
        // texte a virgules) : direction visuelle validee sur la maquette.
        property var patternsList: []
        readonly property string patternsText: patternsList.join(",")

        function addPattern(raw) {
            var value = raw.trim()
            if (value.length === 0) return
            if (editExcludePatternsDialog.patternsList.indexOf(value) === -1) {
                editExcludePatternsDialog.patternsList = editExcludePatternsDialog.patternsList.concat([value])
            }
            impactPreviewTimer.restart()
        }

        function removePattern(value) {
            editExcludePatternsDialog.patternsList = editExcludePatternsDialog.patternsList.filter(function(p) { return p !== value })
            impactPreviewTimer.restart()
        }

        function refreshImpactPreview() {
            if (root.context && editExcludePatternsDialog.targetFolderId >= 0) {
                editExcludePatternsDialog.impactedPaths =
                    root.context.previewExcludePatternsImpact(editExcludePatternsDialog.targetFolderId,
                                                               editExcludePatternsDialog.patternsText)
            } else {
                editExcludePatternsDialog.impactedPaths = []
            }
        }

        onOpened: {
            var current = root.context ? root.context.excludePatternsForFolder(editExcludePatternsDialog.targetFolderId) : ""
            editExcludePatternsDialog.patternsList = current.length > 0
                ? current.split(",").map(function(p) { return p.trim() }).filter(function(p) { return p.length > 0 })
                : []
            excludePatternsEditField.text = ""
            // Motifs actuellement enregistres : par definition aucun fichier
            // deja indexe ne peut les matcher (ils seraient deja tombstones),
            // donc l'impact initial est toujours vide -- pas la peine
            // d'attendre le debounce pour l'afficher.
            editExcludePatternsDialog.impactedPaths = []
        }

        ColumnLayout {
            id: mainColumn
            width: parent.width
            spacing: Theme.spacingMedium

            Label {
                text: qsTr("Motifs glob (ex : *.log, node_modules, drafts/*). S'ajoutent aux exclusions par défaut. Ne s'applique qu'à ce poste.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            AppTextField {
                id: excludePatternsEditField
                Layout.fillWidth: true
                placeholderText: qsTr("Tapez un motif puis Entrée…")
                field.onAccepted: {
                    editExcludePatternsDialog.addPattern(text)
                    text = ""
                }
                // Une virgule tapee en cours de saisie cree directement une
                // chip (comportement familier, ex. champs "tags" web).
                field.onTextChanged: {
                    if (text.indexOf(",") !== -1) {
                        var parts = text.split(",")
                        for (var i = 0; i < parts.length - 1; i++) {
                            editExcludePatternsDialog.addPattern(parts[i])
                        }
                        text = parts[parts.length - 1]
                    }
                }
            }

            // Chips des motifs actifs.
            Flow {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall
                visible: editExcludePatternsDialog.patternsList.length > 0

                Repeater {
                    model: editExcludePatternsDialog.patternsList

                    delegate: Rectangle {
                        radius: Theme.radiusMedium
                        color: Theme.primaryMuted
                        border.width: 1
                        border.color: Theme.primary
                        height: 28
                        width: chipRow.implicitWidth + Theme.spacingMedium

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6

                            Label {
                                text: modelData
                                color: Theme.primaryDeep
                                font.pixelSize: Theme.fontSizeCaption
                                font.bold: true
                            }
                            Text {
                                text: "\u2715"
                                color: Theme.primaryDeep
                                font.pixelSize: 10
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: editExcludePatternsDialog.removePattern(modelData)
                                }
                            }
                        }
                    }
                }
            }

            Label {
                visible: editExcludePatternsDialog.patternsList.length === 0
                text: qsTr("Aucun motif d'exclusion pour ce dossier.")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeCaption
                font.italic: true
            }

            Timer {
                id: impactPreviewTimer
                interval: 250
                repeat: false
                onTriggered: editExcludePatternsDialog.refreshImpactPreview()
            }

            Label {
                visible: editExcludePatternsDialog.impactedPaths.length > 0
                text: {
                    var paths = editExcludePatternsDialog.impactedPaths
                    var shown = paths.slice(0, 5).join(", ")
                    var extra = paths.length > 5 ? qsTr(" (+%1 autre(s))").arg(paths.length - 5) : ""
                    return qsTr("⚠ %1 fichier(s) déjà partagé(s) seront retirés à l'enregistrement : %2%3")
                        .arg(paths.length).arg(shown).arg(extra)
                }
                color: Theme.warning
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Label {
                text: qsTr("Les fichiers déjà indexés qui correspondent à un nouveau motif seront retirés lors de la prochaine réindexation (immédiate à la validation).")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingSmall

                AppButton {
                    text: qsTr("Annuler")
                    variant: "secondary"
                    Layout.fillWidth: true
                    onClicked: editExcludePatternsDialog.close()
                }
                AppButton {
                    text: qsTr("Enregistrer")
                    variant: "primary"
                    Layout.fillWidth: true
                    onClicked: {
                        if (root.context && editExcludePatternsDialog.targetFolderId >= 0) {
                            if (root.context.updateExcludePatterns(editExcludePatternsDialog.targetFolderId,
                                                                    editExcludePatternsDialog.patternsText)) {
                                editExcludePatternsDialog.close()
                                root.refreshFiles()
                                root.refreshHistory()
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- dialogue de définition du chemin local pour dossiers distants ----
    AppDialog {
        id: setLocalPathDialog
        title: qsTr("Définir le dossier local — %1").arg(setLocalPathDialog.targetFolderName)
        headerIcon: "\uf07c"
        dialogWidth: 420
        // Hauteur calculee sur le contenu reel (cf. createDialog plus haut) :
        // une valeur fixe (280 auparavant) ne tenait pas compte du texte
        // d'intro sur plusieurs lignes ni de la zone de depot vide (116px),
        // ce qui poussait les boutons Annuler/Definir hors de la carte.
        dialogHeight: setLocalPathColumn.implicitHeight + Theme.spacingMedium * 2
        standardButtons: Dialog.NoButton

        property int targetFolderId: -1
        property string targetFolderName: ""
        property string targetFolderUuid: ""
        property string localPath: ""

        onOpened: {
            setLocalPathDialog.localPath = ""
        }

        ColumnLayout {
            id: setLocalPathColumn
            width: parent.width
            spacing: Theme.spacingMedium

            Label {
                text: qsTr("Ce dossier partagé provient d'un autre poste.\nChoisissez le dossier local où les fichiers seront téléchargés.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Label {
                text: qsTr("Dossier local")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
            FolderDropzone {
                path: setLocalPathDialog.localPath
                emptyHint: qsTr("Cliquez ou glissez le dossier de destination ici")
                onBrowseRequested: remoteFolderPickerDialog.open()
                onPathDropped: function (droppedPath) { setLocalPathDialog.localPath = droppedPath }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingSmall

                AppButton {
                    text: qsTr("Annuler")
                    variant: "secondary"
                    Layout.fillWidth: true
                    onClicked: setLocalPathDialog.close()
                }
                AppButton {
                    text: qsTr("Définir")
                    variant: "primary"
                    Layout.fillWidth: true
                    enabled: setLocalPathDialog.localPath.length > 0
                    onClicked: {
                        if (root.context && setLocalPathDialog.targetFolderId >= 0) {
                            if (root.context.setFolderLocalPath(setLocalPathDialog.targetFolderId, setLocalPathDialog.localPath)) {
                                setLocalPathDialog.close()
                                root.openFolder(setLocalPathDialog.targetFolderId, setLocalPathDialog.targetFolderName, false, setLocalPathDialog.targetFolderUuid)
                            }
                        }
                    }
                }
            }
        }
    }

    FolderDialog {
        id: remoteFolderPickerDialog
        title: qsTr("Choisir le dossier local")
        currentFolder: (typeof settingsModel !== "undefined" && settingsModel) ? settingsModel.defaultSharedFolderPath : ""
        onAccepted: {
            let path = decodeURIComponent(selectedFolder.toString())
            path = path.replace(/^file:\/\//, "")
            if (/^\/[A-Za-z]:/.test(path)) {
                path = path.substring(1)
            }
            setLocalPathDialog.localPath = path
        }
    }

    // ---- dialogue de confirmation d'un nouveau partage reçu ----
    //
    // Affiché quand core::SharedFolderContext émet
    // folderShareConfirmationRequested() : un pair vient de nous partager un
    // dossier pour la première fois. On demande explicitement l'accord de
    // l'utilisateur avant de commencer quoi que ce soit sur son disque
    // (au lieu d'auto-provisionner silencieusement), tout en lui montrant OÙ
    // le contenu serait placé s'il accepte.
    AppDialog {
        id: shareConfirmDialog
        title: qsTr("Nouveau dossier partagé — %1").arg(shareConfirmDialog.targetFolderName)
        headerIcon: "\uf07b"
        dialogWidth: 440
        // Hauteur calculee sur le contenu reel (au lieu d'une hauteur fixe
        // de 300px) : avec une hauteur fixe et un Item{Layout.fillHeight}
        // pour pousser les boutons en bas, un message court laissait un
        // grand espace vide entre le texte et les boutons Refuser/Accepter.
        dialogHeight: shareConfirmColumn.implicitHeight + Theme.spacingMedium * 2
        standardButtons: Dialog.NoButton
        closePolicy: Popup.NoAutoClose
        showCloseButton: false
        busyText: qsTr("Préparation de la synchronisation…")

        onClosed: {
            busy = false
            root.showNextShareConfirmation()
        }

        property int targetFolderId: -1
        property string targetFolderName: ""
        property string ownerName: ""
        property string suggestedPath: ""
        property bool allowWrite: false

        ColumnLayout {
            id: shareConfirmColumn
            width: parent.width
            spacing: Theme.spacingMedium

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Label {
                    Layout.fillWidth: true
                    text: shareConfirmDialog.ownerName.length > 0
                        ? qsTr("« %1 » vient de partager le dossier « %2 » avec vous.")
                            .arg(shareConfirmDialog.ownerName).arg(shareConfirmDialog.targetFolderName)
                        : qsTr("Un dossier partagé « %1 » a été reçu.").arg(shareConfirmDialog.targetFolderName)
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeBody
                    wrapMode: Text.WordWrap
                }

                // Badge de permission : direction visuelle validee sur la
                // maquette. Reflete l'acces reellement accorde par le
                // proprietaire (lecture seule si allowWrite est faux).
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    radius: Theme.radiusPill
                    color: shareConfirmDialog.allowWrite ? Theme.successMuted : Theme.surfaceAlt
                    border.width: 1
                    border.color: shareConfirmDialog.allowWrite ? Theme.success : Theme.border
                    height: 24
                    width: permissionBadgeRow.implicitWidth + Theme.spacingMedium

                    RowLayout {
                        id: permissionBadgeRow
                        anchors.centerIn: parent
                        spacing: 4

                        FaIcon {
                            glyph: shareConfirmDialog.allowWrite ? "\uf044" : "\uf06e"
                            font.pixelSize: 10
                            color: shareConfirmDialog.allowWrite ? Theme.success : Theme.textSecondary
                        }
                        Label {
                            text: shareConfirmDialog.allowWrite ? qsTr("Lecture/écriture") : qsTr("Lecture seule")
                            color: shareConfirmDialog.allowWrite ? Theme.success : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeCaption
                            font.bold: true
                        }
                    }
                }
            }

            Label {
                text: qsTr("Si vous acceptez, son contenu sera synchronisé dans :")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Label {
                text: shareConfirmDialog.suggestedPath
                color: Theme.text
                font.pixelSize: Theme.fontSizeSmall
                font.family: "monospace"
                elide: Text.ElideMiddle
                wrapMode: Text.WrapAnywhere
                Layout.fillWidth: true
            }

            Label {
                text: qsTr("Vous pourrez changer cet emplacement plus tard, ou refuser pour l'instant sans perdre l'accès au dossier.")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingSmall

                AppButton {
                    text: qsTr("Refuser")
                    variant: "secondary"
                    Layout.fillWidth: true
                    onClicked: {
                        if (root.context && shareConfirmDialog.targetFolderId >= 0) {
                            root.context.declineFolderShare(shareConfirmDialog.targetFolderId)
                        }
                        shareConfirmDialog.close()
                    }
                }
                AppButton {
                    text: qsTr("Accepter")
                    variant: "primary"
                    Layout.fillWidth: true
                    onClicked: {
                        shareConfirmDialog.busy = true
                        if (root.context && shareConfirmDialog.targetFolderId >= 0) {
                            root.context.acceptFolderShare(shareConfirmDialog.targetFolderId)
                        }
                        shareConfirmDialog.close()
                    }
                }
            }
        }
    }

    // ---- dialogue de gestion des accès (voir / révoquer / ajouter) ----
    AppDialog {
        id: manageAccessDialog
        title: qsTr("Gérer les accès — %1").arg(manageAccessDialog.targetFolderName)
        headerIcon: "\uf0c0"
        dialogWidth: 460
        // Hauteur calculee sur le contenu reel (meme pattern que
        // AdminView.qml / editExcludePatternsDialog), plafonnee a 560
        // pour garder un filet de securite si la liste d'acces est
        // longue (le ScrollView de la liste prend le relais du scroll
        // au-dela de sa propre limite, cf. plus bas).
        dialogHeight: Math.min(manageAccessMainColumn.implicitHeight + Theme.spacingMedium * 2, 560)
        standardButtons: Dialog.NoButton

        property int    targetFolderId: -1
        property string targetFolderName: ""
        property var    grants: []          // QVariantList {userId, username, permission}

        // ---- état révocation en attente ----
        property int    pendingRevokeUserId: -1
        property string pendingRevokeUsername: ""

        onOpened: manageAccessDialog.reload()

        function reload() {
            manageAccessDialog.pendingRevokeUserId = -1
            if (root.context && manageAccessDialog.targetFolderId >= 0) {
                manageAccessDialog.grants = root.context.accessForFolder(manageAccessDialog.targetFolderId)
            } else {
                manageAccessDialog.grants = []
            }
            addUserCombo.reloadCandidates()
        }

        ColumnLayout {
            id: manageAccessMainColumn
            width: parent.width
            spacing: Theme.spacingMedium

            // ── Section « utilisateurs actuels » ──────────────────────────
            Label {
                text: qsTr("Accès accordés")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            // Bandeau de confirmation de révocation (inline, sans popup)
            Rectangle {
                id: revokeConfirmBanner
                Layout.fillWidth: true
                height: 52
                radius: Theme.radiusMedium
                color: Theme.errorMuted
                border.color: Theme.error
                border.width: 1
                visible: manageAccessDialog.pendingRevokeUserId >= 0

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingSmall
                    anchors.rightMargin: Theme.spacingSmall
                    spacing: Theme.spacingSmall

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Révoquer l'accès de « %1 » ?").arg(manageAccessDialog.pendingRevokeUsername)
                        color: Theme.error
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                    }
                    AppButton {
                        text: qsTr("Annuler")
                        variant: "ghost"
                        onClicked: manageAccessDialog.pendingRevokeUserId = -1
                    }
                    AppButton {
                        text: qsTr("Confirmer")
                        variant: "danger"
                        onClicked: {
                            if (root.context) {
                                root.context.revokeAccess(manageAccessDialog.targetFolderId,
                                                          manageAccessDialog.pendingRevokeUserId)
                                manageAccessDialog.reload()
                            }
                        }
                    }
                }
            }

            ScrollView {
                Layout.fillWidth: true
                // La liste epouse son contenu reel (nombre d'acces
                // accordes) au lieu d'une hauteur fixe de 180px qui
                // laissait un grand vide des qu'il y avait peu
                // d'utilisateurs. Plafonnee a 180 : au-dela, ca defile.
                Layout.preferredHeight: Math.min(Math.max(grantsListView.contentHeight, 56), 180)
                clip: true

                ListView {
                    id: grantsListView
                    anchors.fill: parent
                    spacing: 4
                    model: manageAccessDialog.grants

                    delegate: Rectangle {
                        width: grantsListView.width
                        height: 48
                        radius: Theme.radiusSmall
                        color: Theme.surfaceAlt
                        border.width: 1
                        border.color: Theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.rightMargin: Theme.spacingSmall
                            spacing: Theme.spacingSmall

                            // Nom seul : la permission est portee par la
                            // bascule segmentee a droite (direction visuelle
                            // validee sur la maquette, remplace le bouton
                            // "→ Lecture/Écriture" et le sous-libelle).
                            Label {
                                Layout.fillWidth: true
                                text: modelData.username
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }

                            // Bascule segmentee Lecture / Écriture
                            AppSegmentedControl {
                                Layout.preferredWidth: 190
                                model: [
                                    { label: qsTr("Lecture"), glyph: "\uf06e" },
                                    { label: qsTr("Écriture"), glyph: "\uf044" }
                                ]
                                currentIndex: modelData.permission === "Write" ? 1 : 0
                                onActivated: function(index) {
                                    if (root.context) {
                                        root.context.changePermission(
                                            manageAccessDialog.targetFolderId,
                                            modelData.userId,
                                            index === 1)
                                        manageAccessDialog.reload()
                                    }
                                }
                            }

                            // Bouton révoquer (avec confirmation inline)
                            AppButton {
                                text: qsTr("Révoquer")
                                variant: "danger"
                                onClicked: {
                                    manageAccessDialog.pendingRevokeUserId   = modelData.userId
                                    manageAccessDialog.pendingRevokeUsername = modelData.username
                                }
                            }
                        }
                    }

                    Label {
                        visible: grantsListView.count === 0
                        anchors.centerIn: parent
                        text: qsTr("Ce dossier n'est partagé avec aucun autre utilisateur.")
                        color: Theme.textTertiary
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        width: parent.width - Theme.spacingLarge
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // ── Séparateur ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
            }

            // ── Section « ajouter un utilisateur » ────────────────────────
            Label {
                text: qsTr("Ajouter un utilisateur")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            RowLayout {
                id: addUserCombo
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                // Liste des candidats = tous les utilisateurs pas encore dans grants
                property var candidates: []
                property int selectedUserId: -1
                property string selectedUsername: ""

                function reloadCandidates() {
                    if (!root.context) { candidates = []; return }
                    const all = root.context.availableUsers()
                    const grantedIds = {}
                    for (let i = 0; i < manageAccessDialog.grants.length; ++i) {
                        grantedIds[manageAccessDialog.grants[i].userId] = true
                    }
                    const filtered = []
                    for (let j = 0; j < all.length; ++j) {
                        if (!grantedIds[all[j].userId]) filtered.push(all[j])
                    }
                    candidates = filtered
                    candidateModel.clear()
                    for (let k = 0; k < filtered.length; ++k) {
                        candidateModel.append(filtered[k])
                    }
                    addUserComboBox.currentIndex = -1
                    addUserCombo.selectedUserId  = -1
                    addUserCombo.selectedUsername = ""
                }

                AppComboBox {
                    id: addUserComboBox
                    Layout.fillWidth: true
                    model: ListModel { id: candidateModel }
                    textRole: "username"
                    currentIndex: -1
                    displayText: currentIndex < 0 ? qsTr("Choisir un utilisateur…") : currentText

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < candidateModel.count) {
                            addUserCombo.selectedUserId  = candidateModel.get(currentIndex).userId
                            addUserCombo.selectedUsername = candidateModel.get(currentIndex).username
                        } else {
                            addUserCombo.selectedUserId  = -1
                            addUserCombo.selectedUsername = ""
                        }
                    }

                    Label {
                        visible: candidateModel.count === 0
                        anchors.centerIn: parent
                        text: qsTr("Tous les utilisateurs ont déjà accès")
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                AppCheckBox {
                    id: addWriteCheckBox
                    text: qsTr("Écriture")
                    checked: true
                }

                AppButton {
                    text: qsTr("Ajouter")
                    variant: "primary"
                    enabled: addUserCombo.selectedUserId >= 0
                    onClicked: {
                        if (root.context && addUserCombo.selectedUserId >= 0) {
                            root.context.grantAccess(
                                manageAccessDialog.targetFolderId,
                                addUserCombo.selectedUserId,
                                addWriteCheckBox.checked)
                            manageAccessDialog.reload()
                        }
                    }
                }
            }
        }
    }

    // ---- dialogue de confirmation de suppression ----
    AppDialog {
        id: removeConfirmDialog
        title: qsTr("Supprimer ce dossier partagé ?")
        headerIcon: "\uf1f8"
        dialogWidth: 380
        standardButtons: Dialog.NoButton

        property int targetFolderId: -1
        property string targetFolderName: ""

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingMedium

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    Layout.alignment: Qt.AlignTop
                    radius: Theme.radiusMedium
                    color: Theme.errorMuted

                    FaIcon {
                        anchors.centerIn: parent
                        glyph: "\uf071"
                        font.pixelSize: 15
                        color: Theme.error
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("« %1 » ne sera plus partagé. Les fichiers restent intacts sur le disque : seul l'enregistrement dans LocaLink est supprimé.").arg(removeConfirmDialog.targetFolderName)
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall
                Item { Layout.fillWidth: true }
                AppButton {
                    text: qsTr("Annuler")
                    variant: "ghost"
                    onClicked: removeConfirmDialog.close()
                }
                AppButton {
                    text: qsTr("Supprimer")
                    variant: "danger"
                    onClicked: {
                        if (root.context && removeConfirmDialog.targetFolderId >= 0) {
                            if (root.openedFolderId === removeConfirmDialog.targetFolderId) {
                                root.openedFolderId = -1
                            }
                            root.context.removeFolder(removeConfirmDialog.targetFolderId)
                        }
                        removeConfirmDialog.close()
                    }
                }
            }
        }
    }

    // ---- layout principal ----
    // Redesign aligne sur FileTransferView : barre d'adresse personnalisee
    // (pilule fil d'Ariane, recherche, bascule grille/liste) + rangee de
    // filtres rapides en chips a la place de l'ancien panneau lateral
    // ExplorerSidebar (desormais supprime de cet ecran), tuiles "carte"
    // avec avatar colore, badges de statut communs (StatusBadge) et barre
    // d'etat inferieure fine, comme un explorateur natif.
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // =========================================================
        // Barre d'adresse personnalisée (custom, meme principe que
        // FileTransferView) : navigation + fil d'Ariane pilule +
        // recherche + bascule grille/liste + actions propres a l'ecran.
        // =========================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: Theme.addressBarBackground

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.border
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                IconButton {
                    glyph: "\uf060"
                    variant: "ghost"
                    size: 30
                    onClicked: {
                        if (root.openedFolderId >= 0) {
                            if (root.browsedRelativePath.length > 0) {
                                root.goUpInBrowser()
                            } else {
                                root.openedFolderId = -1
                            }
                        } else {
                            root.backRequested()
                        }
                    }
                }

                IconButton {
                    glyph: "\uf021"
                    variant: "ghost"
                    size: 30
                    onClicked: {
                        if (root.openedFolderId >= 0) {
                            root.refreshFiles()
                            root.refreshHistory()
                        } else if (root.context) {
                            root.context.refresh()
                        }
                    }
                }

                // Fil d'Ariane en pilule
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: Theme.radiusSmall
                    color: Theme.breadcrumbChipHover
                    border.width: 1
                    border.color: Theme.border

                    RowLayout {
                        id: breadcrumbRow
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        // Pas de anchors.right : le row ne s'etire pas sur
                        // toute la largeur de la pilule, il ne prend que la
                        // place necessaire a son contenu.
                        spacing: 6

                        Label {
                            text: qsTr("Dossiers partagés")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: root.openedFolderId >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                enabled: root.openedFolderId >= 0
                                onClicked: root.openedFolderId = -1
                            }
                        }

                        Label {
                            visible: root.openedFolderId >= 0
                            text: "/"
                            font.pixelSize: Theme.fontSizeCaption
                            font.family: Theme.fontFamily
                            color: Theme.textTertiary
                        }

                        Label {
                            visible: root.openedFolderId >= 0
                            text: root.openedFolderName
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            font.family: Theme.fontFamily
                            color: root.browsedRelativePath.length > 0 ? Theme.textSecondary : Theme.text
                            elide: Text.ElideRight
                            Layout.maximumWidth: 180

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: root.browsedRelativePath.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                enabled: root.browsedRelativePath.length > 0
                                onClicked: root.openBrowserFolder("")
                            }
                        }

                        // CORRECTIF PERF : retour visuel pendant l'indexation
                        // asynchrone (cf. SyncEngine::reindexFolderAsync()) --
                        // avant, le clic "Réindexer"/le partage semblait figer
                        // l'appli sur un poste peu performant ; maintenant
                        // l'indexation tourne en arrière-plan et ce petit
                        // indicateur montre qu'elle est en cours, sans bloquer
                        // le reste de l'écran.
                        RowLayout {
                            visible: root.openedFolderId >= 0 && root.indexingFolderIds.indexOf(root.openedFolderId) !== -1
                            spacing: 6

                            BusyIndicator {
                                implicitWidth: 14
                                implicitHeight: 14
                                running: parent.visible
                            }

                            Label {
                                text: qsTr("Indexation…")
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                color: Theme.textTertiary
                            }
                        }

                        Repeater {
                            model: root.openedFolderId >= 0 && root.browsedRelativePath.length > 0
                                   ? root.browsedRelativePath.split("/") : []

                            delegate: RowLayout {
                                spacing: 6
                                Layout.minimumWidth: 0

                                Label {
                                    text: "/"
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.family: Theme.fontFamily
                                    color: Theme.textTertiary
                                }

                                Label {
                                    text: modelData
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    font.family: Theme.fontFamily
                                    color: index === root.browsedRelativePath.split("/").length - 1
                                           ? Theme.text : Theme.textSecondary
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 180
                                    Layout.minimumWidth: 0

                                    ToolTip.visible: truncated && breadcrumbSegmentArea.containsMouse
                                    ToolTip.text: root.browserPathAt(index)
                                    ToolTip.delay: 500

                                    MouseArea {
                                        id: breadcrumbSegmentArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openBrowserFolder(root.browserPathAt(index))
                                    }
                                }
                            }
                        }
                    }
                }

                // Champ de recherche
                Item {
                    visible: !root.showHistory
                    Layout.preferredWidth: 190
                    Layout.preferredHeight: 32

                    AppSearchField {
                        id: addressSearchField
                        compact: true
                        anchors.fill: parent
                        placeholderText: qsTr("Rechercher...")
                        text: root.searchText
                        rightInset: clearIcon.visible ? 18 : 0
                        onTextChanged: root.searchText = text
                    }

                    FaIcon {
                        id: clearIcon
                        visible: root.searchText.length > 0
                        glyph: "\uf00d"
                        font.pixelSize: 11
                        color: Theme.textTertiary
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: addressSearchField.text = ""
                        }
                    }
                }

                Rectangle {
                    visible: !root.showHistory
                    width: 1
                    height: 18
                    color: Theme.border
                }

                // Bascule grille/liste
                RowLayout {
                    visible: !root.showHistory
                    spacing: 0

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: Theme.radiusSmall
                        color: root.viewMode === "grid" ? Theme.primaryMuted
                               : (gridToggleArea.containsMouse ? Theme.surfaceHover : "transparent")
                        Behavior on color { ColorAnimation { duration: 100 } }

                        FaIcon {
                            anchors.centerIn: parent
                            glyph: "\uf009"
                            font.pixelSize: 15
                            color: root.viewMode === "grid" ? Theme.primary : Theme.textTertiary
                        }

                        MouseArea {
                            id: gridToggleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewMode = "grid"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: Theme.radiusSmall
                        color: root.viewMode === "list" ? Theme.primaryMuted
                               : (listToggleArea.containsMouse ? Theme.surfaceHover : "transparent")
                        Behavior on color { ColorAnimation { duration: 100 } }

                        FaIcon {
                            anchors.centerIn: parent
                            glyph: "\uf0ca"
                            font.pixelSize: 15
                            color: root.viewMode === "list" ? Theme.primary : Theme.textTertiary
                        }

                        MouseArea {
                            id: listToggleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewMode = "list"
                        }
                    }
                }

                Rectangle {
                    visible: root.openedFolderId >= 0
                    width: 1
                    height: 18
                    color: Theme.border
                }

                // APRÈS
                IconButton {
                    id: moreActionsBtn
                    visible: root.openedFolderId >= 0
                    glyph: "\uf142"   // ellipsis-v (Font Awesome) — menu "plus d'actions"
                    variant: "ghost"
                    size: 30
                    onClicked: moreActionsMenu.open()

                    Menu {
                        id: moreActionsMenu
                        y: parent.height + 2
                        width: 230
                        palette.window: Theme.surface
                        palette.base: Theme.surface
                        palette.text: Theme.text
                        palette.highlight: Theme.primaryMuted
                        palette.highlightedText: Theme.text
                        padding: Theme.spacingXs

                        background: Rectangle {
                            radius: Theme.radiusMedium
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border
                        }

                        MenuItem {
                            width: parent.width - 2 * Theme.spacingXs
                            height: 40
                            contentItem: Label {
                                text: parent.text
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: Theme.spacingSmall
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: parent.highlighted ? Theme.primaryMuted : "transparent"
                            }
                            text: root.showHistory ? qsTr("Fichiers") : qsTr("Historique")
                            onTriggered: root.showHistory = !root.showHistory
                        }
                        MenuItem {
                            width: parent.width - 2 * Theme.spacingXs
                            height: 40
                            enabled: root.openedFolderIsLocalOrigin
                            contentItem: Label {
                                text: parent.text
                                color: parent.enabled ? Theme.text : Theme.textTertiary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: Theme.spacingSmall
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: parent.highlighted ? Theme.primaryMuted : "transparent"
                            }
                            text: qsTr("Réindexer")
                            onTriggered: {
                                if (root.context) {
                                    root.context.shareFolder(root.openedFolderId)
                                    root.refreshFiles()
                                    root.refreshHistory()
                                }
                            }
                        }
                        MenuItem {
                            width: parent.width - 2 * Theme.spacingXs
                            height: 40
                            enabled: true
                            contentItem: Label {
                                text: parent.text
                                color: parent.enabled ? Theme.text : Theme.textTertiary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: Theme.spacingSmall
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: parent.highlighted ? Theme.primaryMuted : "transparent"
                            }
                            // CORRECTIF : l'écran "Dossiers partagés" n'offrait
                            // jusqu'ici aucun moyen d'accéder au contenu réel
                            // sur le disque (contrairement à FileTransferView,
                            // qui a "Ouvrir l'emplacement" sur chaque fichier
                            // transféré, cf. TransferContext::openFileLocation()).
                            text: qsTr("Ouvrir dans l'explorateur")
                            onTriggered: {
                                if (root.context && !root.context.openFolderLocation(root.openedFolderId)) {
                                    errorBanner.show(qsTr("Impossible d'ouvrir l'emplacement du dossier."))
                                }
                            }
                        }
                        MenuSeparator {
                            // CORRECTIF (espace vide conservé pour un dossier
                            // "Reçu") : ce séparateur n'a de sens que devant
                            // "Exclusions…"/"Gérer les accès…", masqués juste
                            // en dessous pour un dossier distant. `visible`
                            // seul ne suffit pas ici : dans le ListView/Column
                            // interne de Menu, un delegate invisible garde sa
                            // hauteur de mise en page (seul le rendu est
                            // masqué) -- d'où le "trou" observé. On force donc
                            // aussi height à 0 quand il est masqué, comme pour
                            // les deux MenuItem ci-dessous.
                            visible: root.openedFolderIsLocalOrigin
                            height: visible ? implicitHeight : 0
                            contentItem: Rectangle {
                                implicitHeight: 1
                                color: Theme.border
                            }
                        }
                        MenuItem {
                            width: parent.width - 2 * Theme.spacingXs
                            visible: root.openedFolderIsLocalOrigin
                            height: visible ? 40 : 0
                            contentItem: Label {
                                text: parent.text
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: Theme.spacingSmall
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: parent.highlighted ? Theme.primaryMuted : "transparent"
                            }
                            text: qsTr("Exclusions…")
                            onTriggered: {
                                editExcludePatternsDialog.targetFolderId = root.openedFolderId
                                editExcludePatternsDialog.targetFolderName = root.openedFolderName
                                editExcludePatternsDialog.open()
                            }
                        }
                        MenuItem {
                            width: parent.width - 2 * Theme.spacingXs
                            visible: root.openedFolderIsLocalOrigin
                            height: visible ? 40 : 0
                            contentItem: Label {
                                text: parent.text
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: Theme.spacingSmall
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: parent.highlighted ? Theme.primaryMuted : "transparent"
                            }
                            text: qsTr("Gérer les accès…")
                            onTriggered: {
                                manageAccessDialog.targetFolderId = root.openedFolderId
                                manageAccessDialog.targetFolderName = root.openedFolderName
                                manageAccessDialog.open()
                            }
                        }
                    }
                }

                AppButton {
                    visible: root.openedFolderId < 0
                    text: qsTr("+ Nouveau dossier")
                    variant: "primary"
                    onClicked: createDialog.open()
                }
            }
        }

        // =========================================================
        // Rangée de filtres rapides (Tout, Mes dossiers, Reçus) — remplace
        // l'ancien panneau lateral ExplorerSidebar (supprime de cet ecran).
        // Visible uniquement a la racine (liste des dossiers partages).
        // =========================================================
        RowLayout {
            visible: root.openedFolderId < 0
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingMedium
            Layout.rightMargin: Theme.spacingMedium
            Layout.topMargin: Theme.spacingSmall
            spacing: 6

            Repeater {
                model: [
                    { key: "all",      label: qsTr("Tout") },
                    { key: "mine",     label: qsTr("Mes dossiers") },
                    { key: "received", label: qsTr("Reçus") }
                ]

                delegate: Rectangle {
                    height: 24
                    width: filterChipRow.implicitWidth + 20
                    radius: Theme.radiusSmall
                    color: root.activeFilter === modelData.key ? Theme.primaryMuted : Theme.surfaceAlt
                    border.width: 1
                    border.color: root.activeFilter === modelData.key ? Theme.primary : Theme.border
                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        id: filterChipRow
                        anchors.centerIn: parent
                        spacing: 5

                        FaIcon {
                            glyph: root.filterIconGlyph(modelData.key)
                            font.pixelSize: 9
                            color: root.activeFilter === modelData.key ? Theme.primary : root.filterIconColor(modelData.key)
                        }
                        Label {
                            text: modelData.label
                            color: root.activeFilter === modelData.key ? Theme.primary : Theme.textSecondary
                            font.pixelSize: Theme.fontSizeCaption
                            font.weight: root.activeFilter === modelData.key ? Font.Medium : Font.Normal
                            font.family: Theme.fontFamily
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeFilter = modelData.key
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                visible: root.hasActiveFilters()
                text: qsTr("Réinitialiser")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeCaption
                font.family: Theme.fontFamily

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.activeFilter = "all"
                        root.searchText = ""
                    }
                }
            }
        }

        // =========================================================
        // Zone de contenu principal
        // =========================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // État vide (aucun dossier partagé du tout)
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.openedFolderId < 0 && gridView.count === 0
                spacing: Theme.spacingSmall

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    Layout.bottomMargin: Theme.spacingSmall
                    radius: 18
                    color: Theme.primaryMuted
                    FaIcon {
                        anchors.centerIn: parent
                        glyph: "\uf07b"
                        font.pixelSize: 26
                        color: Theme.primary
                    }
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Aucun dossier partagé")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeBody
                    font.weight: Font.Medium
                    font.family: Theme.fontFamily
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Cliquez sur « + Nouveau dossier » pour commencer.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                }
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacingMedium
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: emptyCtaRow.implicitWidth + 26
                    radius: Theme.radiusSmall
                    color: emptyCtaArea.pressed ? Theme.primaryHover : Theme.primary

                    RowLayout {
                        id: emptyCtaRow
                        anchors.centerIn: parent
                        spacing: 6
                        FaIcon { glyph: "\uf07b"; font.pixelSize: 12; color: Theme.primaryText }
                        Label {
                            text: qsTr("Nouveau dossier")
                            color: Theme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            font.family: Theme.fontFamily
                        }
                    }
                    MouseArea {
                        id: emptyCtaArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: createDialog.open()
                    }
                }
            }

            // =====================================================
            // VUE RACINE : grille/liste des dossiers partagés (tuiles
            // "carte" avec avatar colore, meme principe que les tuiles
            // correspondants de FileTransferView).
            // =====================================================
            ColumnLayout {
                anchors.fill: parent
                visible: root.openedFolderId < 0 && gridView.count > 0
                spacing: 0

                Item { Layout.preferredHeight: 16 }

                Label {
                    Layout.leftMargin: 16
                    Layout.bottomMargin: 10
                    text: qsTr("DOSSIERS PARTAGÉS")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeCaption
                    font.weight: Font.Medium
                    font.family: Theme.fontFamily
                    font.letterSpacing: 0.4
                }

                GridView {
                    id: gridView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    visible: root.viewMode === "grid"
                    readonly property int columns: Math.max(2, Math.floor(width / 160))
                    cellWidth: Math.floor(width / columns)
                    cellHeight: 132
                    model: root.context ? root.context.folderFilterProxy : null
                    clip: true

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }

                    delegate: Item {
                        id: folderTile
                        width: gridView.cellWidth
                        height: gridView.cellHeight
                        clip: true

                        // readonly property color accentColor: Theme.colorForName(model.name)
                        readonly property color accentColor: "#FFC83D"   // jaune dossier façon Windows
                        readonly property bool hovered: tileArea.containsMouse

                        // ---- Fond de la tuile (survol / selection), meme
                        // principe que FolderTile.tileBg. ----
                        Rectangle {
                            id: tileBg
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: Theme.radiusMedium
                            color: folderTile.hovered ? Theme.surfaceHover : "transparent"
                            border.width: folderTile.hovered ? 1 : 0
                            border.color: Theme.selectionBorder
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSmall
                            spacing: 4

                            // ---- Icone de dossier, style FolderTile ----
                            Item {
                                id: iconArea
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 52
                                Layout.topMargin: 6

                                // Elevation discrete au survol.
                                Rectangle {
                                    anchors.fill: folderShape
                                    anchors.topMargin: 3
                                    radius: folderShape.radius
                                    color: Theme.shadow
                                    opacity: folderTile.hovered ? 0.55 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }

                                // Corps du dossier (forme "plate" a onglet).
                                Item {
                                    id: folderShape
                                    anchors.fill: parent
                                    property real radius: 6
                                    scale: folderTile.hovered ? 1.04 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                    // Onglet arriere-plan.
                                    Rectangle {
                                        x: 2
                                        y: 4
                                        width: parent.width * 0.42
                                        height: 11
                                        radius: 3
                                        color: folderTile.accentColor
                                        opacity: 0.75
                                    }

                                    // Corps principal du dossier.
                                    Rectangle {
                                        y: 11
                                        width: parent.width
                                        height: parent.height - 11
                                        radius: folderShape.radius
                                        color: folderTile.accentColor

                                        // Degrade "vitre" subtil.
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                                                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                                            }
                                        }

                                        // Ligne de pli du rabat avant.
                                        Rectangle {
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: parent.height * 0.38
                                            radius: folderShape.radius
                                            color: Qt.rgba(1, 1, 1, 0.10)
                                        }
                                    }
                                }

                                // Avatar/accent : initiale du dossier, ancre
                                // en bas a droite du dossier (comme un badge
                                // "proprietaire" pose sur la pochette).
                                // Rectangle {
                                //     width: 24
                                //     height: 24
                                //     radius: 12
                                //     color: Theme.surface
                                //     border.width: 2
                                //     border.color: Theme.surface
                                //     anchors.right: folderShape.right
                                //     anchors.bottom: folderShape.bottom
                                //     anchors.rightMargin: -6
                                //     anchors.bottomMargin: -6

                                //     Rectangle {
                                //         anchors.fill: parent
                                //         anchors.margins: 2
                                //         radius: width / 2
                                //         color: Qt.rgba(folderTile.accentColor.r,
                                //                         folderTile.accentColor.g,
                                //                         folderTile.accentColor.b, 0.20)
                                //         Text {
                                //             anchors.centerIn: parent
                                //             text: model.name.length > 0 ? model.name.charAt(0).toUpperCase() : "?"
                                //             color: folderTile.accentColor
                                //             font.pixelSize: 10
                                //             font.bold: true
                                //             font.family: Theme.fontFamily
                                //         }
                                //     }
                                // }

                                // Pastille conflit (coin superieur gauche).
                                Rectangle {
                                    visible: model.hasConflict
                                    width: 20
                                    height: 20
                                    radius: 10
                                    color: Theme.warning
                                    border.width: 2
                                    border.color: Theme.surface
                                    anchors.left: folderShape.left
                                    anchors.top: folderShape.top
                                    anchors.leftMargin: -7
                                    anchors.topMargin: -4

                                    FaIcon {
                                        anchors.centerIn: parent
                                        glyph: "\uf071"
                                        font.pixelSize: 9
                                        color: "#FFFFFF"
                                    }
                                }

                                // Pastille de comptage (coin superieur droit).
                                Rectangle {
                                    visible: model.fileCount > 0
                                    width: Math.max(20, countLabel.implicitWidth + 10)
                                    height: 20
                                    radius: 10
                                    color: Theme.primary
                                    border.width: 2
                                    border.color: Theme.surface
                                    anchors.right: folderShape.right
                                    anchors.top: folderShape.top
                                    anchors.rightMargin: -8
                                    anchors.topMargin: -4

                                    Text {
                                        id: countLabel
                                        anchors.centerIn: parent
                                        text: model.fileCount > 99 ? "99+" : model.fileCount
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                        color: Theme.primaryText
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: model.name
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 1

                                ToolTip.visible: truncated && folderTile.hovered
                                ToolTip.text: model.name
                                ToolTip.delay: 500
                            }
                        }

                        MouseArea {
                            id: tileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    removeConfirmDialog.targetFolderId = model.folderId
                                    removeConfirmDialog.targetFolderName = model.name
                                    removeConfirmDialog.open()
                                    return
                                }
                                if (!model.isLocalOrigin) {
                                    if (model.localPath && model.localPath.length > 0) {
                                        root.openFolder(model.folderId, model.name, false, model.uuid)
                                    } else {
                                        setLocalPathDialog.targetFolderId = model.folderId
                                        setLocalPathDialog.targetFolderName = model.name
                                        setLocalPathDialog.targetFolderUuid = model.uuid
                                        setLocalPathDialog.open()
                                    }
                                } else {
                                    root.openFolder(model.folderId, model.name, true, model.uuid)
                                }
                            }
                        }
                    }
                }

                // Vue "liste" des dossiers partagés
                ListView {
                    id: foldersListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    visible: root.viewMode === "list"
                    spacing: 2
                    clip: true
                    model: root.context ? root.context.folderFilterProxy : null

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }

                    delegate: Rectangle {
                        id: folderRow
                        width: foldersListView.width
                        height: 56
                        radius: Theme.radiusSmall
                        color: folderRowArea.containsMouse ? Theme.surfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        readonly property color accentColor: "#FFC83D"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 8
                                color: Qt.rgba(folderRow.accentColor.r,
                                                folderRow.accentColor.g,
                                                folderRow.accentColor.b, 0.16)

                                FaIcon {
                                    anchors.centerIn: parent
                                    glyph: "\uf114"
                                    font.pixelSize: 15
                                    color: folderRow.accentColor
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Label {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: model.name
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                }

                                Label {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: model.isLocalOrigin ? qsTr("Dossier local") : qsTr("Dossier reçu")
                                    color: Theme.textTertiary
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                }
                            }

                            StatusBadge {
                                tone: model.hasConflict ? "warning" : (model.isLocalOrigin ? "info" : "success")
                                text: model.hasConflict ? qsTr("Conflit")
                                      : (model.isLocalOrigin ? qsTr("Local") : qsTr("Reçu"))
                            }

                            Label {
                                Layout.preferredWidth: 90
                                text: model.fileCount === 1 ? qsTr("1 fichier") : qsTr("%1 fichiers").arg(model.fileCount)
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignRight
                            }

                            FaIcon {
                                glyph: "\uf105"
                                font.pixelSize: 13
                                color: Theme.textTertiary
                            }
                        }

                        MouseArea {
                            id: folderRowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    removeConfirmDialog.targetFolderId = model.folderId
                                    removeConfirmDialog.targetFolderName = model.name
                                    removeConfirmDialog.open()
                                    return
                                }
                                if (!model.isLocalOrigin) {
                                    if (model.localPath && model.localPath.length > 0) {
                                        root.openFolder(model.folderId, model.name, false, model.uuid)
                                    } else {
                                        setLocalPathDialog.targetFolderId = model.folderId
                                        setLocalPathDialog.targetFolderName = model.name
                                        setLocalPathDialog.targetFolderUuid = model.uuid
                                        setLocalPathDialog.open()
                                    }
                                } else {
                                    root.openFolder(model.folderId, model.name, true, model.uuid)
                                }
                            }
                        }
                    }
                }
            }

            // =====================================================
            // VUE DOSSIER OUVERT : fichiers/sous-dossiers (grille ou
            // liste), icones par type de fichier + badges de statut.
            // =====================================================
            ColumnLayout {
                anchors.fill: parent
                visible: root.openedFolderId >= 0 && !root.showHistory
                spacing: 0

                RowLayout {
                    visible: false
                    Layout.preferredHeight: 0
                    Layout.minimumHeight: 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.bottomMargin: 10
                    spacing: 8

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: Theme.colorForName(root.openedFolderName)
                        Text {
                            anchors.centerIn: parent
                            text: root.openedFolderName.length > 0 ? root.openedFolderName.charAt(0).toUpperCase() : "?"
                            color: "#FFFFFF"
                            font.pixelSize: 11
                            font.bold: true
                            font.family: Theme.fontFamily
                        }
                    }
                    Label {
                        text: root.openedFolderName
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        font.family: Theme.fontFamily
                    }
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("%n élément(s)", "", filesListView.count)
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeCaption
                        font.family: Theme.fontFamily
                    }
                }

                ListView {
                    id: filesListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.topMargin: 8
                    spacing: 0
                    clip: true
                    visible: root.viewMode === "list"
                    model: root.browserItems

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }

                    delegate: Rectangle {
                        id: fileRow
                        width: filesListView.width
                        height: fileRow.hasConflict ? 128 : (fileRow.isFolder ? 56 : 40)
                        clip: true
                        color: fileRowArea.containsMouse ? Theme.surfaceHover
                               : (index % 2 === 1 ? Theme.surfaceAlt : "transparent")
                        radius: Theme.radiusSmall
                        Behavior on color { ColorAnimation { duration: 100 } }

                        readonly property bool isFolder: modelData.kind === "folder"
                        readonly property bool hasConflict: !isFolder
                            && root.conflictedFiles.hasOwnProperty(modelData.relativePath)
                        readonly property string conflictPath: hasConflict ? root.conflictedFiles[modelData.relativePath] : ""
                        readonly property var kind: isFolder ? null : root.fileKindFor(modelData.name)
                        readonly property color folderAccent: "#FFC83D"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: fileRow.isFolder ? 56 : 40
                                spacing: 8

                                Rectangle {
                                    visible: fileRow.isFolder
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: 8
                                    color: Qt.rgba(fileRow.folderAccent.r,
                                                   fileRow.folderAccent.g,
                                                   fileRow.folderAccent.b, 0.16)

                                    FaIcon {
                                        anchors.centerIn: parent
                                        glyph: "\uf114"
                                        font.pixelSize: 15
                                        color: fileRow.folderAccent
                                    }
                                }
                                FaIcon {
                                    visible: !fileRow.isFolder
                                    glyph: fileRow.kind ? fileRow.kind.glyph : "\uf016"
                                    font.pixelSize: 15
                                    color: fileRow.kind ? fileRow.kind.color : Theme.textSecondary
                                }

                                Rectangle {
                                    visible: fileRow.hasConflict
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: Theme.warning
                                    Label {
                                        anchors.centerIn: parent
                                        text: "!"
                                        color: "#FFFFFF"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: modelData.name
                                    color: fileRow.hasConflict ? Theme.warning : Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: fileRow.isFolder ? Font.Medium : Font.Normal
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideMiddle

                                    ToolTip.visible: truncated && fileRowArea.containsMouse
                                    ToolTip.text: modelData.name
                                    ToolTip.delay: 500
                                }

                                Label {
                                    visible: !fileRow.isFolder
                                    Layout.preferredWidth: 70
                                    text: root.formatBytes(modelData.size)
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.fontFamily
                                    horizontalAlignment: Text.AlignRight
                                }

                                Label {
                                    visible: fileRow.isFolder
                                    Layout.preferredWidth: 70
                                    text: modelData.count === 1 ? qsTr("1 fichier") : qsTr("%1 fichiers").arg(modelData.count)
                                    color: Theme.textTertiary
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.family: Theme.fontFamily
                                    horizontalAlignment: Text.AlignRight
                                }

                                Label {
                                    visible: !fileRow.isFolder
                                    Layout.preferredWidth: 32
                                    text: "v" + modelData.version
                                    color: Theme.textTertiary
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.family: Theme.fontFamily
                                }

                                StatusBadge {
                                    visible: !fileRow.isFolder
                                    tone: fileRow.hasConflict ? "warning" : "success"
                                    text: fileRow.hasConflict ? qsTr("Conflit") : qsTr("Synchronisé")
                                }

                                FaIcon {
                                    visible: fileRow.isFolder
                                    glyph: "\uf105"
                                    font.pixelSize: 13
                                    color: Theme.textTertiary
                                }
                            }

                            // Sous-ligne + actions de résolution de conflit
                            Label {
                                visible: fileRow.hasConflict
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.leftMargin: 23
                                text: qsTr("→ copie en conflit : %1").arg(fileRow.conflictPath)
                                color: Theme.warning
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                elide: Text.ElideMiddle
                            }

                            RowLayout {
                                visible: fileRow.hasConflict
                                Layout.fillWidth: true
                                Layout.leftMargin: 23
                                Layout.bottomMargin: 6
                                spacing: Theme.spacingSmall
                                z: 1

                                AppButton {
                                    text: qsTr("Conserver local")
                                    variant: "secondary"
                                    onClicked: root.resolveConflictFor(modelData.relativePath, fileRow.conflictPath, "keep_local")
                                }
                                AppButton {
                                    text: qsTr("Conserver distant")
                                    variant: "secondary"
                                    onClicked: root.resolveConflictFor(modelData.relativePath, fileRow.conflictPath, "keep_remote")
                                }
                                AppButton {
                                    text: qsTr("Garder les deux")
                                    variant: "secondary"
                                    onClicked: root.resolveConflictFor(modelData.relativePath, fileRow.conflictPath, "keep_both")
                                }
                            }
                        }

                        MouseArea {
                            id: fileRowArea
                            anchors.fill: parent
                            z: 0
                            enabled: !fileRow.hasConflict
                            hoverEnabled: true
                            cursorShape: fileRow.isFolder ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (fileRow.isFolder) root.openBrowserFolder(modelData.path)
                            }
                        }
                    }

                    Label {
                        visible: filesListView.count === 0
                        anchors.centerIn: parent
                        text: qsTr("Ce dossier partagé ne contient aucun fichier indexé.")
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                    }
                }

                // Vue grille d'icônes des fichiers/sous-dossiers
                GridView {
                    id: filesGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.topMargin: 8
                    visible: root.viewMode === "grid"
                    readonly property int columns: Math.max(3, Math.min(8, Math.floor(width / 104)))
                    cellWidth: Math.floor(width / columns)
                    cellHeight: 148
                    clip: true
                    model: root.browserItems

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }

                    delegate: Item {
                        id: fileTile
                        width: filesGrid.cellWidth
                        height: filesGrid.cellHeight
                        clip: true

                        readonly property bool isFolder: modelData.kind === "folder"
                        readonly property bool hasConflict: !isFolder
                            && root.conflictedFiles.hasOwnProperty(modelData.relativePath)
                        readonly property var kind: isFolder ? null : root.fileKindFor(modelData.name)
                        readonly property color tileColor: isFolder ? "#FFC83D"
                                                                     : (fileTile.kind ? fileTile.kind.color : Theme.textSecondary)
                        readonly property bool tileHovered: fileTileArea.containsMouse

                        ColumnLayout {
                            z: 1
                            anchors.fill: parent
                            anchors.topMargin: 12
                            anchors.bottomMargin: 8
                            spacing: 4

                            Item {
                                id: subfolderIconArea
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: fileTile.isFolder ? 64 : 40
                                Layout.preferredHeight: fileTile.isFolder ? 52 : 30

                                Item {
                                    visible: fileTile.isFolder
                                    anchors.fill: parent
                                    property real radius: 6

                                    Rectangle {
                                        x: 2
                                        y: 4
                                        width: parent.width * 0.42
                                        height: 11
                                        radius: 3
                                        color: fileTile.tileColor
                                        opacity: 0.75
                                    }

                                    Rectangle {
                                        y: 11
                                        width: parent.width
                                        height: parent.height - 11
                                        radius: parent.radius
                                        color: fileTile.tileColor

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                                                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                                            }
                                        }

                                        Rectangle {
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: parent.height * 0.38
                                            radius: parent.radius
                                            color: Qt.rgba(1, 1, 1, 0.10)
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: !fileTile.isFolder
                                    anchors.fill: parent
                                    radius: 8
                                    color: Qt.rgba(fileTile.tileColor.r,
                                                    fileTile.tileColor.g,
                                                    fileTile.tileColor.b, 0.14)

                                    FaIcon {
                                        anchors.centerIn: parent
                                        glyph: fileTile.kind ? fileTile.kind.glyph : "\uf016"
                                        font.pixelSize: 20
                                        color: fileTile.tileColor
                                    }
                                }

                                Rectangle {
                                    visible: fileTile.hasConflict
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: Theme.warning
                                    border.width: 2
                                    border.color: Theme.surface
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: -6
                                    anchors.topMargin: -4
                                }

                                Rectangle {
                                    visible: fileTile.isFolder && modelData.count > 0
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: Theme.primary
                                    border.width: 2
                                    border.color: Theme.surface
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.leftMargin: -6
                                    anchors.topMargin: -4
                                    Text {
                                        anchors.centerIn: parent
                                        text: (modelData.count !== undefined && modelData.count > 9) ? "9+" : (modelData.count !== undefined ? modelData.count : "")
                                        font.pixelSize: 8
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                        color: Theme.primaryText
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                text: modelData.name
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                maximumLineCount: 1

                                ToolTip.visible: truncated && fileTile.tileHovered
                                ToolTip.text: modelData.name
                                ToolTip.delay: 500
                            }
                            Label {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                text: fileTile.isFolder
                                      ? (modelData.count === 1 ? qsTr("1 fichier") : qsTr("%1 fichiers").arg(modelData.count))
                                      : root.formatBytes(modelData.size)
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            ColumnLayout {
                                visible: fileTile.hasConflict
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                spacing: 2

                                AppButton {
                                    text: qsTr("Local")
                                    variant: "secondary"
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    onClicked: root.resolveConflictFor(modelData.relativePath,
                                                                        root.conflictedFiles[modelData.relativePath],
                                                                        "keep_local")
                                }
                                AppButton {
                                    text: qsTr("Distant")
                                    variant: "secondary"
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    onClicked: root.resolveConflictFor(modelData.relativePath,
                                                                        root.conflictedFiles[modelData.relativePath],
                                                                        "keep_remote")
                                }
                                AppButton {
                                    text: qsTr("Les deux")
                                    variant: "secondary"
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    onClicked: root.resolveConflictFor(modelData.relativePath,
                                                                        root.conflictedFiles[modelData.relativePath],
                                                                        "keep_both")
                                }
                            }
                        }

                        MouseArea {
                            id: fileTileArea
                            anchors.fill: parent
                            z: 0
                            enabled: !fileTile.hasConflict
                            hoverEnabled: true
                            cursorShape: fileTile.isFolder ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (fileTile.isFolder) root.openBrowserFolder(modelData.path)
                            }
                        }
                    }

                    Label {
                        visible: filesGrid.count === 0
                        anchors.centerIn: parent
                        text: qsTr("Ce dossier partagé ne contient aucun fichier indexé.")
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                    }
                }
            }

            // =====================================================
            // VUE HISTORIQUE (journal de synchronisation)
            // =====================================================
            ColumnLayout {
                anchors.fill: parent
                visible: root.openedFolderId >= 0 && root.showHistory
                spacing: 0

                Rectangle {
                    visible: false
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.border
                    Layout.topMargin: 8
                }

                Item { visible: false; Layout.preferredHeight: 0 }

                RowLayout {
                    visible: false
                    Layout.preferredHeight: 0
                    Layout.minimumHeight: 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.bottomMargin: 10
                    spacing: 8

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: Theme.colorForName(root.openedFolderName)
                        Text {
                            anchors.centerIn: parent
                            text: root.openedFolderName.length > 0 ? root.openedFolderName.charAt(0).toUpperCase() : "?"
                            color: "#FFFFFF"
                            font.pixelSize: 11
                            font.bold: true
                            font.family: Theme.fontFamily
                        }
                    }
                    Label {
                        text: qsTr("Historique — %1").arg(root.openedFolderName)
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        font.family: Theme.fontFamily
                    }
                    Item { Layout.fillWidth: true }
                }

                ListView {
                    id: historyListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: Theme.spacingMedium
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.bottomMargin: 8
                    spacing: 2
                    clip: true
                    model: root.currentSyncHistory

                    header: Rectangle {
                        width: historyListView.width
                        height: 32
                        color: Theme.surfaceAlt
                        radius: Theme.radiusSmall
                        border.width: 1
                        border.color: Theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.rightMargin: Theme.spacingSmall
                            Label { Layout.preferredWidth: 70; text: qsTr("Opération"); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary; font.family: Theme.fontFamily }
                            Label { Layout.fillWidth: true; text: qsTr("Fichier"); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary; font.family: Theme.fontFamily }
                            Label { Layout.preferredWidth: 50; text: qsTr("Ver."); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary; font.family: Theme.fontFamily }
                            Label { Layout.preferredWidth: 120; text: qsTr("Date"); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary; font.family: Theme.fontFamily }
                        }
                    }

                    delegate: Rectangle {
                        width: historyListView.width
                        height: modelData.type === "Rename" ? 52 : 36
                        radius: Theme.radiusSmall
                        color: index % 2 === 1 ? Theme.surfaceAlt : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSmall
                            anchors.rightMargin: Theme.spacingSmall

                            StatusBadge {
                                Layout.preferredWidth: 70
                                tone: {
                                    switch (modelData.type) {
                                    case "Create": return "success"
                                    case "Update": return "info"
                                    case "Delete": return "error"
                                    case "Rename": return "warning"
                                    default: return "neutral"
                                    }
                                }
                                text: {
                                    switch (modelData.type) {
                                    case "Create": return qsTr("Créé")
                                    case "Update": return qsTr("Modifié")
                                    case "Delete": return qsTr("Supprimé")
                                    case "Rename": return qsTr("Renommé")
                                    default: return modelData.type
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.relativePath
                                    color: modelData.type === "Delete" ? Theme.textTertiary : Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideMiddle
                                    font.strikeout: modelData.type === "Delete"
                                }
                                Label {
                                    visible: modelData.type === "Rename" && modelData.oldRelativePath.length > 0
                                    Layout.fillWidth: true
                                    text: qsTr("← %1").arg(modelData.oldRelativePath)
                                    color: Theme.textTertiary
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideMiddle
                                }
                            }

                            Label {
                                Layout.preferredWidth: 50
                                text: "v" + modelData.version
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                            }

                            Label {
                                Layout.preferredWidth: 120
                                text: {
                                    const d = new Date(modelData.createdAt)
                                    return isNaN(d.getTime()) ? modelData.createdAt
                                        : d.toLocaleTimeString(Qt.locale(), "HH:mm:ss")
                                }
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                            }
                        }
                    }

                    Label {
                        visible: historyListView.count === 0
                        anchors.centerIn: parent
                        text: qsTr("Aucune opération enregistrée pour ce dossier.\nReindexez le dossier pour commencer à alimenter le journal.")
                        color: Theme.textTertiary
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSizeBody
                        font.family: Theme.fontFamily
                    }
                }
            }
        }

        // =========================================================
        // Barre d'état inférieure (même style que FileTransferView)
        // =========================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: Theme.statusBarBackground
            border.width: 1
            border.color: Theme.border
            visible: gridView.count > 0 || root.openedFolderId >= 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 16

                RowLayout {
                    visible: root.openedFolderId < 0
                    spacing: 4
                    FaIcon { glyph: "\uf07b"; font.pixelSize: 12; color: Theme.textSecondary }
                    Label {
                        text: qsTr("%n dossier(s)", "", gridView.count)
                        font.pixelSize: Theme.fontSizeCaption
                        font.family: Theme.fontFamily
                        color: Theme.textSecondary
                    }
                }
                RowLayout {
                    visible: root.openedFolderId >= 0 && !root.showHistory
                    spacing: 4
                    FaIcon { glyph: "\uf0f6"; font.pixelSize: 12; color: Theme.textSecondary }
                    Label {
                        text: qsTr("%n élément(s)", "", filesListView.count)
                        font.pixelSize: Theme.fontSizeCaption
                        font.family: Theme.fontFamily
                        color: Theme.textSecondary
                    }
                }
                RowLayout {
                    visible: root.openedFolderId >= 0 && root.showHistory
                    spacing: 4
                    FaIcon { glyph: "\uf1da"; font.pixelSize: 12; color: Theme.textSecondary }
                    Label {
                        text: qsTr("%n entrée(s) d'historique", "", historyListView.count)
                        font.pixelSize: Theme.fontSizeCaption
                        font.family: Theme.fontFamily
                        color: Theme.textSecondary
                    }
                }
                Item { Layout.fillWidth: true }
                Label {
                    visible: root.openedFolderId < 0 && root.hasActiveFilters()
                    text: qsTr("Filtres actifs")
                    font.pixelSize: Theme.fontSizeCaption
                    font.family: Theme.fontFamily
                    color: Theme.primary
                }
            }
        }
    }
}
