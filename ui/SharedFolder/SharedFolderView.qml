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
    property var currentSyncHistory: []
    property bool showHistory: false

    // Ensemble des chemins relatifs en conflit pour le dossier actuellement ouvert.
    // Clé: relativePath  Valeur: chemin du fichier de conflit renommé.
    // Réinitialisé à l'ouverture d'un nouveau dossier.
    property var conflictedFiles: ({})

    // File d'attente des demandes de confirmation de partage (dossiers
    // distants reçus sans localPath) pas encore affichées : plusieurs
    // dossiers peuvent être reçus d'affilée, on les présente un par un
    // plutôt que d'empiler des dialogues.
    property var pendingShareConfirmations: []

    function showNextShareConfirmation() {
        if (shareConfirmDialog.visible || root.pendingShareConfirmations.length === 0) {
            return
        }
        const next = root.pendingShareConfirmations.shift()
        shareConfirmDialog.targetFolderId = next.folderId
        shareConfirmDialog.targetFolderName = next.folderName
        shareConfirmDialog.ownerName = next.ownerName
        shareConfirmDialog.suggestedPath = next.suggestedPath
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
        } else {
            root.currentFiles = []
            root.conflictedFiles = {}
        }
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
            if (folderId === root.openedFolderId) {
                root.refreshFiles()
                root.refreshHistory()
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
        function onFolderShareConfirmationRequested(folderId, folderName, ownerName, suggestedPath) {
            root.pendingShareConfirmations.push({
                folderId: folderId,
                folderName: folderName,
                ownerName: ownerName,
                suggestedPath: suggestedPath
            })
            root.showNextShareConfirmation()
        }
    }

    Component.onCompleted: {
        if (root.context) root.context.refresh()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    FolderDialog {
        id: folderPickerDialog
        title: qsTr("Choisir un dossier local à partager")
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
            conflictBanner.show(relativePath, conflictPath)
        }
    }

    // ---- dialogue de création ----
    Dialog {
        id: createDialog
        title: qsTr("Nouveau dossier partagé")
        modal: true
        anchors.centerIn: parent
        width: 420
        height: 680
        standardButtons: Dialog.NoButton

        property string localPath: ""

        onOpened: {
            nameField.text = ""
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

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingMedium

            Label {
                text: qsTr("Nom du dossier partagé")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: qsTr("ex : Documents projet")
                font.pixelSize: Theme.fontSizeBody
                color: Theme.text
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: nameField.activeFocus ? Theme.primary : Theme.border
                }
            }

            Label {
                text: qsTr("Dossier local à partager")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Label {
                    Layout.fillWidth: true
                    text: createDialog.localPath.length > 0 ? createDialog.localPath : qsTr("Aucun dossier sélectionné")
                    color: createDialog.localPath.length > 0 ? Theme.text : Theme.textTertiary
                    elide: Text.ElideMiddle
                    font.pixelSize: Theme.fontSizeSmall
                }
                AppButton {
                    text: qsTr("Parcourir…")
                    variant: "secondary"
                    onClicked: folderPickerDialog.open()
                }
            }

            Label {
                text: qsTr("Partager avec")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                radius: Theme.radiusSmall
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

                        CheckBox {
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

            CheckBox {
                id: allowWriteCheckBox
                text: qsTr("Autoriser la modification (lecture/écriture)")
                checked: true
                contentItem: Label {
                    text: allowWriteCheckBox.text
                    leftPadding: allowWriteCheckBox.indicator.width + Theme.spacingSmall
                    verticalAlignment: Text.AlignVCenter
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Label {
                text: qsTr("Exclure de la synchronisation (optionnel)")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
            TextField {
                id: excludePatternsField
                Layout.fillWidth: true
                placeholderText: qsTr("ex : *.log, node_modules, drafts/*")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.text
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: excludePatternsField.activeFocus ? Theme.primary : Theme.border
                }
            }
            Label {
                text: qsTr("Motifs séparés par des virgules. S'applique en plus des exclusions par défaut (dossiers systèmes, fichiers temporaires…). Local à ce poste.")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingSmall

                Item { Layout.fillWidth: true }

                AppButton {
                    text: qsTr("Annuler")
                    variant: "ghost"
                    onClicked: createDialog.close()
                }
                AppButton {
                    text: qsTr("Créer")
                    variant: "primary"
                    enabled: nameField.text.trim().length > 0 && createDialog.localPath.length > 0
                    onClicked: {
                        if (!root.context) return
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
                        }
                    }
                }
            }
        }
    }

    // ---- dialogue de modification des motifs d'exclusion (debrief point #4) ----
    Dialog {
        id: editExcludePatternsDialog
        title: qsTr("Exclusions — %1").arg(editExcludePatternsDialog.targetFolderName)
        modal: true
        anchors.centerIn: parent
        width: 420
        height: 320
        standardButtons: Dialog.NoButton

        property int targetFolderId: -1
        property string targetFolderName: ""
        property var impactedPaths: []

        function refreshImpactPreview() {
            if (root.context && editExcludePatternsDialog.targetFolderId >= 0) {
                editExcludePatternsDialog.impactedPaths =
                    root.context.previewExcludePatternsImpact(editExcludePatternsDialog.targetFolderId,
                                                               excludePatternsEditField.text.trim())
            } else {
                editExcludePatternsDialog.impactedPaths = []
            }
        }

        onOpened: {
            excludePatternsEditField.text =
                root.context ? root.context.excludePatternsForFolder(editExcludePatternsDialog.targetFolderId) : ""
            // Motifs actuellement enregistres : par definition aucun fichier
            // deja indexe ne peut les matcher (ils seraient deja tombstones),
            // donc l'impact initial est toujours vide -- pas la peine
            // d'attendre le debounce pour l'afficher.
            editExcludePatternsDialog.impactedPaths = []
        }

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingMedium

            Label {
                text: qsTr("Motifs glob séparés par des virgules (ex : *.log, node_modules, drafts/*). S'ajoutent aux exclusions par défaut. Ne s'applique qu'à ce poste.")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            TextField {
                id: excludePatternsEditField
                Layout.fillWidth: true
                placeholderText: qsTr("ex : *.log, node_modules, drafts/*")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.text
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: excludePatternsEditField.activeFocus ? Theme.primary : Theme.border
                }
                // Previsualisation live (debounce 250ms) de l'impact sur les
                // fichiers deja partages : sans ca, un motif trop large
                // ("*.md" tape par erreur au lieu de "*.tmp") ne se
                // remarquait qu'apres coup, une fois les fichiers disparus
                // de la liste suite a l'enregistrement.
                onTextChanged: impactPreviewTimer.restart()
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

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
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
                                                                    excludePatternsEditField.text.trim())) {
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
    Dialog {
        id: setLocalPathDialog
        title: qsTr("Définir le dossier local — %1").arg(setLocalPathDialog.targetFolderName)
        modal: true
        anchors.centerIn: parent
        width: 420
        height: 280
        standardButtons: Dialog.NoButton

        property int targetFolderId: -1
        property string targetFolderName: ""
        property string targetFolderUuid: ""
        property string localPath: ""

        onOpened: {
            setLocalPathDialog.localPath = ""
        }

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        ColumnLayout {
            anchors.fill: parent
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
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Label {
                    Layout.fillWidth: true
                    text: setLocalPathDialog.localPath.length > 0 ? setLocalPathDialog.localPath : qsTr("Aucun dossier sélectionné")
                    color: setLocalPathDialog.localPath.length > 0 ? Theme.text : Theme.textTertiary
                    elide: Text.ElideMiddle
                    font.pixelSize: Theme.fontSizeSmall
                }
                AppButton {
                    text: qsTr("Parcourir…")
                    variant: "secondary"
                    onClicked: remoteFolderPickerDialog.open()
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
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
    Dialog {
        id: shareConfirmDialog
        title: qsTr("Nouveau dossier partagé — %1").arg(shareConfirmDialog.targetFolderName)
        modal: true
        anchors.centerIn: parent
        width: 440
        height: 300
        standardButtons: Dialog.NoButton
        closePolicy: Popup.NoAutoClose

        property int targetFolderId: -1
        property string targetFolderName: ""
        property string ownerName: ""
        property string suggestedPath: ""

        onClosed: root.showNextShareConfirmation()

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingMedium

            Label {
                text: shareConfirmDialog.ownerName.length > 0
                    ? qsTr("« %1 » vient de partager le dossier « %2 » avec vous.")
                        .arg(shareConfirmDialog.ownerName).arg(shareConfirmDialog.targetFolderName)
                    : qsTr("Un dossier partagé « %1 » a été reçu.").arg(shareConfirmDialog.targetFolderName)
                color: Theme.text
                font.pixelSize: Theme.fontSizeBody
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
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

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
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
    Dialog {
        id: manageAccessDialog
        title: qsTr("Gérer les accès — %1").arg(manageAccessDialog.targetFolderName)
        modal: true
        anchors.centerIn: parent
        width: 460
        height: 560
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

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        ColumnLayout {
            anchors.fill: parent
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
                radius: Theme.radiusSmall
                color: "#fff5f5"
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
                Layout.preferredHeight: 180
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

                            // Nom + permission (cliquable pour basculer Read↔Write)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Label {
                                    text: modelData.username
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                }
                                Label {
                                    text: modelData.permission === "Write"
                                          ? qsTr("Lecture / écriture")
                                          : qsTr("Lecture seule")
                                    color: Theme.textTertiary
                                    font.pixelSize: Theme.fontSizeCaption
                                }
                            }

                            // Bouton bascule Read ↔ Write
                            AppButton {
                                text: modelData.permission === "Write"
                                      ? qsTr("→ Lecture")
                                      : qsTr("→ Écriture")
                                variant: "secondary"
                                onClicked: {
                                    if (root.context) {
                                        const newWrite = (modelData.permission !== "Write")
                                        root.context.changePermission(
                                            manageAccessDialog.targetFolderId,
                                            modelData.userId,
                                            newWrite)
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

                ComboBox {
                    id: addUserComboBox
                    Layout.fillWidth: true
                    model: ListModel { id: candidateModel }
                    textRole: "username"
                    currentIndex: -1
                    displayText: currentIndex < 0 ? qsTr("Choisir un utilisateur…") : currentText

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.surfaceAlt
                        border.width: 1
                        border.color: addUserComboBox.activeFocus ? Theme.primary : Theme.border
                    }

                    contentItem: Label {
                        leftPadding: Theme.spacingSmall
                        text: addUserComboBox.displayText
                        color: addUserComboBox.currentIndex < 0 ? Theme.textTertiary : Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

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

                CheckBox {
                    id: addWriteCheckBox
                    text: qsTr("Écriture")
                    checked: true
                    contentItem: Label {
                        text: addWriteCheckBox.text
                        leftPadding: addWriteCheckBox.indicator.width + Theme.spacingXs
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                    }
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

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall
                Item { Layout.fillWidth: true }
                AppButton {
                    text: qsTr("Fermer")
                    variant: "ghost"
                    onClicked: manageAccessDialog.close()
                }
            }
        }
    }

    // ---- dialogue de confirmation de suppression ----
    Dialog {
        id: removeConfirmDialog
        title: qsTr("Supprimer ce dossier partagé ?")
        modal: true
        anchors.centerIn: parent
        width: 380
        standardButtons: Dialog.NoButton

        property int targetFolderId: -1
        property string targetFolderName: ""

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingMedium

            Label {
                Layout.fillWidth: true
                text: qsTr("« %1 » ne sera plus partagé. Les fichiers restent intacts sur le disque : seul l'enregistrement dans CollabLAN est supprimé.").arg(removeConfirmDialog.targetFolderName)
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
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
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Barre d'adresse
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            color: Theme.addressBarBackground
            border.width: 1
            border.color: Theme.border
            z: 2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Button {
                    implicitWidth: 32
                    implicitHeight: 32
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: parent.hovered ? Theme.surfaceHover : "transparent"
                    }
                    contentItem: Text {
                        text: "\u2190"
                        color: Theme.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (root.openedFolderId >= 0) {
                            root.openedFolderId = -1
                        } else {
                            root.backRequested()
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: root.openedFolderId >= 0
                          ? qsTr("Dossiers partagés  ›  %1").arg(root.openedFolderName)
                          : qsTr("Dossiers partagés")
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.text
                    elide: Text.ElideRight
                }

                AppButton {
                    visible: root.openedFolderId >= 0
                    text: root.showHistory ? qsTr("Fichiers") : qsTr("Historique")
                    variant: "ghost"
                    onClicked: root.showHistory = !root.showHistory
                }

                AppButton {
                    visible: root.openedFolderId >= 0
                    enabled: root.openedFolderIsLocalOrigin
                    text: qsTr("Réindexer")
                    variant: "secondary"
                    onClicked: {
                        if (root.context) {
                            root.context.shareFolder(root.openedFolderId)
                            root.refreshFiles()
                            root.refreshHistory()
                        }
                    }
                }

                // ---- Menu « ⋯ » regroupant les actions secondaires ----
                // Exclusions et Gérer les accès sont fusionnés ici pour
                // éviter le débordement horizontal de la barre d'actions
                // quand la fenêtre n'est pas assez large.
                AppButton {
                    id: moreActionsBtn
                    visible: root.openedFolderId >= 0
                    text: qsTr("⋯")
                    variant: "secondary"
                    onClicked: moreActionsMenu.open()

                    Menu {
                        id: moreActionsMenu
                        // Ancré sous le bouton pour rester dans l'écran
                        y: parent.height + 2

                        MenuItem {
                            text: qsTr("Exclusions…")
                            onTriggered: {
                                editExcludePatternsDialog.targetFolderId = root.openedFolderId
                                editExcludePatternsDialog.targetFolderName = root.openedFolderName
                                editExcludePatternsDialog.open()
                            }
                        }
                        MenuItem {
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

        // ---- Vue grille des dossiers partagés ----
        ScrollView {
            visible: root.openedFolderId < 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            GridView {
                id: gridView
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                cellWidth: 148
                cellHeight: 144
                model: root.context ? root.context.folderModel : null

                delegate: Item {
                    width: gridView.cellWidth
                    height: gridView.cellHeight

                    FolderTile {
                        anchors.centerIn: parent
                        label: model.name
                        sublabel: model.fileCount === 1 ? qsTr("1 fichier") : qsTr("%1 fichiers").arg(model.fileCount)
                        count: model.fileCount
                        hasConflict: model.hasConflict
                        onOpened: {
                            if (!model.isLocalOrigin) {
                                // Si le localPath est déjà défini, ouvrir directement le dossier
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

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: {
                                removeConfirmDialog.targetFolderId = model.folderId
                                removeConfirmDialog.targetFolderName = model.name
                                removeConfirmDialog.open()
                            }
                        }
                    }
                }

                Label {
                    visible: gridView.count === 0
                    anchors.centerIn: parent
                    text: qsTr("Aucun dossier partagé pour le moment.\nCliquez sur « + Nouveau dossier » pour commencer.")
                    color: Theme.textTertiary
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Theme.fontSizeBody
                }
            }
        }

        // ---- Vue liste des fichiers d'un dossier partagé ----
        ScrollView {
            visible: root.openedFolderId >= 0 && !root.showHistory
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: filesListView
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: 2
                model: root.currentFiles

                header: Rectangle {
                    width: filesListView.width
                    height: 32
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingSmall
                        anchors.rightMargin: Theme.spacingSmall
                        Label { Layout.fillWidth: true; text: qsTr("Nom"); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary }
                        Label { Layout.preferredWidth: 90; text: qsTr("Taille"); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary }
                        Label { Layout.preferredWidth: 60; text: qsTr("Version"); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary }
                    }
                }

                delegate: Rectangle {
                    id: fileRow
                    width: filesListView.width
                    height: hasConflict ? 90 : 36
                    color: fileMouseArea.containsMouse ? Theme.surfaceHover : "transparent"

                    // true si ce fichier a un conflit en attente de résolution
                    readonly property bool hasConflict: root.conflictedFiles.hasOwnProperty(modelData.relativePath)
                    readonly property string conflictPath: hasConflict ? root.conflictedFiles[modelData.relativePath] : ""

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingSmall
                        anchors.rightMargin: Theme.spacingSmall
                        spacing: 1

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Theme.spacingSmall

                            // Badge conflit — icône ⚠ ambrée sur la gauche du nom
                            Rectangle {
                                visible: fileRow.hasConflict
                                width: 20
                                height: 20
                                radius: 10
                                color: "#C07000"
                                Label {
                                    anchors.centerIn: parent
                                    text: "⚠"
                                    color: "#FFFFFF"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                                HoverHandler { id: badgeHover }
                                ToolTip.visible: badgeHover.hovered
                                ToolTip.text: qsTr("Conflit → %1").arg(fileRow.conflictPath)
                            }

                            Label {
                                Layout.fillWidth: true
                                text: modelData.relativePath
                                color: fileRow.hasConflict ? "#C07000" : Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: fileRow.hasConflict
                                elide: Text.ElideMiddle
                            }
                            Label {
                                Layout.preferredWidth: 90
                                text: root.formatBytes(modelData.size)
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            Label {
                                Layout.preferredWidth: 60
                                text: "v" + modelData.version
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        // Sous-ligne : chemin du fichier de conflit renommé
                        Label {
                            visible: fileRow.hasConflict
                            Layout.fillWidth: true
                            text: qsTr("→ copie en conflit : %1").arg(fileRow.conflictPath)
                            color: "#C07000"
                            font.pixelSize: Theme.fontSizeCaption
                            elide: Text.ElideMiddle
                        }

                        RowLayout {
                            visible: fileRow.hasConflict
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            AppButton {
                                text: qsTr("Conserver local")
                                variant: "secondary"
                                onClicked: {
                                    if (root.context) {
                                        root.context.resolveConflict(root.openedFolderId, modelData.relativePath, fileRow.conflictPath, "keep_local")
                                        root.refreshFiles()
                                        root.refreshHistory()
                                    }
                                }
                            }
                            AppButton {
                                text: qsTr("Conserver distant")
                                variant: "secondary"
                                onClicked: {
                                    if (root.context) {
                                        root.context.resolveConflict(root.openedFolderId, modelData.relativePath, fileRow.conflictPath, "keep_remote")
                                        root.refreshFiles()
                                        root.refreshHistory()
                                    }
                                }
                            }
                            AppButton {
                                text: qsTr("Garder les deux")
                                variant: "secondary"
                                onClicked: {
                                    if (root.context) {
                                        root.context.resolveConflict(root.openedFolderId, modelData.relativePath, fileRow.conflictPath, "keep_both")
                                        root.refreshFiles()
                                        root.refreshHistory()
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: fileMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }

                Label {
                    visible: filesListView.count === 0
                    anchors.centerIn: parent
                    text: qsTr("Ce dossier partagé ne contient aucun fichier indexé.")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeBody
                }
            }
        }

        // ---- Journal de synchronisation (Release 3) ----
        // Affiche les SyncOperations enregistrees par SyncEngine apres chaque
        // (re)indexation : Create / Update / Delete / Rename, avec le chemin
        // relatif, la version et l'horodatage. Bascule via le bouton "Historique".
        ScrollView {
            visible: root.openedFolderId >= 0 && root.showHistory
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: historyListView
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: 2
                model: root.currentSyncHistory

                header: Rectangle {
                    width: historyListView.width
                    height: 32
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingSmall
                        anchors.rightMargin: Theme.spacingSmall
                        Label { Layout.preferredWidth: 70; text: qsTr("Opération"); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary }
                        Label { Layout.fillWidth: true; text: qsTr("Fichier"); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary }
                        Label { Layout.preferredWidth: 50; text: qsTr("Ver."); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary }
                        Label { Layout.preferredWidth: 120; text: qsTr("Date"); font.bold: true; font.pixelSize: Theme.fontSizeCaption; color: Theme.textSecondary }
                    }
                }

                delegate: Rectangle {
                    width: historyListView.width
                    height: modelData.type === "Rename" ? 52 : 36
                    color: "transparent"

                    // Bordure de séparation en bas
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: Theme.border
                        opacity: 0.5
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingSmall
                        anchors.rightMargin: Theme.spacingSmall

                        // Pastille colorée selon le type d'opération
                        Rectangle {
                            Layout.preferredWidth: 70
                            height: 22
                            radius: Theme.radiusSmall
                            color: {
                                switch (modelData.type) {
                                case "Create": return "#1A7F4B"
                                case "Update": return "#1A5FA0"
                                case "Delete": return "#9B2E2E"
                                case "Rename": return "#6B4EA0"
                                default:       return Theme.border
                                }
                            }
                            opacity: 0.85
                            Label {
                                anchors.centerIn: parent
                                text: {
                                    switch (modelData.type) {
                                    case "Create": return qsTr("Créé")
                                    case "Update": return qsTr("Modifié")
                                    case "Delete": return qsTr("Supprimé")
                                    case "Rename": return qsTr("Renommé")
                                    default:       return modelData.type
                                    }
                                }
                                color: "#FFFFFF"
                                font.pixelSize: Theme.fontSizeCaption
                                font.bold: true
                            }
                        }

                        // Chemin relatif (ancien → nouveau pour Rename)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                Layout.fillWidth: true
                                text: modelData.relativePath
                                color: modelData.type === "Delete" ? Theme.textTertiary : Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideMiddle
                                font.strikeout: modelData.type === "Delete"
                            }
                            Label {
                                visible: modelData.type === "Rename" && modelData.oldRelativePath.length > 0
                                Layout.fillWidth: true
                                text: qsTr("← %1").arg(modelData.oldRelativePath)
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                                elide: Text.ElideMiddle
                            }
                        }

                        Label {
                            Layout.preferredWidth: 50
                            text: "v" + modelData.version
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
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
                }
            }
        }
    }
}
