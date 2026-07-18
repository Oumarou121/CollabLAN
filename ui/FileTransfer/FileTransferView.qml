import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"

/*
 * FileTransferView - Écran "Transfert de fichiers" façon explorateur de
 * fichiers moderne (Windows 11 / Nautilus) :
 *   - Barre d'adresse : navigation (retour/actualiser) + fil d'Ariane
 *     cliquable + recherche + bascule grille/liste
 *   - Panneau latéral de filtres rapides (Tout, Reçus, Envoyés, Échoués)
 *   - Vue grille des correspondants (à la racine), chacun étant un "dossier"
 *   - Vue "Détails" (liste avec en-têtes de colonnes) ou grille d'icônes
 *     pour les fichiers d'un correspondant
 *   - Barre d'état fine en bas, comme dans un explorateur natif
 */
Item {
    id: root

    property var context: (typeof transferContext !== "undefined") ? transferContext : null

    property string selectedFilePath: ""
    property string selectedFileName: ""

    // Sous ce seuil (fenetre partagee / petit ecran, minimum 640px pour
    // la fenetre entiere - cf. Main.qml), les colonnes secondaires de la
    // vue "Détails" (Sens, Date de modification) sont masquees : a 640px
    // de large, une fois le panneau lateral de 168px et les colonnes
    // fixes (Taille/Sens/Statut/Date = ~360px) deduits, il ne restait
    // presque plus de place pour le nom du fichier.
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

    // Filtre rapide (panneau lateral), applique aux fichiers ET aux dossiers.
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

    // Couleur/glyphe (toujours des caracteres ASCII/BMP sûrs, jamais d'emoji
    // astral non garanti) associes a chaque filtre rapide du panneau lateral.
    function filterIconColor(key) {
        switch (key) {
        case "received": return Theme.accent
        case "sent": return Theme.primary
        case "failed": return Theme.error
        default: return Theme.textTertiary
        }
    }
    function filterIconGlyph(key) {
        switch (key) {
        case "received": return "\u2193"
        case "sent": return "\u2191"
        case "failed": return "!"
        default: return ""
        }
    }

    // ---- fond ----
    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

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

    // Petit bouton d'outils rond/carre reutilise dans la barre d'adresse.
    component ToolbarIconButton: Button {
        property string glyph: ""
        implicitWidth: 32
        implicitHeight: 32
        background: Rectangle {
            radius: Theme.radiusSmall
            color: parent.down ? Theme.surfaceHover : (parent.hovered ? Theme.breadcrumbChipHover : "transparent")
        }
        contentItem: Text {
            text: parent.glyph
            color: parent.enabled ? Theme.text : Theme.textTertiary
            font.pixelSize: Theme.fontSizeBody
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // ---- layout principal ----
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // =========================================================
        // Barre d'adresse (navigation + fil d'Ariane + recherche + vue)
        // =========================================================
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

                ToolbarIconButton {
                    glyph: "\u2190"
                    // Toujours actif : au niveau d'un dossier ouvert, revient a la
                    // liste des correspondants ; a la racine, quitte l'ecran (signal
                    // backRequested() ecoute par Main.qml pour revenir au Home).
                    onClicked: {
                        if (root.openedPeerKey.length > 0) {
                            root.openedPeerKey = ""
                        } else {
                            root.backRequested()
                        }
                    }
                }
                ToolbarIconButton {
                    glyph: "\u21bb"
                    onClicked: root.peerGroups = root.buildPeerGroups(root.context ? root.context.activeTransfers : [])
                }

                // ---- Fil d'Ariane, style barre d'adresse ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: Theme.radiusPill
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingSmall
                        anchors.rightMargin: Theme.spacingSmall
                        spacing: 2

                        Rectangle {
                            id: crumbRootChip
                            radius: Theme.radiusPill
                            color: root.openedPeerKey.length > 0 && crumbRootArea.containsMouse ? Theme.breadcrumbChipHover : "transparent"
                            implicitHeight: 24
                            implicitWidth: crumbRootLabel.implicitWidth + 20

                            Label {
                                id: crumbRootLabel
                                anchors.centerIn: parent
                                text: qsTr("Transferts")
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: root.openedPeerKey.length === 0
                                // Toujours une couleur pleine (jamais de texte teinte
                                // sur fond teinte) : segment courant en texte fort,
                                // segment cliquable en texte secondaire + soulignement
                                // au survol pour rester lisible dans les deux themes.
                                color: root.openedPeerKey.length === 0 ? Theme.text : Theme.textSecondary
                            }
                            Rectangle {
                                visible: root.openedPeerKey.length > 0 && crumbRootArea.containsMouse
                                anchors.left: crumbRootLabel.left
                                anchors.right: crumbRootLabel.right
                                anchors.bottom: crumbRootLabel.bottom
                                anchors.bottomMargin: -1
                                height: 1
                                color: Theme.textSecondary
                            }
                            MouseArea {
                                id: crumbRootArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.openedPeerKey.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                enabled: root.openedPeerKey.length > 0
                                onClicked: root.openedPeerKey = ""
                            }
                        }

                        Label {
                            visible: root.openedPeerKey.length > 0
                            text: "\u203A"
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Rectangle {
                            visible: root.openedPeerKey.length > 0
                            radius: Theme.radiusPill
                            color: "transparent"
                            implicitHeight: 24
                            implicitWidth: crumbPeerLabel.implicitWidth + 12
                            Layout.maximumWidth: 220

                            Label {
                                id: crumbPeerLabel
                                anchors.centerIn: parent
                                width: parent.implicitWidth - 12
                                text: root.currentGroup ? root.currentGroup.peerLabel : ""
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                color: Theme.text
                                elide: Text.ElideRight
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                // ---- Recherche ----
                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 32
                    radius: Theme.radiusPill
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: searchField.activeFocus ? Theme.primary : Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 4
                        Label {
                            text: "🔍"
                            font.pixelSize: 12
                            color: Theme.textSecondary
                        }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            placeholderText: root.openedPeerKey.length > 0
                                             ? qsTr("Rechercher un fichier...")
                                             : qsTr("Rechercher un correspondant...")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.text
                            placeholderTextColor: Theme.textTertiary
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.primaryText
                            background: Rectangle { color: "transparent" }
                            text: root.searchText
                            onTextChanged: root.searchText = text
                        }
                        ToolbarIconButton {
                            glyph: "\u2715"
                            visible: root.searchText.length > 0
                            implicitWidth: 22
                            implicitHeight: 22
                            onClicked: { searchField.text = ""; root.searchText = "" }
                        }
                    }
                }

                // ---- Bascule vue grille / liste ----
                Rectangle {
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: 64
                    radius: Theme.radiusSmall
                    color: Theme.surfaceAlt
                    border.width: 1
                    border.color: Theme.border
                    visible: root.openedPeerKey.length > 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 2
                        ToolbarIconButton {
                            id: gridToggleBtn
                            implicitWidth: 28
                            implicitHeight: 28
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: root.viewMode === "grid" ? Theme.primary : "transparent"
                            }
                            contentItem: Item {
                                readonly property color dotColor: root.viewMode === "grid" ? Theme.primaryText : Theme.text
                                Grid {
                                    anchors.centerIn: parent
                                    columns: 2
                                    rows: 2
                                    spacing: 3
                                    Repeater {
                                        model: 4
                                        Rectangle {
                                            width: 6
                                            height: 6
                                            radius: 1
                                            color: parent.parent.dotColor
                                        }
                                    }
                                }
                            }
                            onClicked: root.viewMode = "grid"
                        }
                        ToolbarIconButton {
                            id: listToggleBtn
                            implicitWidth: 28
                            implicitHeight: 28
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: root.viewMode === "list" ? Theme.primary : "transparent"
                            }
                            contentItem: Item {
                                readonly property color barColor: root.viewMode === "list" ? Theme.primaryText : Theme.text
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    Repeater {
                                        model: 3
                                        Rectangle {
                                            width: 14
                                            height: 2
                                            radius: 1
                                            color: parent.parent.barColor
                                        }
                                    }
                                }
                            }
                            onClicked: root.viewMode = "list"
                        }
                    }
                }
            }
        }

        // =========================================================
        // Panneau d'envoi (compact, sous la barre d'adresse)
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

                Label {
                    text: qsTr("Envoyer :")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textSecondary
                }

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
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: fileDialog.open()
                }

                Label {
                    Layout.fillWidth: true
                    text: root.selectedFileName.length > 0 ? root.selectedFileName : qsTr("Aucun fichier sélectionné")
                    color: root.selectedFileName.length > 0 ? Theme.text : Theme.textSecondary
                    elide: Text.ElideMiddle
                    font.pixelSize: Theme.fontSizeSmall
                }

                ComboBox {
                    id: recipientCombo
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 28
                    textRole: "label"
                    model: {
                        const peers = root.context ? root.context.availableRecipients() : []
                        const result = []
                        for (let i = 0; i < peers.length; ++i) {
                            result.push({
                                label: peers[i].name + " (" + peers[i].address + ")",
                                address: peers[i].address,
                                port: peers[i].port
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
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    indicator: Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u25BE"
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
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                }

                Button {
                    text: qsTr("Envoyer")
                    Layout.preferredHeight: 28
                    enabled: root.selectedFilePath.length > 0 && recipientCombo.count > 0 && root.context !== null
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: parent.enabled ? (parent.hovered ? Theme.primaryHover : Theme.primary) : Theme.surfaceAlt
                    }
                    contentItem: Text {
                        text: qsTr("Envoyer")
                        color: parent.enabled ? Theme.primaryText : Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        const selected = recipientCombo.model[recipientCombo.currentIndex]
                        if (!selected || !root.context) return
                        if (root.context.sendFile(root.selectedFilePath.toString(), selected.address, selected.port)) {
                            root.selectedFilePath = ""
                            root.selectedFileName = ""
                        }
                    }
                }

                Button {
                    text: qsTr("📂 Réception")
                    Layout.preferredHeight: 28
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: parent.hovered ? Theme.surface : "transparent"
                        border.width: 1
                        border.color: Theme.border
                    }
                    contentItem: Text {
                        text: qsTr("📂 Réception")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (root.context && !root.context.openDownloadsFolder()) {
                            console.warn("Impossible d'ouvrir le dossier de réception")
                        }
                    }
                }
            }
        }

        // =========================================================
        // Corps : panneau lateral de filtres + contenu
        // =========================================================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ---- Panneau lateral (filtres rapides, style "Acces rapide") ----
            // Utilise les jetons de surface "normaux" (qui suivent Theme.darkMode),
            // et non les jetons Theme.sidebar* qui sont volontairement fixes en
            // marine sombre pour la navigation globale de l'appli ailleurs dans
            // CollabLAN : ce panneau local doit basculer avec le theme clair/sombre.
            Rectangle {
                Layout.preferredWidth: 168
                Layout.fillHeight: true
                color: Theme.surfaceAlt
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSmall
                    spacing: 2

                    Label {
                        text: qsTr("ACCÈS RAPIDE")
                        color: Theme.textTertiary
                        font.pixelSize: Theme.fontSizeCaption
                        font.bold: true
                        Layout.topMargin: 4
                        Layout.bottomMargin: 4
                        Layout.leftMargin: 8
                    }

                    Repeater {
                        model: [
                            { key: "all", label: qsTr("Tout") },
                            { key: "received", label: qsTr("Reçus") },
                            { key: "sent", label: qsTr("Envoyés") },
                            { key: "failed", label: qsTr("Échoués") }
                        ]

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: Theme.radiusSmall
                            color: root.activeFilter === modelData.key ? Theme.selectionBackground
                                   : sidebarItemArea.containsMouse ? Theme.surfaceHover
                                   : "transparent"

                            // Liseré d'accent a gauche pour l'element actif (repere
                            // visuel supplementaire qui ne depend pas de la couleur
                            // de fond, donc reste visible dans les deux themes).
                            Rectangle {
                                visible: root.activeFilter === modelData.key
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 3
                                radius: 1.5
                                color: Theme.primary
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 8

                                // Pastille de couleur dessinee (jamais de glyphe de
                                // police non garanti) : indique la categorie du filtre.
                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: root.filterIconColor(modelData.key)
                                    opacity: modelData.key === "all" ? 0.55 : 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.filterIconGlyph(modelData.key)
                                        color: Theme.primaryText
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: root.activeFilter === modelData.key ? Theme.primary : Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: root.activeFilter === modelData.key
                                }
                            }

                            MouseArea {
                                id: sidebarItemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeFilter = modelData.key
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ---- Zone de contenu principal ----
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.surface
                border.width: 1
                border.color: Theme.border
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // ---- Corps (listes/grilles) ----
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // État vide
                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: root.peerGroups.length === 0
                            spacing: Theme.spacingSmall
                            Label {
                                text: qsTr("Aucun transfert")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeBody
                            }
                        }

                        // ---- VUE RACINE : grille de dossiers ----
                        GridView {
                            id: foldersGrid
                            anchors.fill: parent
                            anchors.margins: Theme.spacingMedium
                            visible: root.peerGroups.length > 0 && root.openedPeerKey.length === 0
                            cellWidth: 150
                            cellHeight: 144
                            model: root.filteredPeerGroups
                            clip: true

                            add: Transition {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                            }

                            delegate: FolderTile {
                                width: foldersGrid.cellWidth
                                height: foldersGrid.cellHeight
                                label: modelData.peerLabel
                                count: root.filteredCountFor(modelData)
                                accentColor: Theme.colorForName(modelData.peerLabel)
                                sublabel: modelData.items.length > 0 ? root.formatDate(modelData.items[0].timestamp) : ""
                                onOpened: root.openedPeerKey = modelData.peerKey
                            }

                            // Message "aucun résultat"
                            Label {
                                visible: root.filteredPeerGroups.length === 0
                                anchors.centerIn: parent
                                text: root.searchText.length > 0
                                      ? qsTr("Aucun correspondant ne correspond à « %1 »").arg(root.searchText)
                                      : qsTr("Aucun correspondant pour ce filtre")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        // ---- VUE DOSSIER OUVERT ----
                        ColumnLayout {
                            anchors.fill: parent
                            visible: root.openedPeerKey.length > 0
                            spacing: 0

                            // En-tête du dossier (avatar + nombre de fichiers)
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.margins: Theme.spacingMedium
                                Layout.bottomMargin: Theme.spacingSmall
                                spacing: Theme.spacingSmall

                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 16
                                    color: root.currentGroup ? Theme.colorForName(root.currentGroup.peerLabel) : Theme.primary
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.currentGroup && root.currentGroup.peerLabel.length > 0
                                              ? root.currentGroup.peerLabel.charAt(0).toUpperCase() : "?"
                                        color: Theme.primaryText
                                        font.pixelSize: 14
                                        font.bold: true
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: root.currentGroup ? qsTr("%n fichier(s)", "", root.filteredCurrentItems.length) : ""
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            // Liste ou grille des fichiers
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                // ---- Vue grille (fichiers en cartes) ----
                                GridView {
                                    id: filesGrid
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingMedium
                                    anchors.rightMargin: Theme.spacingMedium
                                    visible: root.viewMode === "grid"
                                    cellWidth: 140
                                    cellHeight: 128
                                    model: root.filteredCurrentItems
                                    clip: true

                                    add: Transition {
                                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                                    }

                                    delegate: Rectangle {
                                        width: filesGrid.cellWidth - 10
                                        height: filesGrid.cellHeight - 10
                                        radius: Theme.radiusSmall
                                        color: fileCardArea.containsMouse ? Theme.surfaceHover : "transparent"

                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingSmall
                                            spacing: 6

                                            FileIcon {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.topMargin: 2
                                                size: 40
                                                received: modelData.direction === qsTr("Réception")
                                                failed: modelData.statusText === qsTr("Échoué")
                                                accentColor: modelData.direction === qsTr("Réception") ? Theme.accent : Theme.primary
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.fileName
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: true
                                                color: Theme.text
                                                elide: Text.ElideMiddle
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                text: root.formatBytes(modelData.totalBytes)
                                                font.pixelSize: Theme.fontSizeCaption
                                                color: Theme.textSecondary
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            ProgressBar {
                                                id: filesGridProgress
                                                Layout.fillWidth: true
                                                from: 0
                                                to: 100
                                                value: modelData.percent
                                                background: Rectangle {
                                                    implicitHeight: 5
                                                    radius: 3
                                                    color: Theme.border
                                                }
                                                contentItem: Item {
                                                    implicitHeight: 5
                                                    Rectangle {
                                                        width: filesGridProgress.visualPosition * parent.width
                                                        height: parent.height
                                                        radius: 3
                                                        color: modelData.statusText === qsTr("Échoué") ? Theme.error : Theme.primary
                                                    }
                                                }
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.statusText
                                                font.pixelSize: Theme.fontSizeCaption
                                                color: modelData.statusText === qsTr("Échoué") ? Theme.error
                                                       : modelData.statusText === qsTr("Terminé") ? Theme.success
                                                       : Theme.textSecondary
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }

                                        MouseArea {
                                            id: fileCardArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                        }

                                        Button {
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.margins: 2
                                            width: 22
                                            height: 22
                                            visible: modelData.statusText === qsTr("Échoué") && modelData.direction === qsTr("Envoi")
                                            opacity: fileCardArea.containsMouse ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            background: Rectangle {
                                                radius: width / 2
                                                color: parent.hovered ? Theme.surface : Theme.surfaceHover
                                                border.width: 0
                                            }
                                            contentItem: Text {
                                                text: "↻"
                                                font.pixelSize: 13
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            ToolTip.visible: hovered
                                            ToolTip.text: qsTr("Réessayer")
                                            onClicked: {
                                                if (root.context && !root.context.retryTransfer(modelData.transferKey)) {
                                                    console.warn("Impossible de relancer le transfert")
                                                }
                                            }
                                        }
                                    }

                                    // Message "aucun résultat"
                                    Label {
                                        visible: root.filteredCurrentItems.length === 0
                                        anchors.centerIn: parent
                                        text: qsTr("Aucun fichier ne correspond à ces critères")
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                // ---- Vue liste ("Détails", comme un explorateur) ----
                                ColumnLayout {
                                    anchors.fill: parent
                                    visible: root.viewMode === "list"
                                    spacing: 0

                                    // En-tête de colonnes (barre grise, comme Explorer)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 32
                                        color: Theme.listHeaderBackground
                                        border.width: 1
                                        border.color: Theme.border
                                        visible: root.filteredCurrentItems.length > 0

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacingMedium
                                            anchors.rightMargin: Theme.spacingMedium
                                            spacing: Theme.spacingSmall

                                            Label {
                                                Layout.fillWidth: true
                                                text: qsTr("Nom")
                                                font.bold: true
                                                color: Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeCaption
                                            }
                                            Label {
                                                Layout.preferredWidth: 80
                                                text: qsTr("Taille")
                                                font.bold: true
                                                color: Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeCaption
                                                horizontalAlignment: Text.AlignRight
                                            }
                                            Label {
                                                Layout.preferredWidth: 60
                                                visible: !root.compactList
                                                text: qsTr("Sens")
                                                font.bold: true
                                                color: Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeCaption
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            Label {
                                                Layout.preferredWidth: 90
                                                text: qsTr("Statut")
                                                font.bold: true
                                                color: Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeCaption
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            Label {
                                                Layout.preferredWidth: 130
                                                visible: !root.compactList
                                                text: qsTr("Date de modification")
                                                font.bold: true
                                                color: Theme.textSecondary
                                                font.pixelSize: Theme.fontSizeCaption
                                                horizontalAlignment: Text.AlignRight
                                            }
                                            Item { Layout.preferredWidth: 36 }
                                        }
                                    }

                                    // Liste déroulante
                                    ListView {
                                        id: filesList
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 0
                                        clip: true
                                        model: root.filteredCurrentItems

                                        add: Transition {
                                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                                        }

                                        delegate: Rectangle {
                                            width: filesList.width
                                            height: 42
                                            color: fileRowArea.containsMouse ? Theme.surfaceHover : "transparent"

                                            Behavior on color { ColorAnimation { duration: 100 } }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.spacingMedium
                                                anchors.rightMargin: Theme.spacingMedium
                                                spacing: Theme.spacingSmall

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8
                                                    FileIcon {
                                                        size: 22
                                                        received: modelData.direction === qsTr("Réception")
                                                        failed: modelData.statusText === qsTr("Échoué")
                                                        accentColor: modelData.direction === qsTr("Réception") ? Theme.accent : Theme.primary
                                                    }
                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: modelData.fileName
                                                        color: Theme.text
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        elide: Text.ElideMiddle
                                                    }
                                                }
                                                Label {
                                                    Layout.preferredWidth: 80
                                                    text: root.formatBytes(modelData.totalBytes)
                                                    color: Theme.textSecondary
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                                Label {
                                                    Layout.preferredWidth: 60
                                                    visible: !root.compactList
                                                    text: modelData.direction === qsTr("Réception") ? "\u2193" : "\u2191"
                                                    color: modelData.direction === qsTr("Réception") ? Theme.accent : Theme.primary
                                                    font.pixelSize: Theme.fontSizeBody
                                                    font.bold: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                }
                                                Label {
                                                    Layout.preferredWidth: 90
                                                    text: modelData.statusText
                                                    color: modelData.statusText === qsTr("Échoué") ? Theme.error
                                                           : modelData.statusText === qsTr("Terminé") ? Theme.success
                                                           : Theme.textSecondary
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    horizontalAlignment: Text.AlignHCenter
                                                }
                                                Label {
                                                    Layout.preferredWidth: 130
                                                    visible: !root.compactList
                                                    text: root.formatDate(modelData.timestamp)
                                                    color: Theme.textSecondary
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    horizontalAlignment: Text.AlignRight
                                                }

                                                Button {
                                                    Layout.preferredWidth: 30
                                                    Layout.preferredHeight: 26
                                                    visible: modelData.statusText === qsTr("Échoué") && modelData.direction === qsTr("Envoi")
                                                    opacity: fileRowArea.containsMouse ? 1 : 0
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                    background: Rectangle {
                                                        radius: Theme.radiusSmall
                                                        color: parent.hovered ? Theme.surface : "transparent"
                                                        border.width: 0
                                                    }
                                                    contentItem: Text {
                                                        text: "↻"
                                                        font.pixelSize: 15
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    ToolTip.visible: hovered
                                                    ToolTip.text: qsTr("Réessayer")
                                                    onClicked: {
                                                        if (root.context && !root.context.retryTransfer(modelData.transferKey)) {
                                                            console.warn("Impossible de relancer le transfert")
                                                        }
                                                    }
                                                }
                                                Button {
                                                    Layout.preferredWidth: 30
                                                    Layout.preferredHeight: 26
                                                    visible: modelData.statusText === qsTr("Terminé")
                                                    opacity: fileRowArea.containsMouse ? 1 : 0
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                    background: Rectangle {
                                                        radius: Theme.radiusSmall
                                                        color: parent.hovered ? Theme.surface : "transparent"
                                                        border.width: 0
                                                    }
                                                    contentItem: Text {
                                                        text: "📂"
                                                        font.pixelSize: 13
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    onClicked: {
                                                        if (root.context && !root.context.openFileLocation(modelData.filePath)) {
                                                            console.warn("Impossible d'ouvrir l'emplacement du fichier")
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                height: 1
                                                color: Theme.border
                                                opacity: 0.6
                                            }

                                            MouseArea {
                                                id: fileRowArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                        }

                                        // Message "aucun résultat"
                                        Label {
                                            visible: root.filteredCurrentItems.length === 0
                                            anchors.centerIn: parent
                                            text: qsTr("Aucun fichier ne correspond à ces critères")
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // =========================================================
        // Barre d'état inférieure (fine, comme un explorateur natif)
        // =========================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            color: Theme.statusBarBackground
            border.width: 1
            border.color: Theme.border
            visible: root.peerGroups.length > 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingMedium

                Label {
                    text: qsTr("%1 dossier(s)").arg(root.filteredPeerGroups.length)
                    font.pixelSize: Theme.fontSizeCaption
                    color: Theme.textSecondary
                    visible: root.openedPeerKey.length === 0
                }
                Label {
                    text: qsTr("%1 fichier(s)").arg(root.filteredCurrentItems.length)
                    font.pixelSize: Theme.fontSizeCaption
                    color: Theme.textSecondary
                    visible: root.openedPeerKey.length > 0
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: root.hasActiveFilters() ? qsTr("🔍 Filtres actifs") : ""
                    font.pixelSize: Theme.fontSizeCaption
                    color: Theme.primary
                }
            }
        }
    }
}
