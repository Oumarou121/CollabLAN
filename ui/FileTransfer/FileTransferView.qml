import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"

/*
 * FileTransferView - Écran "Transfert de fichiers" façon explorateur de
 * fichiers moderne et compact.
 *
 * Refonte v2 (design) :
 *   - Tous les styles utilisent desormais les jetons `Theme.*` (plus un
 *     seul hex code en dur) => le mode sombre fonctionne enfin sur cet
 *     ecran, comme partout ailleurs dans l'app.
 *   - Bouton d'envoi de fichier ("+ Envoyer") integre a la barre d'adresse,
 *     relie a `TransferContext.sendFile` + un selecteur de destinataire
 *     (le `FileDialog` existait deja mais n'etait jamais utilise).
 *   - Barre de progression reelle pour les transferts "En cours"
 *     (propriete `percent`, jusque-la ignoree par la vue).
 *   - `StatusBadge` reutilise au lieu d'un badge redessine a la main.
 *   - Tuiles "correspondants" et lignes de fichiers retravaillees
 *     (hover/elevation, avatar coherent avec le reste de l'app).
 *   - Etat vide illustre avec appel a l'action.
 */
Item {
    id: root

    property var context: (typeof transferContext !== "undefined") ? transferContext : null

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
            const key = rawAddress.length > 0
                        ? root.normalizePeerAddress(rawAddress)
                        : "__unknown__"

            if (!groupsByKey[key]) {
                groupsByKey[key] = {
                    peerKey: key,
                    peerLabel: (item.peerName && item.peerName.length > 0) ? item.peerName
                               : (rawAddress.length > 0) ? rawAddress
                               : qsTr("Correspondant inconnu"),
                    peerAddress: rawAddress,
                    items: [],
                    lastTimestampMs: 0
                }
                order.push(key)
            }

            const group = groupsByKey[key]
            if (item.peerName && item.peerName.length > 0) {
                group.peerLabel = item.peerName
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
    function filterLabel(key) {
        switch (key) {
        case "received": return qsTr("Reçus")
        case "sent": return qsTr("Envoyés")
        case "failed": return qsTr("Échoués")
        default: return qsTr("Tout")
        }
    }

    // Mappe un statusText de transfert vers un "tone" de StatusBadge.
    function statusTone(statusText) {
        switch (statusText) {
        case qsTr("Terminé"): return "success"
        case qsTr("Échoué"): return "error"
        case qsTr("En cours"): return "info"
        default: return "neutral"
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
            return { glyph: "\uf1c6", color: Theme.warning }
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
        id: card
        anchors.fill: parent
        color: Theme.surface
        border.width: 0
        border.color: Theme.border
        clip: true

        // ---- sélecteur de fichier + destinataire pour l'envoi ----
        FileDialog {
            id: fileDialog
            title: qsTr("Choisir un fichier à envoyer")
            onAccepted: recipientPicker.openFor(selectedFile.toString())
        }

        RecipientPicker {
            id: recipientPicker
            anchors.fill: parent
            recipients: root.context ? root.context.availableRecipients() : []
            onRecipientChosen: function(filePath, address, port) {
                if (!root.context || !root.context.sendFile(filePath, address, port)) {
                    errorBanner.show(qsTr("Impossible d'envoyer le fichier à ce correspondant."))
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---- bannière d'erreur ----
            Rectangle {
                id: errorBanner
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? errorLabel.implicitHeight + Theme.spacingMedium : 0
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
                    font.family: Theme.fontFamily
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
            // Barre d'adresse
            // =========================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
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
                        size: 32
                        ToolTip.visible: hovered
                        ToolTip.text: root.openedPeerKey.length > 0 ? qsTr("Retour aux correspondants") : qsTr("Retour")
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
                        size: 32
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Actualiser")
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
                            spacing: 6

                            FaIcon {
                                glyph: "\uf114"
                                font.pixelSize: 13
                                color: Theme.textTertiary
                            }

                            Label {
                                text: qsTr("Transferts")
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                color: root.currentGroup ? Theme.textSecondary : Theme.text
                                font.weight: root.currentGroup ? Font.Normal : Font.Medium

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
                                color: Theme.textTertiary
                            }

                            Label {
                                visible: !!root.currentGroup
                                text: root.currentGroup ? root.currentGroup.peerLabel : ""
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                font.weight: Font.Medium
                                color: Theme.text
                                elide: Text.ElideRight
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
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                color: Theme.text
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

                    Rectangle {
                        width: 1
                        height: 18
                        color: Theme.border
                    }

                    // Bouton principal d'envoi de fichier
                    Rectangle {
                        Layout.preferredHeight: 32
                        Layout.preferredWidth: sendRow.implicitWidth + 24
                        radius: Theme.radiusSmall
                        color: sendArea.pressed ? Theme.primaryHover : Theme.primary

                        RowLayout {
                            id: sendRow
                            anchors.centerIn: parent
                            spacing: 6
                            FaIcon {
                                glyph: "\uf0ee"
                                font.pixelSize: 13
                                color: Theme.primaryText
                            }
                            Label {
                                text: qsTr("Envoyer")
                                color: Theme.primaryText
                                font.pixelSize: Theme.fontSizeCaption
                                font.weight: Font.Medium
                                font.family: Theme.fontFamily
                            }
                        }

                        MouseArea {
                            id: sendArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fileDialog.open()
                        }
                    }
                }
            }

            // =========================================================
            // Rangée de filtres rapides
            // =========================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                color: Theme.surface

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8

                    Repeater {
                        model: ["all", "received", "sent", "failed"]

                        Rectangle {
                            readonly property bool active: root.activeFilter === modelData
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: filterRow.implicitWidth + 20
                            radius: Theme.radiusPill
                            color: active ? Theme.primaryMuted : (filterArea.containsMouse ? Theme.surfaceHover : "transparent")
                            border.width: 1
                            border.color: active ? Theme.primary : Theme.border

                            RowLayout {
                                id: filterRow
                                anchors.centerIn: parent
                                spacing: 6
                                FaIcon {
                                    glyph: root.filterIconGlyph(modelData)
                                    font.pixelSize: 11
                                    color: active ? Theme.primary : root.filterIconColor(modelData)
                                }
                                Label {
                                    text: root.filterLabel(modelData)
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.family: Theme.fontFamily
                                    font.weight: active ? Font.Medium : Font.Normal
                                    color: active ? Theme.primary : Theme.textSecondary
                                }
                            }

                            MouseArea {
                                id: filterArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeFilter = modelData
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        visible: root.hasActiveFilters()
                        text: qsTr("Réinitialiser")
                        font.pixelSize: Theme.fontSizeCaption
                        font.family: Theme.fontFamily
                        color: Theme.primary

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.searchText = ""; root.activeFilter = "all" }
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
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 72
                        Layout.bottomMargin: Theme.spacingSmall
                        radius: 20
                        color: Theme.primaryMuted
                        FaIcon {
                            anchors.centerIn: parent
                            glyph: "\uf0ee"
                            font.pixelSize: 30
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
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: emptyCtaRow.implicitWidth + 28
                        radius: Theme.radiusSmall
                        color: emptyCtaArea.pressed ? Theme.primaryHover : Theme.primary

                        RowLayout {
                            id: emptyCtaRow
                            anchors.centerIn: parent
                            spacing: 6
                            FaIcon { glyph: "\uf0ee"; font.pixelSize: 13; color: Theme.primaryText }
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
                // tuiles compactes
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
                        readonly property int columns: Math.max(3, Math.min(6, Math.floor(width / 108)))
                        cellWidth: Math.floor(width / columns)
                        cellHeight: 128
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

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: Theme.radiusMedium
                                color: folderTile.hovered ? Theme.surfaceHover : "transparent"
                                border.width: folderTile.hovered ? 1 : 0
                                border.color: Theme.border
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.topMargin: 14
                                anchors.bottomMargin: 6
                                spacing: 6

                                // Avatar rond aux initiales, avec pastille
                                // de comptage superposee (coin sup. droit).
                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 44

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 22
                                        color: Qt.rgba(folderTile.accentColor.r,
                                                        folderTile.accentColor.g,
                                                        folderTile.accentColor.b, 0.16)

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.peerLabel.length > 0
                                                  ? modelData.peerLabel.charAt(0).toUpperCase() : "?"
                                            font.pixelSize: 16
                                            font.bold: true
                                            font.family: Theme.fontFamily
                                            color: folderTile.accentColor
                                        }
                                    }

                                    Rectangle {
                                        visible: root.filteredCountFor(modelData) > 0
                                        width: 17
                                        height: 17
                                        radius: 9
                                        color: folderTile.accentColor
                                        border.width: 2
                                        border.color: Theme.surface
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.rightMargin: -6
                                        anchors.topMargin: -4

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
                            width: 28
                            height: 28
                            radius: 14
                            color: root.currentGroup ? Theme.colorForName(root.currentGroup.peerLabel) : Theme.primary
                            Text {
                                anchors.centerIn: parent
                                text: root.currentGroup && root.currentGroup.peerLabel.length > 0
                                      ? root.currentGroup.peerLabel.charAt(0).toUpperCase() : "?"
                                color: "#FFFFFF"
                                font.pixelSize: 12
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
                        Rectangle {
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: sendToPeerRow.implicitWidth + 20
                            radius: Theme.radiusSmall
                            color: sendToPeerArea.containsMouse ? Theme.surfaceHover : "transparent"
                            border.width: 1
                            border.color: Theme.border

                            RowLayout {
                                id: sendToPeerRow
                                anchors.centerIn: parent
                                spacing: 6
                                FaIcon { glyph: "\uf0ee"; font.pixelSize: 12; color: Theme.primary }
                                Label {
                                    text: qsTr("Envoyer à ce correspondant")
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.family: Theme.fontFamily
                                    color: Theme.primary
                                }
                            }
                            MouseArea {
                                id: sendToPeerArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    fileDialogForPeer.targetAddress = root.currentGroup ? root.currentGroup.peerAddress : ""
                                    fileDialogForPeer.open()
                                }
                            }
                        }
                    }

                    FileDialog {
                        id: fileDialogForPeer
                        property string targetAddress: ""
                        title: qsTr("Choisir un fichier à envoyer")
                        onAccepted: {
                            if (!root.context || targetAddress.length === 0) return
                            if (!root.context.sendFile(selectedFile.toString(), targetAddress, -1)) {
                                errorBanner.show(qsTr("Impossible d'envoyer le fichier à ce correspondant."))
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        Layout.preferredHeight: 1
                        color: Theme.border
                        visible: root.filteredCurrentItems.length > 0
                    }

                    // En-têtes de colonnes
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        Layout.topMargin: 8
                        Layout.bottomMargin: 6
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
                        Layout.topMargin: 6
                        spacing: 2
                        clip: true
                        model: root.filteredCurrentItems

                        add: Transition {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                        }

                        delegate: Rectangle {
                            id: fileRow
                            width: filesList.width
                            height: root.isInProgress(modelData.statusText) ? 52 : 42
                            color: fileRowArea.containsMouse ? Theme.surfaceHover
                                   : (index % 2 === 1 ? Theme.surfaceAlt : "transparent")
                            radius: Theme.radiusSmall
                            Behavior on color { ColorAnimation { duration: 100 } }

                            readonly property var kind: root.fileKindFor(modelData.fileName)

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
                                            text: modelData.statusText + (root.isInProgress(modelData.statusText) && modelData.percent !== undefined
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
                                                console.warn("Impossible de relancer le transfert")
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
                                                console.warn("Impossible d'ouvrir l'emplacement du fichier")
                                            }
                                        }
                                    }
                                }

                                // Barre de progression, uniquement pour les
                                // transferts encore en cours.
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 24
                                    Layout.rightMargin: 82
                                    Layout.bottomMargin: 6
                                    Layout.preferredHeight: 4
                                    visible: root.isInProgress(modelData.statusText)
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
