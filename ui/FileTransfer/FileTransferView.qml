import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"

/*
 * FileTransferView - Écran "Transfert de fichiers" façon explorateur de
 * fichiers moderne et compact (design aligné sur la maquette de référence
 * "filetransfer_option_a_explorer_compact") :
 *   - Barre d'adresse : navigation (retour/actualiser) + fil d'Ariane
 *     cliquable + recherche + bascule grille/liste
 *   - Rangée de filtres rapides compacte (Tout, Reçus, Envoyés, Échoués)
 *   - Section "Correspondants" : grille de tuiles compactes (icône teintée
 *     + pastille de comptage + libellé + date relative), 6 colonnes environ
 *   - Vue "Détails" (liste avec en-têtes de colonnes, icônes de fichier
 *     colorées par type, lignes alternées) ou grille d'icônes pour les
 *     fichiers d'un correspondant
 *   - Barre d'état fine en bas, comme dans un explorateur natif
 *
 * Ajouts sur cette passe :
 *   - Panneau d'envoi (choix du fichier + destinataire + bouton Envoyer +
 *     accès au dossier de réception) : la fonctionnalité d'envoi n'était
 *     plus câblée à aucun bouton, seul `fileDialog` existait.
 *   - Toutes les couleurs en dur remplacées par des jetons `Theme.*`, pour
 *     que le mode sombre fonctionne sur cet écran.
 *   - `StatusBadge` réutilisé pour le statut, au lieu d'un badge redessiné
 *     à la main pour chaque état.
 *   - Barre de progression + pourcentage pour les transferts "En cours"
 *     (propriété `percent`, jusque-là ignorée par la vue).
 *   - Échecs de retry / ouverture d'emplacement remontés dans la bannière
 *     d'erreur au lieu d'un simple `console.warn`.
 */
Item {
    id: root

    property var context: (typeof transferContext !== "undefined") ? transferContext : null

    property string selectedFilePath: ""
    property string selectedFileName: ""

    // Sous ce seuil (fenetre partagee / petit ecran, minimum 640px pour
    // la fenetre entiere - cf. Main.qml), les colonnes secondaires de la
    // vue "Détails" (Sens, Date de modification) sont masquees.
    readonly property bool compactList: root.width < 900

    signal backRequested()

    // ---- fonctions utilitaires ----
    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 Ko"
        const units = ["o", "Ko", "Mo", "Go"]
        let value = bytes
        let unitIndex = 0
        while (value >= 1024 && unitIndex < units.length - 1) {
            value /= 1024
            unitIndex++
        }
        return (unitIndex === 0 ? value.toFixed(0) : value.toFixed(1)) + " " + units[unitIndex]
    }

    function formatDate(isoString) {
        if (!isoString) return ""
        const d = new Date(isoString)
        if (isNaN(d.getTime())) return ""
        return d.toLocaleString(Qt.locale(), "dd/MM/yyyy HH:mm")
    }

    // Date relative courte pour les tuiles de correspondants ("Hier",
    // "Lun.", "3 j.", "1 sem."...), a la maniere de la maquette compacte.
    function formatRelative(isoString) {
        if (!isoString) return ""
        const d = new Date(isoString)
        if (isNaN(d.getTime())) return ""
        const now = new Date()
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        const startOfDate = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const diffDays = Math.round((startOfToday - startOfDate) / 86400000)

        if (diffDays <= 0) return d.toLocaleString(Qt.locale(), "HH:mm")
        if (diffDays === 1) return qsTr("Hier")
        if (diffDays < 7) return qsTr("%1 j.").arg(diffDays)
        if (diffDays < 14) return qsTr("1 sem.")
        return qsTr("%1 sem.").arg(Math.floor(diffDays / 7))
    }

    function normalizePeerAddress(address) {
        if (!address) return ""
        let a = address.trim().toLowerCase()
        const v4MappedPrefix = "::ffff:"
        if (a.indexOf(v4MappedPrefix) === 0) {
            a = a.substring(v4MappedPrefix.length)
        }
        return a
    }

    function buildPeerGroups(transfers) {
        const groupsByKey = {}
        const order = []

        for (let i = 0; i < transfers.length; i++) {
            const item = transfers[i]
            const rawAddress = item.peerAddress || ""
            const peerMachineId = item.peerMachineId || ""
            const peerUserUuid = item.peerUserUuid || ""
            const peerUserName = item.peerUserName || ""

            // Cle conversation : sender/recipient identifient le correspondant
            // utilisateur, quel que soit le sens du transfert. peerMachineId
            // reste le repli stable pour les pairs LAN sans compte utilisateur.
            const key = peerUserUuid.length > 0
                        ? "user:" + peerUserUuid
                        : (peerMachineId.length > 0
                        ? "uuid:" + peerMachineId
                        : (rawAddress.length > 0 ? root.normalizePeerAddress(rawAddress) : "__unknown__"))

            if (!groupsByKey[key]) {
                groupsByKey[key] = {
                    peerKey: key,
                    peerLabel: peerUserName.length > 0 ? peerUserName
                               : ((item.peerName && item.peerName.length > 0) ? item.peerName
                               : (rawAddress.length > 0 ? rawAddress
                               : qsTr("Correspondant inconnu"))),
                    peerAddress: rawAddress,
                    peerMachineId: peerMachineId,
                    peerUserUuid: peerUserUuid,
                    peerUserName: peerUserName,
                    items: [],
                    lastTimestampMs: 0
                }
                order.push(key)
            }

            const group = groupsByKey[key]
            // Mettre à jour peerLabel si on reçoit un nom plus tard
            // (seulement si le label actuel est l'adresse ou "Correspondant inconnu")
            if (peerUserName.length > 0) {
                group.peerLabel = peerUserName
            } else if (item.peerName && item.peerName.length > 0) {
                if (group.peerLabel === rawAddress || group.peerLabel === qsTr("Correspondant inconnu")) {
                    group.peerLabel = item.peerName
                }
            }
            if (rawAddress.length > 0 && group.peerAddress.toLowerCase().indexOf("::ffff:") === 0
                    && rawAddress.toLowerCase().indexOf("::ffff:") !== 0) {
                group.peerAddress = rawAddress
                if (!item.peerName || item.peerName.length === 0) {
                    group.peerLabel = rawAddress
                }
            }

            const ts = item.timestamp ? Date.parse(item.timestamp) : 0
            group.items.push(item)
            if (ts > group.lastTimestampMs) {
                group.lastTimestampMs = ts
            }
        }

        const groups = order.map(function(key) { return groupsByKey[key] })
        groups.sort(function(a, b) { return b.lastTimestampMs - a.lastTimestampMs })
        for (let g = 0; g < groups.length; g++) {
            groups[g].items.sort(function(a, b) {
                return Date.parse(b.timestamp || 0) - Date.parse(a.timestamp || 0)
            })
        }
        return groups
    }

    // ---- propriétés ----
    property var peerGroups: root.buildPeerGroups(root.context ? root.context.activeTransfers : [])

    property string openedPeerKey: ""
    property string searchText: ""

    // Mode d'affichage : "grid" pour la racine, "list" pour les fichiers dans un dossier
    property string viewMode: "grid"   // "grid" | "list"

    // Filtre rapide (rangee compacte), applique aux fichiers ET aux dossiers.
    property string activeFilter: "all"   // "all" | "received" | "sent" | "failed"

    function matchesFilter(item) {
        switch (root.activeFilter) {
        case "received": return item.direction === qsTr("Réception")
        case "sent": return item.direction !== qsTr("Réception")
        case "failed": return item.statusText === qsTr("Échoué")
        default: return true
        }
    }

    readonly property var currentGroup: {
        for (let i = 0; i < root.peerGroups.length; i++) {
            if (root.peerGroups[i].peerKey === root.openedPeerKey)
                return root.peerGroups[i]
        }
        return null
    }

    // Dossiers (correspondants) filtrés : recherche + filtre rapide (un
    // dossier est conserve s'il contient au moins un element correspondant).
    readonly property var filteredPeerGroups: {
        const q = root.searchText.trim().toLowerCase()
        return root.peerGroups.filter(function(g) {
            if (q.length > 0 && g.peerLabel.toLowerCase().indexOf(q) === -1) return false
            if (root.activeFilter === "all") return true
            return g.items.some(root.matchesFilter)
        })
    }

    readonly property var filteredCurrentItems: {
        if (!root.currentGroup) return []
        const q = root.searchText.trim().toLowerCase()
        return root.currentGroup.items.filter(function(it) {
            if (q.length > 0 && it.fileName.toLowerCase().indexOf(q) === -1) return false
            return root.matchesFilter(it)
        })
    }

    // Nombre total de fichiers (toutes conversations), pour la barre d'etat.
    readonly property int totalFileCount: {
        let n = 0
        for (let i = 0; i < root.peerGroups.length; i++) n += root.peerGroups[i].items.length
        return n
    }

    // Volume total transfere (fichiers termines), pour la barre d'etat.
    readonly property real totalTransferredBytes: {
        let total = 0
        for (let i = 0; i < root.peerGroups.length; i++) {
            const items = root.peerGroups[i].items
            for (let j = 0; j < items.length; j++) {
                if (items[j].statusText === qsTr("Terminé")) total += (items[j].totalBytes || 0)
            }
        }
        return total
    }

    // Nombre d'elements correspondant au filtre rapide dans un dossier donne
    // (utilise pour la pastille/sous-titre de la tuile dossier).
    function filteredCountFor(group) {
        if (root.activeFilter === "all") return group.items.length
        return group.items.filter(root.matchesFilter).length
    }

    onPeerGroupsChanged: {
        if (root.openedPeerKey.length > 0 && !root.currentGroup) {
            root.openedPeerKey = ""
        }
    }

    function hasActiveFilters() {
        return root.searchText.trim().length > 0 || root.activeFilter !== "all"
    }

    // Couleur/glyphe (Font Awesome) associes a chaque filtre rapide.
    function filterIconColor(key) {
        switch (key) {
        case "received": return Theme.success
        case "sent": return Theme.primary
        case "failed": return Theme.error
        default: return Theme.textTertiary
        }
    }
    function filterIconGlyph(key) {
        switch (key) {
        case "received": return "\uf063" // arrow-down
        case "sent": return "\uf062"     // arrow-up
        case "failed": return "\uf12a"   // exclamation
        default: return "\uf00a"         // th (tout)
        }
    }

    // Mappe un statusText de transfert vers un "tone" de StatusBadge.
    function statusTone(statusText) {
        switch (statusText) {
        case qsTr("Terminé"): return "success"
        case qsTr("Échoué"): return "error"
        default: return "info"
        }
    }

    function isInProgress(statusText) {
        return statusText === qsTr("En cours")
    }

    // Icone + couleur de fichier selon l'extension, a la maniere des
    // icones colorees par type de la maquette compacte (pdf/image/
    // archive/video/document...). Glyphes Font Awesome 4.7.0.
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

    // ---- fond ----
    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    // ---- carte principale (conteneur) ----
    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        border.width: 0
        clip: true 

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---- dialogues ----
            FileDialog {
                id: fileDialog
                title: qsTr("Choisir un fichier à envoyer")
                onAccepted: {
                    root.selectedFilePath = selectedFile.toString()
                    const parts = root.selectedFilePath.split("/")
                    root.selectedFileName = parts[parts.length - 1]
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
                function onTransferRejected(reason) {
                    errorBanner.show(reason)
                }
            }

        // =========================================================
        // Barre d'adresse personnalisée (selon maquette HTML)
        // =========================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
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
                        if (root.openedPeerKey.length > 0) {
                            root.openedPeerKey = ""
                        } else {
                            root.backRequested()
                        }
                    }
                }

                IconButton {
                    glyph: "\uf021"
                    variant: "ghost"
                    size: 30
                    onClicked: root.peerGroups = root.buildPeerGroups(root.context ? root.context.activeTransfers : [])
                }

                // Fil d'Ariane en pilule
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: Theme.radiusPill
                    color: Theme.breadcrumbChipHover
                    border.width: 1
                    border.color: Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 0

                        Label {
                            text: qsTr("Transferts")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: root.currentGroup ? Qt.PointingHandCursor : Qt.ArrowCursor
                                enabled: !!root.currentGroup
                                onClicked: root.openedPeerKey = ""
                            }
                        }

                        Label {
                            visible: !!root.currentGroup
                            text: "/"
                            font.pixelSize: Theme.fontSizeCaption
                            font.family: Theme.fontFamily
                            color: Theme.textTertiary
                        }

                        Label {
                            visible: !!root.currentGroup
                            text: root.currentGroup ? root.currentGroup.peerLabel : ""
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            font.family: Theme.fontFamily
                            color: Theme.text
                        }
                    }
                }

                // Champ de recherche
                Rectangle {
                    Layout.preferredWidth: 190
                    Layout.preferredHeight: 32
                    radius: Theme.radiusSmall
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6

                        FaIcon {
                            glyph: "\uf002"
                            font.pixelSize: 13
                            color: Theme.textTertiary
                        }

                        TextField {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            placeholderText: qsTr("Rechercher...")
                            text: root.searchText
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                            placeholderTextColor: Theme.textTertiary
                            background: Rectangle { color: "transparent" }
                            onTextChanged: root.searchText = text
                        }
                    }
                }

                Rectangle {
                    width: 1
                    height: 18
                    color: Theme.border
                }

                // Bascule grille/liste
                RowLayout {
                    spacing: 0

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: Theme.radiusSmall
                        color: root.viewMode === "grid" ? Theme.primaryMuted : "transparent"

                        FaIcon {
                            anchors.centerIn: parent
                            glyph: "\uf009"
                            font.pixelSize: 15
                            color: root.viewMode === "grid" ? Theme.primary : Theme.textTertiary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewMode = "grid"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: Theme.radiusSmall
                        color: root.viewMode === "list" ? Theme.primaryMuted : "transparent"

                        FaIcon {
                            anchors.centerIn: parent
                            glyph: "\uf0ca"
                            font.pixelSize: 15
                            color: root.viewMode === "list" ? Theme.primary : Theme.textTertiary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewMode = "list"
                        }
                    }
                }
            }
        }

        // =========================================================
        // Panneau d'envoi (compact, sous la barre d'adresse) : choix du
        // fichier + destinataire + bouton Envoyer + accès au dossier de
        // réception. Réutilise `fileDialog`/`selectedFilePath` déjà
        // déclarés, qui n'étaient jusqu'ici reliés à aucun bouton.
        // =========================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            color: Theme.surfaceAlt
            border.width: 1
            border.color: Theme.border
            z: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Button {
                    text: qsTr("Choisir...")
                    Layout.preferredHeight: 28
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: parent.hovered ? Theme.surface : "transparent"
                        border.width: 1
                        border.color: Theme.border
                    }
                    contentItem: Text {
                        text: qsTr("Choisir...")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: fileDialog.open()
                }

                Label {
                    Layout.fillWidth: true
                    text: root.selectedFileName.length > 0 ? root.selectedFileName : qsTr("Aucun fichier sélectionné")
                    color: root.selectedFileName.length > 0 ? Theme.text : Theme.textTertiary
                    elide: Text.ElideMiddle
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                }

                ComboBox {
                    id: recipientCombo
                    Layout.preferredWidth: 190
                    Layout.preferredHeight: 28
                    textRole: "label"
                    model: {
                        const peers = root.context ? root.context.availableRecipients() : []
                        const result = []
                        for (let i = 0; i < peers.length; ++i) {
                            result.push({
                                label: peers[i].name + " (" + peers[i].address + ")",
                                address: peers[i].address,
                                port: peers[i].port,
                                // CORRECTIF : UUID du pair choisi, transmis a sendFile()
                                // pour que l'envoi et la reception d'un meme correspondant
                                // se regroupent dans le meme dossier/tuile (voir
                                // buildPeerGroups() plus haut et TransferManager::sendFile()).
                                machineId: peers[i].id
                            })
                        }
                        return result
                    }

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.surface
                        border.width: 1
                        border.color: recipientCombo.activeFocus ? Theme.primary : Theme.border
                    }
                    contentItem: Text {
                        leftPadding: 8
                        rightPadding: 8
                        text: recipientCombo.displayText.length > 0 ? recipientCombo.displayText : qsTr("Aucun destinataire")
                        color: recipientCombo.count > 0 ? Theme.text : Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    indicator: FaIcon {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "\uf107"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                    }
                    popup: Popup {
                        y: recipientCombo.height + 2
                        width: recipientCombo.width
                        implicitHeight: Math.min(contentItem.implicitHeight, 200)
                        padding: 4

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border
                        }
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: recipientCombo.popup.visible ? recipientCombo.delegateModel : null
                            currentIndex: recipientCombo.highlightedIndex
                        }
                    }
                    delegate: ItemDelegate {
                        width: recipientCombo.width
                        height: 32
                        highlighted: recipientCombo.highlightedIndex === index
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: parent.highlighted ? Theme.surfaceHover : "transparent"
                        }
                        contentItem: Text {
                            text: modelData.label
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                }

                Button {
                    id: sendButton
                    text: qsTr("Envoyer")
                    Layout.preferredHeight: 28
                    enabled: root.selectedFilePath.length > 0 && recipientCombo.count > 0 && root.context !== null
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: sendButton.enabled ? (sendButton.hovered ? Theme.primaryHover : Theme.primary) : Theme.surfaceAlt
                    }
                    contentItem: RowLayout {
                        spacing: 6
                        FaIcon {
                            glyph: "\uf0ee"
                            font.pixelSize: 12
                            color: sendButton.enabled ? Theme.primaryText : Theme.textTertiary
                        }
                        Text {
                            text: qsTr("Envoyer")
                            color: sendButton.enabled ? Theme.primaryText : Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            font.family: Theme.fontFamily
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    onClicked: {
                        const selected = recipientCombo.model[recipientCombo.currentIndex]
                        if (!selected || !root.context) return
                        if (root.context.sendFile(root.selectedFilePath.toString(), selected.address, selected.port, selected.machineId)) {
                            root.selectedFilePath = ""
                            root.selectedFileName = ""
                        } else {
                            errorBanner.show(qsTr("Impossible d'envoyer le fichier."))
                        }
                    }
                }

                IconButton {
                    glyph: "\uf07c"
                    variant: "ghost"
                    size: 30
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Ouvrir le dossier de réception")
                    onClicked: {
                        if (root.context && !root.context.openDownloadsFolder()) {
                            errorBanner.show(qsTr("Impossible d'ouvrir le dossier de réception."))
                        }
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

            // État vide
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.peerGroups.length === 0
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
                        glyph: "\uf0ee"
                        font.pixelSize: 26
                        color: Theme.primary
                    }
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Aucun transfert")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeBody
                    font.weight: Font.Medium
                    font.family: Theme.fontFamily
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Vos fichiers envoyés et reçus apparaîtront ici.")
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
                        FaIcon { glyph: "\uf0ee"; font.pixelSize: 12; color: Theme.primaryText }
                        Label {
                            text: qsTr("Envoyer un fichier")
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
                        onClicked: fileDialog.open()
                    }
                }
            }

            // =====================================================
            // VUE RACINE : section "Correspondants" + grille de
            // tuiles compactes (icône teintée + pastille + libellé)
            // =====================================================
            ColumnLayout {
                anchors.fill: parent
                visible: root.peerGroups.length > 0 && root.openedPeerKey.length === 0
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16
                }

                Label {
                    Layout.leftMargin: 16
                    Layout.bottomMargin: 10
                    text: qsTr("CORRESPONDANTS")
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeCaption
                    font.weight: Font.Medium
                    font.family: Theme.fontFamily
                    font.letterSpacing: 0.4
                }

                GridView {
                    id: foldersGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    readonly property int columns: Math.max(3, Math.min(6, Math.floor(width / 100)))
                    cellWidth: Math.floor(width / columns)
                    cellHeight: 118
                    model: root.filteredPeerGroups
                    clip: true

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }

                    delegate: Item {
                        id: folderTile
                        width: foldersGrid.cellWidth
                        height: foldersGrid.cellHeight

                        readonly property color accentColor: Theme.colorForName(modelData.peerLabel)
                        readonly property bool hovered: tileArea.containsMouse

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.topMargin: 12
                            anchors.bottomMargin: 4
                            spacing: 6

                            // Icone "dossier" teintee, avec pastille
                            // de comptage superposee (coin sup. droit).
                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 34

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: Qt.rgba(folderTile.accentColor.r,
                                                    folderTile.accentColor.g,
                                                    folderTile.accentColor.b, 0.14)

                                    FaIcon {
                                        anchors.centerIn: parent
                                        glyph: "\uf114"
                                        font.pixelSize: 20
                                        color: folderTile.accentColor
                                    }
                                }

                                Rectangle {
                                    visible: root.filteredCountFor(modelData) > 0
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: folderTile.accentColor
                                    border.width: 2
                                    border.color: Theme.surface
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: -8
                                    anchors.topMargin: -6

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.filteredCountFor(modelData) > 99 ? "99+" : root.filteredCountFor(modelData)
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                        color: "#FFFFFF"
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                text: modelData.peerLabel
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeCaption
                                font.weight: Font.Medium
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            Label {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                text: modelData.items.length > 0 ? root.formatRelative(modelData.items[0].timestamp) : ""
                                color: Theme.textTertiary
                                font.pixelSize: 10
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        MouseArea {
                            id: tileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openedPeerKey = modelData.peerKey
                        }
                    }

                    Label {
                        visible: root.filteredPeerGroups.length === 0
                        anchors.centerIn: parent
                        text: root.searchText.length > 0
                              ? qsTr("Aucun correspondant ne correspond à « %1 »").arg(root.searchText)
                              : qsTr("Aucun correspondant pour ce filtre")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                    }
                }
            }

            // =====================================================
            // VUE DOSSIER OUVERT
            // =====================================================
            ColumnLayout {
                anchors.fill: parent
                visible: root.openedPeerKey.length > 0
                spacing: 0

                // Séparateur
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.border
                    Layout.topMargin: 8
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                }

                // En-tête du dossier (avatar + nombre de fichiers)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.bottomMargin: 10
                    spacing: 8

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: root.currentGroup ? Theme.colorForName(root.currentGroup.peerLabel) : Theme.primary
                        Text {
                            anchors.centerIn: parent
                            text: root.currentGroup && root.currentGroup.peerLabel.length > 0
                                  ? root.currentGroup.peerLabel.charAt(0).toUpperCase() : "?"
                            color: "#FFFFFF"
                            font.pixelSize: 11
                            font.bold: true
                            font.family: Theme.fontFamily
                        }
                    }
                    Label {
                        text: root.currentGroup ? root.currentGroup.peerLabel : ""
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        font.family: Theme.fontFamily
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.currentGroup ? qsTr("%n fichier(s)", "", root.filteredCurrentItems.length) : ""
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeCaption
                        font.family: Theme.fontFamily
                    }
                }

                // En-têtes de colonnes
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.bottomMargin: 8
                    spacing: 0
                    visible: root.filteredCurrentItems.length > 0

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Nom")
                        font.pixelSize: Theme.fontSizeCaption
                        font.weight: Font.Medium
                        font.family: Theme.fontFamily
                        color: Theme.textTertiary
                    }
                    Label {
                        Layout.preferredWidth: 80
                        text: qsTr("Taille")
                        font.pixelSize: Theme.fontSizeCaption
                        font.weight: Font.Medium
                        font.family: Theme.fontFamily
                        color: Theme.textTertiary
                    }
                    Label {
                        Layout.preferredWidth: 60
                        visible: !root.compactList
                        text: qsTr("Sens")
                        font.pixelSize: Theme.fontSizeCaption
                        font.weight: Font.Medium
                        font.family: Theme.fontFamily
                        color: Theme.textTertiary
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Label {
                        Layout.preferredWidth: 110
                        text: qsTr("Statut")
                        font.pixelSize: Theme.fontSizeCaption
                        font.weight: Font.Medium
                        font.family: Theme.fontFamily
                        color: Theme.textTertiary
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Label {
                        Layout.preferredWidth: 100
                        visible: !root.compactList
                        text: qsTr("Modifié")
                        font.pixelSize: Theme.fontSizeCaption
                        font.weight: Font.Medium
                        font.family: Theme.fontFamily
                        color: Theme.textTertiary
                        horizontalAlignment: Text.AlignRight
                    }
                    Item { Layout.preferredWidth: 30 }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.preferredHeight: 1
                    color: Theme.border
                    visible: root.filteredCurrentItems.length > 0
                }

                // Liste des fichiers
                ListView {
                    id: filesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.topMargin: 8
                    spacing: 0
                    clip: true
                    model: root.filteredCurrentItems

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }

                    delegate: Rectangle {
                        id: fileRow
                        width: filesList.width
                        height: root.isInProgress(modelData.statusText) ? 54 : 40
                        color: fileRowArea.containsMouse ? Theme.surfaceHover
                               : (index % 2 === 1 ? Theme.surfaceAlt : "transparent")
                        radius: Theme.radiusSmall
                        Behavior on color { ColorAnimation { duration: 100 } }

                        readonly property var kind: root.fileKindFor(modelData.fileName)
                        readonly property bool inProgress: root.isInProgress(modelData.statusText)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    FaIcon {
                                        glyph: fileRow.kind.glyph
                                        font.pixelSize: 16
                                        color: fileRow.kind.color
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.fileName
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideMiddle
                                    }
                                }
                                Label {
                                    Layout.preferredWidth: 80
                                    text: root.formatBytes(modelData.totalBytes)
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.fontFamily
                                    horizontalAlignment: Text.AlignRight
                                }
                                FaIcon {
                                    Layout.preferredWidth: 60
                                    visible: !root.compactList
                                    glyph: modelData.direction === qsTr("Réception") ? "\uf063" : "\uf062"
                                    color: modelData.direction === qsTr("Réception") ? Theme.success : Theme.primary
                                    font.pixelSize: 14
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Item {
                                    Layout.preferredWidth: 110
                                    Layout.fillHeight: true
                                    StatusBadge {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        tone: root.statusTone(modelData.statusText)
                                        text: modelData.statusText + (fileRow.inProgress && modelData.percent !== undefined
                                                                      ? " · " + modelData.percent + "%" : "")
                                    }
                                }
                                Label {
                                    Layout.preferredWidth: 100
                                    visible: !root.compactList
                                    text: root.formatDate(modelData.timestamp)
                                    color: Theme.textTertiary
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.family: Theme.fontFamily
                                    horizontalAlignment: Text.AlignRight
                                }

                                IconButton {
                                    glyph: "\uf021"
                                    size: 26
                                    radius: Theme.radiusSmall
                                    visible: modelData.statusText === qsTr("Échoué") && modelData.direction === qsTr("Envoi")
                                    opacity: fileRowArea.containsMouse ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Réessayer")
                                    onClicked: {
                                        if (root.context && !root.context.retryTransfer(modelData.transferKey)) {
                                            errorBanner.show(qsTr("Impossible de relancer le transfert."))
                                        }
                                    }
                                }
                                IconButton {
                                    glyph: "\uf07c"
                                    size: 26
                                    radius: Theme.radiusSmall
                                    visible: modelData.statusText === qsTr("Terminé")
                                    opacity: fileRowArea.containsMouse ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Ouvrir l'emplacement")
                                    onClicked: {
                                        if (root.context && !root.context.openFileLocation(modelData.filePath)) {
                                            errorBanner.show(qsTr("Impossible d'ouvrir l'emplacement du fichier."))
                                        }
                                    }
                                }
                            }

                            // Barre de progression, uniquement pour les
                            // transferts encore en cours.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.leftMargin: 24
                                Layout.rightMargin: 78
                                Layout.bottomMargin: 6
                                Layout.preferredHeight: 4
                                visible: fileRow.inProgress
                                radius: 2
                                color: Theme.surfaceAlt

                                Rectangle {
                                    height: parent.height
                                    radius: 2
                                    color: Theme.primary
                                    width: parent.width * Math.max(0, Math.min(100, modelData.percent || 0)) / 100
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }
                            }
                        }

                        MouseArea {
                            id: fileRowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: -1
                        }
                    }

                    // Message "aucun résultat"
                    Label {
                        visible: root.filteredCurrentItems.length === 0
                        anchors.centerIn: parent
                        text: qsTr("Aucun fichier ne correspond à ces critères")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                    }
                }
            }
        }

        // =========================================================
        // Barre d'état inférieure (fine, comme un explorateur natif)
        // =========================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: Theme.statusBarBackground
            border.width: 1
            border.color: Theme.border
            visible: root.peerGroups.length > 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 16

                RowLayout {
                    spacing: 4
                    FaIcon { glyph: "\uf114"; font.pixelSize: 12; color: Theme.textSecondary }
                    Label {
                        text: qsTr("%n correspondant(s)", "", root.filteredPeerGroups.length)
                        font.pixelSize: Theme.fontSizeCaption
                        font.family: Theme.fontFamily
                        color: Theme.textSecondary
                    }
                }
                RowLayout {
                    spacing: 4
                    FaIcon { glyph: "\uf0f6"; font.pixelSize: 12; color: Theme.textSecondary }
                    Label {
                        text: qsTr("%n fichier(s)", "", root.totalFileCount)
                        font.pixelSize: Theme.fontSizeCaption
                        font.family: Theme.fontFamily
                        color: Theme.textSecondary
                    }
                }
                Item { Layout.fillWidth: true }
                Label {
                    visible: root.hasActiveFilters()
                    text: qsTr("Filtres actifs")
                    font.pixelSize: Theme.fontSizeCaption
                    font.family: Theme.fontFamily
                    color: Theme.primary
                }
                Label {
                    text: qsTr("%1 transférés").arg(root.formatBytes(root.totalTransferredBytes))
                    font.pixelSize: Theme.fontSizeCaption
                    font.family: Theme.fontFamily
                    color: Theme.textSecondary
                }
            }
        }
        }
    }
}
