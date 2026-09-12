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
 *
 * Révision "design" (inspirée d'une maquette sidebar, sans reprendre sa
 * structure de navigation) :
 *   - Panneau d'envoi transformé en carte avec glisser-déposer de fichier.
 *   - Rangée de filtres rapides (Tout/Reçus/Envoyés/Échoués) enfin câblée
 *     à `activeFilter` (la logique existait déjà via `matchesFilter` mais
 *     n'avait aucun contrôle visible).
 *   - Tooltips sur les libellés tronqués (correspondants, fichiers).
 *   - Actions de ligne (réessayer/ouvrir) partiellement visibles par
 *     défaut au lieu d'apparaître seulement au survol.
 *   - Transition douce sur la hauteur des lignes de transfert en cours.
 *   - Petites retouches de cohérence (focus des champs, hover des
 *     boutons, couleur de texte de la bannière d'erreur).
 *
 * Correctifs UI (cette passe) :
 *   - Fil d'Ariane ("Transfert" / nom du dossier ouvert) : le RowLayout
 *     interne n'est plus en `anchors.fill: parent` (ce qui l'étirait sur
 *     toute la largeur de la pilule et créait un grand vide visuel entre
 *     les libellés). Il est maintenant ancré à gauche + centré
 *     verticalement, avec un `spacing` fixe entre "Transferts", "/" et le
 *     nom du correspondant. La pilule garde `Layout.fillWidth: true`.
 *   - `errorBanner` déplacé hors du `ColumnLayout` principal : c'était un
 *     item avec des ancres alors qu'il était géré par un layout ("Detected
 *     anchors on an item that is managed by a layout"), ce qui empêchait
 *     aussi `z: 10` de le faire flotter correctement par-dessus le
 *     contenu. Il est maintenant un frère direct du `ColumnLayout`, dans
 *     le `Rectangle` racine, où ses ancres sont valides.
 *
 * L'organisation (grille/liste des correspondants, ouverture d'un
 * correspondant, grille/liste des fichiers) et la logique métier ne sont
 * pas modifiées par cette passe.
 */
Item {
    id: root

    property var context: (typeof transferContext !== "undefined") ? transferContext : null

    property var selectedFilePaths: []
    property string selectedFolderPath: ""
    property var selectedRecipients: []

    function isRecipientSelected(machineId) {
        for (let i = 0; i < selectedRecipients.length; ++i) {
            if (selectedRecipients[i].machineId === machineId) return true
        }
        return false
    }

    function toggleRecipient(recipient) {
        const list = selectedRecipients.slice()
        const idx = list.findIndex(function(r) { return r.machineId === recipient.machineId })
        if (idx >= 0) {
            list.splice(idx, 1)
        } else {
            list.push(recipient)
        }
        selectedRecipients = list
    }

    // Sous ce seuil (fenetre partagee / petit ecran, minimum 640px pour
    // la fenetre entiere - cf. Main.qml), les colonnes secondaires de la
    // vue "Détails" (Sens, Date de modification) sont masquees.
    readonly property bool compactList: root.width < 900

    signal backRequested()

    // ---- fonctions utilitaires ----
    function fileNameFromPath(path) {
        const parts = path.split("/")
        return parts[parts.length - 1]
    }

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
                title: qsTr("Choisir un ou plusieurs fichiers à envoyer")
                fileMode: FileDialog.OpenFiles
                onAccepted: {
                    const paths = []
                    for (let i = 0; i < selectedFiles.length; ++i) {
                        paths.push(selectedFiles[i].toString())
                    }
                    root.selectedFilePaths = paths
                    root.selectedFolderPath = ""
                }
            }

            FolderDialog {
                id: sendFolderDialog
                title: qsTr("Choisir un dossier à envoyer")
                onAccepted: {
                    root.selectedFolderPath = selectedFolder.toString()
                    root.selectedFilePaths = []
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
                    radius: Theme.radiusSmall
                    color: Theme.breadcrumbChipHover
                    border.width: 1
                    border.color: Theme.border

                    RowLayout {
                        id: breadcrumbRow
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        // Pas de anchors.right : le row ne s'étire pas sur
                        // toute la largeur de la pilule, il ne prend que la
                        // place nécessaire à son contenu (évite le grand
                        // vide entre "Transferts" et le nom du dossier).
                        spacing: 6

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
                            elide: Text.ElideRight
                            Layout.maximumWidth: 220

                            ToolTip.visible: truncated && breadcrumbLabelArea.containsMouse
                            ToolTip.text: root.currentGroup ? root.currentGroup.peerLabel : ""
                            ToolTip.delay: 500

                            MouseArea {
                                id: breadcrumbLabelArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }
                    }
                }

                // Champ de recherche
                Item {
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
            }
        }

        // =========================================================
        // Panneau d'envoi (compact, sous la barre d'adresse) : choix du
        // fichier + destinataire + bouton Envoyer + accès au dossier de
        // réception. Réutilise `fileDialog`/`selectedFilePaths` déjà
        // déclarés.
        // =========================================================
        Rectangle {
            id: sendPanel
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingMedium
            Layout.rightMargin: Theme.spacingMedium
            Layout.topMargin: Theme.spacingMedium
            Layout.preferredHeight: 56
            radius: Theme.radiusSmall
            color: Theme.surfaceAlt
            border.width: 1
            border.color: sendDropArea.containsDrag ? Theme.primary : Theme.border
            Behavior on border.color { ColorAnimation { duration: 100 } }
            z: 1

            // Dépôt de fichier par glisser-déposer sur l'ensemble du panneau.
            DropArea {
                id: sendDropArea
                anchors.fill: parent
                onDropped: function(drop) {
                    if (drop.hasUrls && drop.urls.length > 0) {
                        const paths = []
                        for (let i = 0; i < drop.urls.length; ++i) {
                            paths.push(drop.urls[i].toString())
                        }
                        root.selectedFilePaths = paths
                        root.selectedFolderPath = ""
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingSmall

                // Sélecteur de fichier (clic ou glisser-déposer)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: Theme.radiusSmall
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        FaIcon {
                            glyph: "\uf0c6"
                            font.pixelSize: 13
                            color: Theme.textTertiary
                        }

                        Label {
                            id: sendFileLabel
                            Layout.fillWidth: true
                            text: sendDropArea.containsDrag
                                  ? qsTr("Déposez le(s) fichier(s) ici")
                                  : (root.selectedFolderPath.length > 0
                                     ? qsTr("Dossier : %1").arg(root.fileNameFromPath(root.selectedFolderPath))
                                     : (root.selectedFilePaths.length === 1
                                        ? root.fileNameFromPath(root.selectedFilePaths[0])
                                        : (root.selectedFilePaths.length > 1
                                           ? qsTr("%1 fichiers sélectionnés").arg(root.selectedFilePaths.length)
                                           : qsTr("Sélectionner ou déposer un ou plusieurs fichiers..."))))
                            color: sendDropArea.containsDrag ? Theme.primary
                                   : (root.selectedFilePaths.length > 0 || root.selectedFolderPath.length > 0 ? Theme.text : Theme.textTertiary)
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            elide: Text.ElideMiddle

                            ToolTip.visible: (truncated || root.selectedFilePaths.length > 1) && sendFileLabelArea.containsMouse
                            ToolTip.text: root.selectedFilePaths.map(root.fileNameFromPath).join("\n")
                            ToolTip.delay: 500

                            MouseArea {
                                id: sendFileLabelArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }

                        Label {
                            text: qsTr("DOSSIER")
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeCaption
                            font.weight: Font.Medium
                            font.family: Theme.fontFamily
                            font.letterSpacing: 0.3

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sendFolderDialog.open()
                            }
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
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: fileDialog.open()
                            }
                        }
                    }
                }

                Rectangle {
                    id: recipientPicker
                    Layout.preferredWidth: 190
                    Layout.preferredHeight: 34
                    radius: Theme.radiusSmall
                    color: Theme.surface
                    border.width: 1
                    border.color: recipientPopup.visible ? Theme.primary : Theme.border
                    Behavior on border.color { ColorAnimation { duration: 100 } }

                    // Selection multiple de destinataires (remplace le
                    // ComboBox a choix unique) : chaque pair coche est
                    // ajoute a root.selectedRecipients ; le bouton Envoyer
                    // boucle ensuite sur destinataires x fichiers.
                    readonly property var availableRecipients: {
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

                    readonly property string summaryText: {
                        if (root.selectedRecipients.length === 0) return qsTr("Aucun destinataire")
                        if (root.selectedRecipients.length === 1) return root.selectedRecipients[0].label
                        return qsTr("%1 destinataires").arg(root.selectedRecipients.length)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: recipientPicker.summaryText
                            color: root.selectedRecipients.length > 0 ? Theme.text : Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        FaIcon {
                            glyph: "\uf107"
                            color: Theme.textSecondary
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: recipientPopup.visible ? recipientPopup.close() : recipientPopup.open()
                    }

                    Popup {
                        id: recipientPopup
                        y: recipientPicker.height + 2
                        width: Math.max(recipientPicker.width, 220)
                        implicitHeight: Math.min(recipientListView.contentHeight + 8, 220)
                        padding: 4

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border
                        }

                        contentItem: ListView {
                            id: recipientListView
                            clip: true
                            implicitHeight: contentHeight
                            model: recipientPicker.availableRecipients
                            delegate: ItemDelegate {
                                width: recipientListView.width
                                height: 32

                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: parent.hovered ? Theme.surfaceHover : "transparent"
                                }

                                contentItem: RowLayout {
                                    spacing: 8
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 3
                                        color: root.isRecipientSelected(modelData.machineId) ? Theme.primary : "transparent"
                                        border.width: 1.5
                                        border.color: root.isRecipientSelected(modelData.machineId) ? Theme.primary : Theme.border

                                        Label {
                                            anchors.centerIn: parent
                                            text: "\u2713"
                                            visible: root.isRecipientSelected(modelData.machineId)
                                            color: Theme.primaryText
                                            font.pixelSize: 11
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                    }
                                }

                                onClicked: root.toggleRecipient(modelData)
                            }
                        }
                    }
                }

                Rectangle {
                    id: sendButton
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: 34
                    radius: Theme.radiusSmall
                    readonly property bool sendEnabled: (root.selectedFilePaths.length > 0 || root.selectedFolderPath.length > 0)
                                                         && root.selectedRecipients.length > 0 && root.context !== null
                    color: sendEnabled ? (sendButtonArea.containsMouse ? Theme.primaryHover : Theme.primary)
                                        : Theme.surface
                    border.width: sendEnabled ? 0 : 1
                    border.color: Theme.border
                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        FaIcon {
                            glyph: "\uf0ee"
                            font.pixelSize: 12
                            color: sendButton.sendEnabled ? Theme.primaryText : Theme.textTertiary
                        }
                        Text {
                            text: qsTr("Envoyer")
                            color: sendButton.sendEnabled ? Theme.primaryText : Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            font.family: Theme.fontFamily
                        }
                    }

                    MouseArea {
                        id: sendButtonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: sendButton.sendEnabled
                        cursorShape: sendButton.sendEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!root.context || root.selectedRecipients.length === 0) return

                            // Boucle destinataires x (fichiers ou dossier) :
                            // chaque combinaison est un appel sendFile()/
                            // sendFolder() distinct, chacun mis en file cote
                            // TransferService pour sa propre destination --
                            // aucun changement backend necessaire pour le
                            // multi-destinataires, comme pour le multi-fichiers.
                            let failedCount = 0
                            let totalAttempts = 0

                            for (let r = 0; r < root.selectedRecipients.length; ++r) {
                                const recipient = root.selectedRecipients[r]

                                if (root.selectedFolderPath.length > 0) {
                                    totalAttempts++
                                    const ok = root.context.sendFolder(root.selectedFolderPath, recipient.address, recipient.port, recipient.machineId)
                                    if (!ok) failedCount++
                                } else {
                                    for (let i = 0; i < root.selectedFilePaths.length; ++i) {
                                        totalAttempts++
                                        const ok = root.context.sendFile(root.selectedFilePaths[i], recipient.address, recipient.port, recipient.machineId)
                                        if (!ok) failedCount++
                                    }
                                }
                            }

                            if (failedCount === 0) {
                                root.selectedFilePaths = []
                                root.selectedFolderPath = ""
                            } else if (failedCount === totalAttempts) {
                                errorBanner.show(qsTr("Impossible d'envoyer le(s) fichier(s)."))
                            } else {
                                errorBanner.show(qsTr("%1 envoi(s) sur %2 ont échoué.").arg(failedCount).arg(totalAttempts))
                                root.selectedFilePaths = []
                                root.selectedFolderPath = ""
                            }
                        }
                    }
                }

                IconButton {
                    glyph: "\uf07c"
                    variant: "ghost"
                    size: 34
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
        // Rangée de filtres rapides (Tout, Reçus, Envoyés, Échoués) —
        // pilote `activeFilter`, déjà pris en compte par
        // `filteredPeerGroups`/`filteredCurrentItems` selon la vue active.
        // =========================================================
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingMedium
            Layout.rightMargin: Theme.spacingMedium
            Layout.topMargin: Theme.spacingSmall
            spacing: 6

            Repeater {
                model: [
                    { key: "all",      label: qsTr("Tout") },
                    { key: "received", label: qsTr("Reçus") },
                    { key: "sent",     label: qsTr("Envoyés") },
                    { key: "failed",   label: qsTr("Échoués") }
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
                    visible: root.viewMode === "grid"
                    readonly property int columns: Math.max(2, Math.min(4, Math.floor(width / 240)))
                    cellWidth: Math.floor(width / columns)
                    cellHeight: 168
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
                        readonly property var lastItem: modelData.items.length > 0 ? modelData.items[0] : null
                        readonly property var lastKind: folderTile.lastItem ? root.fileKindFor(folderTile.lastItem.fileName) : null
                        readonly property bool hovered: tileArea.containsMouse

                        Rectangle {
                            id: cardBg
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: 12
                            color: folderTile.hovered ? Theme.surfaceHover : Theme.surface
                            border.width: 1
                            border.color: folderTile.hovered ? folderTile.accentColor : Theme.border
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on color { ColorAnimation { duration: 120 } }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 8

                                // En-tête : avatar + nom + date relative + pastille de comptage
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        width: 40
                                        height: 40
                                        radius: 20
                                        color: Qt.rgba(folderTile.accentColor.r,
                                                        folderTile.accentColor.g,
                                                        folderTile.accentColor.b, 0.16)
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.peerLabel.length > 0 ? modelData.peerLabel.charAt(0).toUpperCase() : "?"
                                            color: folderTile.accentColor
                                            font.pixelSize: 16
                                            font.bold: true
                                            font.family: Theme.fontFamily
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Label {
                                            Layout.fillWidth: true
                                            text: modelData.peerLabel
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.DemiBold
                                            font.family: Theme.fontFamily
                                            elide: Text.ElideRight
                                            maximumLineCount: 1

                                            ToolTip.visible: truncated && folderTile.hovered
                                            ToolTip.text: modelData.peerLabel
                                            ToolTip.delay: 500
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: folderTile.lastItem ? root.formatRelative(folderTile.lastItem.timestamp) : ""
                                            color: Theme.textTertiary
                                            font.pixelSize: 10
                                            font.family: Theme.fontFamily
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }

                                    Rectangle {
                                        visible: root.filteredCountFor(modelData) > 0
                                        Layout.alignment: Qt.AlignTop
                                        implicitWidth: Math.max(20, countLabel.implicitWidth + 12)
                                        height: 20
                                        radius: 10
                                        color: Qt.rgba(folderTile.accentColor.r,
                                                        folderTile.accentColor.g,
                                                        folderTile.accentColor.b, 0.16)
                                        Text {
                                            id: countLabel
                                            anchors.centerIn: parent
                                            text: root.filteredCountFor(modelData) > 99 ? "99+" : root.filteredCountFor(modelData)
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.family: Theme.fontFamily
                                            color: folderTile.accentColor
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Theme.border
                                    opacity: 0.6
                                }

                                // Aperçu du dernier fichier échangé avec ce correspondant
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: !!folderTile.lastItem

                                    FaIcon {
                                        visible: !!folderTile.lastKind
                                        glyph: folderTile.lastKind ? folderTile.lastKind.glyph : ""
                                        color: folderTile.lastKind ? folderTile.lastKind.color : Theme.textSecondary
                                        font.pixelSize: 14
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: folderTile.lastItem ? folderTile.lastItem.fileName : ""
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideMiddle
                                        maximumLineCount: 1
                                    }
                                    Label {
                                        visible: !!folderTile.lastItem
                                        text: folderTile.lastItem ? root.formatBytes(folderTile.lastItem.totalBytes) : ""
                                        color: Theme.textTertiary
                                        font.pixelSize: 10
                                        font.family: Theme.fontFamily
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                // Pied de carte : statut du dernier transfert + chevron d'ouverture
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    StatusBadge {
                                        visible: !!folderTile.lastItem
                                        tone: folderTile.lastItem ? root.statusTone(folderTile.lastItem.statusText) : "info"
                                        text: folderTile.lastItem ? folderTile.lastItem.statusText : ""
                                    }

                                    Item { Layout.fillWidth: true }

                                    FaIcon {
                                        glyph: "\uf105"
                                        font.pixelSize: 13
                                        color: Theme.textTertiary
                                    }
                                }
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

                // Vue "liste" des correspondants (bascule grille/liste de la
                // barre d'adresse) : une ligne par correspondant, avec avatar,
                // nombre de fichiers filtrés et date relative du dernier échange.
                ListView {
                    id: foldersListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    visible: root.viewMode === "list"
                    spacing: 2
                    clip: true
                    model: root.filteredPeerGroups

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

                        readonly property color accentColor: Theme.colorForName(modelData.peerLabel)
                        readonly property var lastItem: modelData.items.length > 0 ? modelData.items[0] : null
                        readonly property var lastKind: folderRow.lastItem ? root.fileKindFor(folderRow.lastItem.fileName) : null

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: Qt.rgba(folderRow.accentColor.r,
                                                folderRow.accentColor.g,
                                                folderRow.accentColor.b, 0.16)

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.peerLabel.length > 0 ? modelData.peerLabel.charAt(0).toUpperCase() : "?"
                                    color: folderRow.accentColor
                                    font.pixelSize: 13
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.peerLabel
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight

                                    ToolTip.visible: truncated && folderRowArea.containsMouse
                                    ToolTip.text: modelData.peerLabel
                                    ToolTip.delay: 500
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    visible: !!folderRow.lastItem

                                    FaIcon {
                                        visible: !!folderRow.lastKind
                                        glyph: folderRow.lastKind ? folderRow.lastKind.glyph : ""
                                        color: folderRow.lastKind ? folderRow.lastKind.color : Theme.textTertiary
                                        font.pixelSize: 11
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: folderRow.lastItem ? folderRow.lastItem.fileName : ""
                                        color: Theme.textTertiary
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }

                            StatusBadge {
                                visible: !!folderRow.lastItem && !root.compactList
                                tone: folderRow.lastItem ? root.statusTone(folderRow.lastItem.statusText) : "info"
                                text: folderRow.lastItem ? folderRow.lastItem.statusText : ""
                            }

                            Label {
                                Layout.preferredWidth: 90
                                text: qsTr("%n fichier(s)", "", root.filteredCountFor(modelData))
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignRight
                            }

                            Label {
                                Layout.preferredWidth: 70
                                visible: !root.compactList
                                text: modelData.items.length > 0 ? root.formatRelative(modelData.items[0].timestamp) : ""
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
                    visible: root.viewMode === "list" && root.filteredCurrentItems.length > 0

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
                    visible: root.viewMode === "list" && root.filteredCurrentItems.length > 0
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
                    visible: root.viewMode === "list"
                    model: root.filteredCurrentItems

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }

                    delegate: Rectangle {
                        id: fileRow
                        width: filesList.width
                        height: root.isInProgress(modelData.statusText) ? 54 : 40
                        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
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

                                        ToolTip.visible: truncated && fileRowArea.containsMouse
                                        ToolTip.text: modelData.fileName
                                        ToolTip.delay: 500
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
                                    opacity: fileRowArea.containsMouse ? 1 : 0.45
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
                                    opacity: fileRowArea.containsMouse ? 1 : 0.45
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

                // Vue "grille d'icônes" des fichiers d'un correspondant
                // (bascule grille/liste de la barre d'adresse).
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
                    cellHeight: 112
                    clip: true
                    model: root.filteredCurrentItems

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }

                    delegate: Item {
                        id: fileTile
                        width: filesGrid.cellWidth
                        height: filesGrid.cellHeight

                        readonly property var kind: root.fileKindFor(modelData.fileName)
                        readonly property color kindColor: fileTile.kind.color
                        readonly property bool inProgress: root.isInProgress(modelData.statusText)
                        readonly property bool tileHovered: fileTileArea.containsMouse

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.topMargin: 12
                            anchors.bottomMargin: 4
                            spacing: 6

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 34

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: Qt.rgba(fileTile.kindColor.r,
                                                    fileTile.kindColor.g,
                                                    fileTile.kindColor.b, 0.14)

                                    FaIcon {
                                        anchors.centerIn: parent
                                        glyph: fileTile.kind.glyph
                                        font.pixelSize: 20
                                        color: fileTile.kind.color
                                    }
                                }

                                // Petit indicateur de statut (coin sup. droit),
                                // sur le meme principe que la pastille des
                                // tuiles de correspondants.
                                Rectangle {
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: modelData.statusText === qsTr("Terminé") ? Theme.success
                                           : (modelData.statusText === qsTr("Échoué") ? Theme.error : Theme.primary)
                                    border.width: 2
                                    border.color: Theme.surface
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: -6
                                    anchors.topMargin: -4
                                    visible: !fileTile.tileHovered
                                }

                                // Actions rapides (retry / ouvrir), affichées
                                // au survol à la place de la pastille de statut.
                                IconButton {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: -10
                                    anchors.topMargin: -8
                                    size: 22
                                    radius: Theme.radiusSmall
                                    visible: fileTile.tileHovered && modelData.statusText === qsTr("Échoué") && modelData.direction === qsTr("Envoi")
                                    glyph: "\uf021"
                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Réessayer")
                                    onClicked: {
                                        if (root.context && !root.context.retryTransfer(modelData.transferKey)) {
                                            errorBanner.show(qsTr("Impossible de relancer le transfert."))
                                        }
                                    }
                                }
                                IconButton {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: -10
                                    anchors.topMargin: -8
                                    size: 22
                                    radius: Theme.radiusSmall
                                    visible: fileTile.tileHovered && modelData.statusText === qsTr("Terminé")
                                    glyph: "\uf07c"
                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Ouvrir l'emplacement")
                                    onClicked: {
                                        if (root.context && !root.context.openFileLocation(modelData.filePath)) {
                                            errorBanner.show(qsTr("Impossible d'ouvrir l'emplacement du fichier."))
                                        }
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                text: modelData.fileName
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeCaption
                                font.weight: Font.Medium
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2

                                ToolTip.visible: truncated && fileTile.tileHovered
                                ToolTip.text: modelData.fileName
                                ToolTip.delay: 500
                            }
                            Label {
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                text: root.formatBytes(modelData.totalBytes)
                                    + (fileTile.inProgress && modelData.percent !== undefined ? " · " + modelData.percent + "%" : "")
                                color: Theme.textTertiary
                                font.pixelSize: 10
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        MouseArea {
                            id: fileTileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            z: -1
                        }
                    }

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

        // ---- bannière d'erreur ----
        // Frère direct du ColumnLayout (et non un enfant de celui-ci), pour
        // pouvoir utiliser des ancres librement et flotter par-dessus tout
        // le contenu via z: 10, sans provoquer le warning "Detected anchors
        // on an item that is managed by a layout".
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
                color: Theme.primaryText
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
    }
}
