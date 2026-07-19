import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"

/*
 * FileTransferView — redesign "Sidebar Layout" (Variant A).
 *
 * Structure :
 *   - Panneau gauche permanent (sidebarBackground, toujours sombre) :
 *       en-tête RÉSEAU LOCAL + retour, barre de recherche, liste des
 *       correspondants, pied "Mon Ordinateur".
 *   - Zone droite (suit le thème clair/sombre) :
 *       en-tête du correspondant sélectionné, carte "Nouvel envoi",
 *       filtres rapides, historique des transferts, barre d'état.
 *
 * Logique métier : 100 % conservée par rapport à la version précédente
 * (fonctions utilitaires, propriétés calculées, appels sur context,
 * error banner, FileDialog, signals).
 */
Item {
    id: root

    property var context: (typeof transferContext !== "undefined") ? transferContext : null

    property string selectedFilePath: ""
    property string selectedFileName: ""

    // Sous ce seuil les colonnes secondaires (Sens, Date) sont masquées.
    readonly property bool compactList: root.width < 900

    signal backRequested()

    // =========================================================
    // Fonctions utilitaires (inchangées)
    // =========================================================
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

    // =========================================================
    // Propriétés calculées (inchangées)
    // =========================================================
    property var peerGroups: root.buildPeerGroups(root.context ? root.context.activeTransfers : [])

    property string openedPeerKey: ""
    property string searchText: ""
    property string viewMode: "list"
    property string activeFilter: "all"

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

    readonly property int totalFileCount: {
        let n = 0
        for (let i = 0; i < root.peerGroups.length; i++) n += root.peerGroups[i].items.length
        return n
    }

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
        case "received": return "\uf063"
        case "sent": return "\uf062"
        case "failed": return "\uf12a"
        default: return "\uf00a"
        }
    }

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

    // =========================================================
    // Dialogue de sélection de fichier
    // =========================================================
    FileDialog {
        id: fileDialog
        title: qsTr("Choisir un fichier à envoyer")
        onAccepted: {
            root.selectedFilePath = selectedFile.toString()
            const parts = root.selectedFilePath.split("/")
            root.selectedFileName = parts[parts.length - 1]
        }
    }

    // =========================================================
    // Layout principal : sidebar gauche + contenu droit
    // =========================================================
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ==========================================================
        // SIDEBAR GAUCHE — toujours sombre (sidebarBackground)
        // ==========================================================
        Rectangle {
            Layout.preferredWidth: 288
            Layout.fillHeight: true
            color: Theme.sidebarBackground

            // Séparateur droite de la sidebar
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.sidebarBorder
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // --------------------------------------------------
                // En-tête sidebar
                // --------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    spacing: 8

                    // Bouton retour (quitte la vue)
                    Rectangle {
                        width: 28
                        height: 28
                        radius: Theme.radiusSmall
                        color: backBtnArea.containsMouse ? Theme.sidebarHover : "transparent"

                        FaIcon {
                            anchors.centerIn: parent
                            glyph: "\uf060"
                            font.pixelSize: 13
                            color: Theme.sidebarTextMuted
                        }

                        MouseArea {
                            id: backBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.backRequested()
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("RÉSEAU LOCAL")
                        color: Theme.sidebarText
                        font.pixelSize: Theme.fontSizeCaption
                        font.weight: Font.Bold
                        font.family: Theme.fontFamily
                        font.letterSpacing: 0.6
                    }

                    // Badge : nombre de correspondants en ligne
                    Rectangle {
                        visible: root.peerGroups.length > 0
                        Layout.preferredHeight: 20
                        width: onlineBadgeLabel.implicitWidth + 12
                        radius: Theme.radiusPill
                        color: Theme.sidebarHover

                        Label {
                            id: onlineBadgeLabel
                            anchors.centerIn: parent
                            text: qsTr("%1 en ligne").arg(root.peerGroups.length)
                            color: Theme.sidebarTextMuted
                            font.pixelSize: Theme.fontSizeCaption
                            font.family: Theme.fontFamily
                        }
                    }
                }

                // --------------------------------------------------
                // Barre de recherche
                // --------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.bottomMargin: 8
                    Layout.preferredHeight: 34
                    radius: Theme.radiusSmall
                    color: Theme.sidebarHover
                    border.width: 1
                    border.color: Theme.sidebarBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6

                        FaIcon {
                            glyph: "\uf002"
                            font.pixelSize: 12
                            color: Theme.sidebarTextMuted
                        }

                        TextField {
                            Layout.fillWidth: true
                            placeholderText: qsTr("Chercher un contact...")
                            text: root.searchText
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.sidebarText
                            placeholderTextColor: Theme.sidebarTextMuted
                            background: Rectangle { color: "transparent" }
                            onTextChanged: root.searchText = text
                        }
                    }
                }

                // --------------------------------------------------
                // Liste des correspondants
                // --------------------------------------------------
                ListView {
                    id: peerListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.filteredPeerGroups
                    spacing: 2

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: Theme.scrollbarThumb
                        }
                    }

                    // État vide (aucun correspondant)
                    Label {
                        visible: root.peerGroups.length === 0
                        anchors.centerIn: parent
                        width: parent.width - 32
                        text: qsTr("Aucun transfert pour l'instant.")
                        color: Theme.sidebarTextMuted
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    // Aucun résultat de recherche
                    Label {
                        visible: root.peerGroups.length > 0 && root.filteredPeerGroups.length === 0
                        anchors.centerIn: parent
                        width: parent.width - 32
                        text: qsTr("Aucun correspondant ne correspond à « %1 »").arg(root.searchText)
                        color: Theme.sidebarTextMuted
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    delegate: Rectangle {
                        id: peerItem
                        width: peerListView.width - 16
                        x: 8
                        height: 52
                        radius: Theme.radiusSmall
                        color: {
                            if (modelData.peerKey === root.openedPeerKey)
                                return Theme.sidebarActive
                            if (peerItemArea.containsMouse)
                                return Theme.sidebarHover
                            return "transparent"
                        }
                        Behavior on color { ColorAnimation { duration: 100 } }

                        readonly property color avatarColor: Theme.colorForName(modelData.peerLabel)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            // Avatar lettre
                            Rectangle {
                                width: 34
                                height: 34
                                radius: 17
                                color: Qt.rgba(peerItem.avatarColor.r,
                                               peerItem.avatarColor.g,
                                               peerItem.avatarColor.b, 0.25)

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.peerLabel.length > 0
                                          ? modelData.peerLabel.charAt(0).toUpperCase() : "?"
                                    color: peerItem.avatarColor
                                    font.pixelSize: Theme.fontSizeBody
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }

                                // Pastille en ligne (coin bas-droit)
                                Rectangle {
                                    width: 9
                                    height: 9
                                    radius: 5
                                    color: Theme.success
                                    border.width: 2
                                    border.color: Theme.sidebarBackground
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.rightMargin: -1
                                    anchors.bottomMargin: -1
                                }
                            }

                            // Nom + comptage
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.peerLabel
                                    color: Theme.sidebarText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Label {
                                    text: qsTr("%n fichier(s)", "", modelData.items.length)
                                    color: Theme.sidebarTextMuted
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.family: Theme.fontFamily
                                }
                            }

                            // Heure du dernier transfert
                            Label {
                                text: modelData.items.length > 0
                                      ? root.formatRelative(modelData.items[0].timestamp) : ""
                                color: Theme.sidebarTextMuted
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                            }
                        }

                        MouseArea {
                            id: peerItemArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openedPeerKey = modelData.peerKey
                        }
                    }
                }

                // --------------------------------------------------
                // Séparateur + pied "Mon Ordinateur"
                // --------------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.sidebarBorder
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: "#2A2F42"

                        FaIcon {
                            anchors.centerIn: parent
                            glyph: "\uf109"
                            font.pixelSize: 14
                            color: Theme.sidebarTextMuted
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: qsTr("Mon Ordinateur")
                            color: Theme.sidebarText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            font.family: Theme.fontFamily
                        }

                        RowLayout {
                            spacing: 4
                            Rectangle {
                                width: 7
                                height: 7
                                radius: 4
                                color: Theme.success
                            }
                            Label {
                                text: qsTr("Visible sur le LAN")
                                color: Theme.sidebarTextMuted
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }
            }
        }

        // ==========================================================
        // ZONE DROITE — suit le thème (clair / sombre)
        // ==========================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.background

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // --------------------------------------------------
                // Bannière d'erreur
                // --------------------------------------------------
                Rectangle {
                    id: errorBanner
                    Layout.fillWidth: true
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

                // --------------------------------------------------
                // État vide global (aucun correspondant, aucun transfert)
                // --------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.peerGroups.length === 0
                    spacing: Theme.spacingSmall

                    Item { Layout.fillHeight: true }

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

                    Item { Layout.fillHeight: true }
                }

                // --------------------------------------------------
                // Vue principale (correspondant sélectionné ou invitation)
                // --------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.peerGroups.length > 0
                    spacing: 0

                    // ---- Invite "choisir un correspondant" ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.openedPeerKey.length === 0
                        spacing: Theme.spacingSmall

                        Item { Layout.fillHeight: true }
                        FaIcon {
                            Layout.alignment: Qt.AlignHCenter
                            glyph: "\uf0c0"
                            font.pixelSize: 32
                            color: Theme.textTertiary
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Sélectionnez un correspondant")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeBody
                            font.family: Theme.fontFamily
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Choisissez un contact dans la liste pour voir ses transferts.")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                        }
                        Item { Layout.fillHeight: true }
                    }

                    // ---- Détail du correspondant ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.openedPeerKey.length > 0
                        spacing: 0

                        // En-tête correspondant
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            color: Theme.surface
                            border.width: 0

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Theme.border
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingMedium
                                anchors.rightMargin: Theme.spacingMedium
                                spacing: 10

                                // Avatar
                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 17
                                    color: root.currentGroup
                                           ? Theme.colorForName(root.currentGroup.peerLabel)
                                           : Theme.primary

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.currentGroup && root.currentGroup.peerLabel.length > 0
                                              ? root.currentGroup.peerLabel.charAt(0).toUpperCase() : "?"
                                        color: "#FFFFFF"
                                        font.pixelSize: 14
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Label {
                                        text: root.currentGroup ? root.currentGroup.peerLabel : ""
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSizeBody
                                        font.weight: Font.Medium
                                        font.family: Theme.fontFamily
                                    }

                                    Label {
                                        text: root.currentGroup
                                              ? qsTr("%n fichier(s) dans l'historique", "",
                                                     root.currentGroup.items.length)
                                              : ""
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.family: Theme.fontFamily
                                    }
                                }

                                // Bouton ouvrir dossier de réception
                                Rectangle {
                                    width: 30
                                    height: 30
                                    radius: Theme.radiusSmall
                                    color: openFolderArea.containsMouse ? Theme.surfaceHover : "transparent"

                                    FaIcon {
                                        anchors.centerIn: parent
                                        glyph: "\uf07c"
                                        font.pixelSize: 14
                                        color: Theme.textSecondary
                                    }

                                    ToolTip.visible: openFolderArea.containsMouse
                                    ToolTip.text: qsTr("Ouvrir le dossier de réception")

                                    MouseArea {
                                        id: openFolderArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.context && !root.context.openDownloadsFolder()) {
                                                errorBanner.show(qsTr("Impossible d'ouvrir le dossier de réception."))
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Carte "Nouvel envoi" ----
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.spacingMedium
                            Layout.rightMargin: Theme.spacingMedium
                            Layout.topMargin: Theme.spacingMedium
                            Layout.preferredHeight: sendPanelContent.implicitHeight + Theme.spacingMedium * 2
                            radius: Theme.radiusMedium
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border

                            ColumnLayout {
                                id: sendPanelContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingSmall

                                Label {
                                    text: qsTr("Nouvel envoi")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    font.family: Theme.fontFamily
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSmall

                                    // Sélecteur de destinataire
                                    ComboBox {
                                        id: recipientCombo
                                        Layout.preferredWidth: 200
                                        Layout.preferredHeight: 34
                                        textRole: "label"
                                        model: {
                                            const peers = root.context ? root.context.availableRecipients() : []
                                            const result = []
                                            for (let i = 0; i < peers.length; ++i) {
                                                result.push({
                                                    label: peers[i].name + " (" + peers[i].address + ")",
                                                    address: peers[i].address,
                                                    port: peers[i].port,
                                                    machineId: peers[i].id
                                                })
                                            }
                                            return result
                                        }

                                        background: Rectangle {
                                            radius: Theme.radiusSmall
                                            color: Theme.surfaceAlt
                                            border.width: 1
                                            border.color: recipientCombo.activeFocus ? Theme.primary : Theme.border
                                        }
                                        contentItem: Text {
                                            leftPadding: 10
                                            rightPadding: 24
                                            text: recipientCombo.displayText.length > 0
                                                  ? recipientCombo.displayText
                                                  : qsTr("Aucun destinataire")
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

                                    // Sélecteur de fichier
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
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
                                                glyph: "\uf0c6"
                                                font.pixelSize: 13
                                                color: Theme.textTertiary
                                            }

                                            Label {
                                                Layout.fillWidth: true
                                                text: root.selectedFileName.length > 0
                                                      ? root.selectedFileName
                                                      : qsTr("Sélectionner un fichier...")
                                                color: root.selectedFileName.length > 0
                                                       ? Theme.text : Theme.textTertiary
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.family: Theme.fontFamily
                                                elide: Text.ElideMiddle
                                            }

                                            Label {
                                                text: qsTr("PARCOURIR")
                                                color: Theme.primary
                                                font.pixelSize: Theme.fontSizeCaption
                                                font.weight: Font.Medium
                                                font.family: Theme.fontFamily
                                                font.letterSpacing: 0.3

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: fileDialog.open()
                                                }
                                            }
                                        }
                                    }

                                    // Bouton Envoyer
                                    Rectangle {
                                        id: sendBtn
                                        Layout.preferredWidth: 100
                                        Layout.preferredHeight: 34
                                        radius: Theme.radiusSmall
                                        color: {
                                            if (!sendBtnEnabled) return Theme.surfaceAlt
                                            return sendBtnArea.pressed ? Theme.primaryHover
                                                   : (sendBtnArea.containsMouse ? Theme.primaryHover : Theme.primary)
                                        }

                                        readonly property bool sendBtnEnabled:
                                            root.selectedFilePath.length > 0
                                            && recipientCombo.count > 0
                                            && root.context !== null

                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            FaIcon {
                                                glyph: "\uf0ee"
                                                font.pixelSize: 12
                                                color: sendBtn.sendBtnEnabled
                                                       ? Theme.primaryText : Theme.textTertiary
                                            }

                                            Text {
                                                text: qsTr("Envoyer")
                                                color: sendBtn.sendBtnEnabled
                                                       ? Theme.primaryText : Theme.textTertiary
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.Medium
                                                font.family: Theme.fontFamily
                                            }
                                        }

                                        MouseArea {
                                            id: sendBtnArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: sendBtn.sendBtnEnabled
                                                         ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            enabled: sendBtn.sendBtnEnabled
                                            onClicked: {
                                                const selected = recipientCombo.model[recipientCombo.currentIndex]
                                                if (!selected || !root.context) return
                                                if (root.context.sendFile(root.selectedFilePath.toString(),
                                                                          selected.address, selected.port,
                                                                          selected.machineId)) {
                                                    root.selectedFilePath = ""
                                                    root.selectedFileName = ""
                                                } else {
                                                    errorBanner.show(qsTr("Impossible d'envoyer le fichier."))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Filtres rapides ----
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.spacingMedium
                            Layout.rightMargin: Theme.spacingMedium
                            Layout.topMargin: Theme.spacingMedium
                            Layout.bottomMargin: Theme.spacingSmall
                            spacing: Theme.spacingSmall

                            Label {
                                text: qsTr("HISTORIQUE DES TRANSFERTS")
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                                font.weight: Font.Medium
                                font.family: Theme.fontFamily
                                font.letterSpacing: 0.4
                            }

                            Item { Layout.fillWidth: true }

                            Repeater {
                                model: [
                                    { key: "all",      label: qsTr("Tout") },
                                    { key: "received", label: qsTr("Reçus") },
                                    { key: "sent",     label: qsTr("Envoyés") },
                                    { key: "failed",   label: qsTr("Échoués") }
                                ]

                                delegate: Rectangle {
                                    height: 24
                                    width: filterChipLabel.implicitWidth + 16
                                    radius: Theme.radiusPill
                                    color: root.activeFilter === modelData.key
                                           ? Theme.primaryMuted : Theme.surfaceAlt
                                    border.width: 1
                                    border.color: root.activeFilter === modelData.key
                                                  ? Theme.primary : Theme.border

                                    Label {
                                        id: filterChipLabel
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: root.activeFilter === modelData.key
                                               ? Theme.primary : Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.weight: root.activeFilter === modelData.key
                                                     ? Font.Medium : Font.Normal
                                        font.family: Theme.fontFamily
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activeFilter = modelData.key
                                    }
                                }
                            }
                        }

                        // ---- Séparateur ----
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.spacingMedium
                            Layout.rightMargin: Theme.spacingMedium
                            Layout.preferredHeight: 1
                            color: Theme.border
                        }

                        // ---- En-têtes de colonnes ----
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.spacingMedium + 8
                            Layout.rightMargin: Theme.spacingMedium + 8
                            Layout.topMargin: 8
                            Layout.bottomMargin: 4
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
                                horizontalAlignment: Text.AlignRight
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
                            Item { Layout.preferredWidth: 64 }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.spacingMedium
                            Layout.rightMargin: Theme.spacingMedium
                            Layout.preferredHeight: 1
                            color: Theme.border
                            visible: root.filteredCurrentItems.length > 0
                        }

                        // ---- Liste des fichiers ----
                        ListView {
                            id: filesList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.leftMargin: Theme.spacingMedium
                            Layout.rightMargin: Theme.spacingMedium
                            Layout.topMargin: 4
                            spacing: 0
                            clip: true
                            model: root.filteredCurrentItems

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: 4
                                    radius: 2
                                    color: Theme.scrollbarThumb
                                }
                            }

                            add: Transition {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                            }

                            // Aucun résultat
                            Label {
                                visible: root.filteredCurrentItems.length === 0
                                anchors.centerIn: parent
                                text: qsTr("Aucun fichier ne correspond à ces critères")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
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
                                            color: modelData.direction === qsTr("Réception")
                                                   ? Theme.success : Theme.primary
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
                                                text: modelData.statusText
                                                      + (fileRow.inProgress && modelData.percent !== undefined
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

                                        // Actions au survol
                                        RowLayout {
                                            Layout.preferredWidth: 64
                                            spacing: 2
                                            opacity: fileRowArea.containsMouse ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 120 } }

                                            IconButton {
                                                glyph: "\uf021"
                                                size: 26
                                                radius: Theme.radiusSmall
                                                visible: modelData.statusText === qsTr("Échoué")
                                                         && modelData.direction === qsTr("Envoi")
                                                ToolTip.visible: hovered
                                                ToolTip.text: qsTr("Réessayer")
                                                onClicked: {
                                                    if (root.context
                                                            && !root.context.retryTransfer(modelData.transferKey)) {
                                                        errorBanner.show(qsTr("Impossible de relancer le transfert."))
                                                    }
                                                }
                                            }

                                            IconButton {
                                                glyph: "\uf07c"
                                                size: 26
                                                radius: Theme.radiusSmall
                                                visible: modelData.statusText === qsTr("Terminé")
                                                ToolTip.visible: hovered
                                                ToolTip.text: qsTr("Ouvrir l'emplacement")
                                                onClicked: {
                                                    if (root.context
                                                            && !root.context.openFileLocation(modelData.filePath)) {
                                                        errorBanner.show(qsTr("Impossible d'ouvrir l'emplacement du fichier."))
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Barre de progression (En cours)
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
                                            width: parent.width
                                                   * Math.max(0, Math.min(100, modelData.percent || 0)) / 100
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
                        }

                        // ---- Barre d'état ----
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            color: Theme.surfaceAlt
                            border.width: 1
                            border.color: Theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingMedium
                                anchors.rightMargin: Theme.spacingMedium
                                spacing: 16

                                RowLayout {
                                    spacing: 4
                                    FaIcon { glyph: "\uf0f6"; font.pixelSize: 11; color: Theme.textSecondary }
                                    Label {
                                        text: root.currentGroup
                                              ? qsTr("%n fichier(s)", "", root.filteredCurrentItems.length)
                                              : ""
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
        }
    }
}
