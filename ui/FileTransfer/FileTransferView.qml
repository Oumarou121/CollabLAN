import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"

/*
 * FileTransferView - ecran "FileTransfer" (issue #57).
 *
 * S'appuie sur "transferContext" (core::TransferContext, expose depuis
 * app/main.cpp) qui relie network::TransferService/core::TransferManager
 * a cette vue :
 *  - Selecteur de fichier (FileDialog) + choix du destinataire parmi les
 *    postes decouverts sur le reseau local (issue #9/#17).
 *  - Barre de progression en temps reel pour chaque transfert en cours,
 *    envoi comme reception (transferContext.activeTransfers, mis a jour a
 *    chaque signal transferProgress()).
 */
Item {
    id: root

    // Contexte optionnel : permet de charger cette vue dans un contexte de
    // preview/design sans que "transferContext" soit defini dans le
    // contexte racine (meme convention que UsersView.qml/model).
    property var context: (typeof transferContext !== "undefined") ? transferContext : null

    property string selectedFilePath: ""
    property string selectedFileName: ""

    signal backRequested()

    // Formatte une taille en octets en chaine lisible (Ko/Mo/Go).
    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) {
            return "0 Ko"
        }
        const units = ["o", "Ko", "Mo", "Go"]
        let value = bytes
        let unitIndex = 0
        while (value >= 1024 && unitIndex < units.length - 1) {
            value /= 1024
            unitIndex++
        }
        return (unitIndex === 0 ? value.toFixed(0) : value.toFixed(1)) + " " + units[unitIndex]
    }

    // Date/heure lisible pour une entree de transfert (ex. "12/07/2026 14:32").
    function formatDate(isoString) {
        if (!isoString)
            return ""
        const d = new Date(isoString)
        if (isNaN(d.getTime()))
            return ""
        return d.toLocaleString(Qt.locale(), "dd/MM/yyyy HH:mm")
    }

    // Normalise une adresse IP pour le regroupement par correspondant.
    // Une connexion ENTRANTE (reception) sur le socket serveur, qui ecoute
    // en double pile IPv4/IPv6, rapporte souvent l'adresse distante sous
    // forme IPv4-mappee en IPv6 (ex. "::ffff:192.168.1.5"), alors qu'un
    // envoi SORTANT vers ce meme poste utilise l'adresse IPv4 "nue"
    // (ex. "192.168.1.5"). Sans normalisation, ces deux formes produisent
    // 2 cles differentes et donc 2 dossiers distincts pour un seul et
    // meme correspondant (issue signalee : "2 dossiers differents pour
    // les memes echanges, un pour l'envoi et un pour la reception").
    // core::TransferContext::resolvePeerName() applique deja une
    // comparaison tolerante equivalente cote C++ pour resoudre le nom
    // affiche ; on applique ici la meme tolerance a la cle de regroupement.
    function normalizePeerAddress(address) {
        if (!address)
            return ""
        let a = address.trim().toLowerCase()
        const v4MappedPrefix = "::ffff:"
        if (a.indexOf(v4MappedPrefix) === 0) {
            a = a.substring(v4MappedPrefix.length)
        }
        return a
    }

    // Regroupe la liste plate activeTransfers par correspondant (adresse IP
    // comme cle stable, nom affiche quand connu), le correspondant le plus
    // recemment actif en premier, et au sein de chaque groupe le transfert
    // le plus recent en premier. Recalcule automatiquement des que
    // context.activeTransfers change (propriete QML liee, voir plus bas).
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
            // Prefere le nom des qu'il devient connu (une entree recente
            // peut avoir un peerName resolu alors qu'une plus ancienne du
            // meme correspondant ne l'avait pas).
            if (item.peerName && item.peerName.length > 0) {
                group.peerLabel = item.peerName
            }
            // Prefere afficher la forme d'adresse la plus lisible
            // ("192.168.1.5" plutot que "::ffff:192.168.1.5") si aucun nom
            // n'est encore connu pour ce correspondant.
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

    property var peerGroups: root.buildPeerGroups(root.context ? root.context.activeTransfers : [])

    // --- Navigation par dossiers -------------------------------------
    // "" = on est a la racine (grille de dossiers, un par correspondant).
    // Sinon : peerKey du dossier actuellement ouvert (vue detail = liste
    // des fichiers echanges avec ce correspondant).
    property string openedPeerKey: ""
    property string searchText: ""

    readonly property var currentGroup: {
        for (let i = 0; i < root.peerGroups.length; i++) {
            if (root.peerGroups[i].peerKey === root.openedPeerKey)
                return root.peerGroups[i]
        }
        return null
    }

    // Dossiers (correspondants) filtres par la recherche, a la racine.
    readonly property var filteredPeerGroups: {
        const q = root.searchText.trim().toLowerCase()
        if (q.length === 0)
            return root.peerGroups
        return root.peerGroups.filter(function(g) {
            return g.peerLabel.toLowerCase().indexOf(q) !== -1
        })
    }

    // Fichiers du dossier ouvert, filtres par la recherche.
    readonly property var filteredCurrentItems: {
        if (!root.currentGroup)
            return []
        const q = root.searchText.trim().toLowerCase()
        if (q.length === 0)
            return root.currentGroup.items
        return root.currentGroup.items.filter(function(it) {
            return it.fileName.toLowerCase().indexOf(q) !== -1
        })
    }

    // Si le correspondant du dossier ouvert disparait (plus aucun
    // transfert) on revient automatiquement a la grille de dossiers.
    onPeerGroupsChanged: {
        if (root.openedPeerKey.length > 0 && !root.currentGroup) {
            root.openedPeerKey = ""
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    FileDialog {
        id: fileDialog
        title: qsTr("Choisir un fichier a envoyer")
        onAccepted: {
            root.selectedFilePath = selectedFile.toString()
            // selectedFile est une URL (file:///...) ; on garde uniquement
            // le nom pour l'affichage.
            const parts = root.selectedFilePath.split("/")
            root.selectedFileName = parts[parts.length - 1]
        }
    }

    // Message d'erreur transitoire (fichier illisible, adresse invalide,
    // envoi non demarre...).
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

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }

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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingMedium

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Button {
                text: qsTr("< Retour")
                Layout.preferredHeight: 32

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                    border.width: 1
                    border.color: Theme.border
                }

                contentItem: Text {
                    text: qsTr("< Retour")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: root.backRequested()
            }

            Label {
                text: qsTr("Transfert de fichiers")
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.text
            }

            Item { Layout.fillWidth: true }
        }

        // Panneau d'envoi : selection du fichier + du destinataire.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: sendPanel.implicitHeight + Theme.spacingLarge
            radius: Theme.radiusLarge
            color: Theme.surface
            border.color: Theme.border
            border.width: 1

            ColumnLayout {
                id: sendPanel
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Label {
                    text: qsTr("Envoyer un fichier")
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.text
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Button {
                        text: qsTr("Choisir un fichier...")
                        Layout.preferredHeight: 36

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: parent.hovered ? Theme.surfaceAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                        }

                        contentItem: Text {
                            text: qsTr("Choisir un fichier...")
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: fileDialog.open()
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.selectedFileName.length > 0
                              ? root.selectedFileName
                              : qsTr("Aucun fichier selectionne")
                        color: root.selectedFileName.length > 0 ? Theme.text : Theme.textSecondary
                        elide: Text.ElideMiddle
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Label {
                        text: qsTr("Destinataire :")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    ComboBox {
                        id: recipientCombo
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
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
                    }

                    Button {
                        text: qsTr("Envoyer")
                        Layout.preferredHeight: 36
                        enabled: root.selectedFilePath.length > 0
                                 && recipientCombo.count > 0
                                 && root.context !== null

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: parent.enabled ? (parent.hovered ? Theme.primaryHover : Theme.primary)
                                                   : Theme.surfaceAlt
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
                            if (!selected || !root.context) {
                                return
                            }

                            // selectedFilePath est l'URL brute renvoyee par FileDialog
                            // (ex. "file:///C:/chemin/fichier.ext" sous Windows).
                            // TransferContext::sendFile() convertit lui-meme cette URL
                            // en chemin local via QUrl::toLocalFile(), qui gere
                            // correctement Windows et Linux (contrairement a un
                            // decoupage regex manuel ici, qui laissait un slash en
                            // trop devant la lettre de lecteur : "/C:/...").
                            if (root.context.sendFile(root.selectedFilePath.toString(), selected.address, selected.port)) {
                                root.selectedFilePath = ""
                                root.selectedFileName = ""
                            }
                        }
                    }
                }

                Label {
                    visible: recipientCombo.count === 0
                    text: qsTr("Aucun poste detecte pour le moment : ouvrez d'abord \"Postes connectes\".")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        // Suivi des transferts en cours (envoi et reception), issue #57 :
        // "L'utilisateur voit la progression exacte d'un transfert en cours".
        //
        // Organisation par dossiers : a la racine, un dossier par
        // correspondant (comme un explorateur d'archives) ; on ouvre un
        // dossier pour voir la liste des fichiers echanges avec lui. Fil
        // d'Ariane + recherche permettent de naviguer et filtrer, a la
        // maniere des ecrans d'archivage fournis en reference.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                // En-tete : fil d'Ariane (Transferts > Correspondant), recherche
                // et raccourci vers le dossier de reception.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    RowLayout {
                        spacing: 4

                        Label {
                            text: qsTr("Transferts")
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: root.openedPeerKey.length > 0 ? Theme.primary : Theme.text

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: root.openedPeerKey.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                enabled: root.openedPeerKey.length > 0
                                onClicked: root.openedPeerKey = ""
                            }
                        }

                        Label {
                            visible: root.openedPeerKey.length > 0
                            text: "\u203A"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeBody
                        }

                        Label {
                            visible: root.openedPeerKey.length > 0
                            text: root.currentGroup ? root.currentGroup.peerLabel : ""
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                            elide: Text.ElideRight
                        }
                    }

                    Item { Layout.fillWidth: true }

                    TextField {
                        id: searchField
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 32
                        placeholderText: root.openedPeerKey.length > 0
                                         ? qsTr("Rechercher un fichier...")
                                         : qsTr("Rechercher un correspondant...")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.text
                        text: root.searchText
                        onTextChanged: root.searchText = text

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.surfaceAlt
                            border.width: 1
                            border.color: searchField.activeFocus ? Theme.primary : Theme.border
                        }
                    }

                    // Ouvre directement le dossier ou CollabLAN enregistre
                    // les fichiers recus, sans depender d'un transfert
                    // particulier de la liste ci-dessous.
                    Button {
                        text: qsTr("Ouvrir le dossier de reception")
                        onClicked: {
                            if (root.context && !root.context.openDownloadsFolder()) {
                                console.warn("Impossible d'ouvrir le dossier de reception")
                            }
                        }
                    }
                }

                // Etat vide (aucun transfert du tout).
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacingLarge
                    visible: root.peerGroups.length === 0
                    spacing: Theme.spacingSmall

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Aucun transfert")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeBody
                    }
                }

                // --- Vue "racine" : grille de dossiers, un par correspondant ---
                ScrollView {
                    id: foldersScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    visible: root.peerGroups.length > 0 && root.openedPeerKey.length === 0
                    contentWidth: availableWidth

                    // ScrollView n'accepte qu'un seul enfant direct : la
                    // grille et le message "aucun resultat" sont donc
                    // regroupes dans un Item.
                    Item {
                        width: foldersScroll.availableWidth
                        height: Math.max(foldersGrid.height, root.filteredPeerGroups.length === 0 ? 80 : 0)

                        GridView {
                            id: foldersGrid
                            width: parent.width
                            height: Math.ceil(model.length / Math.max(1, Math.floor(width / cellWidth))) * cellHeight
                            interactive: false
                            cellWidth: 140
                            cellHeight: 132
                            model: root.filteredPeerGroups

                            add: Transition {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                            }

                            delegate: FolderTile {
                                width: foldersGrid.cellWidth
                                height: foldersGrid.cellHeight
                                label: modelData.peerLabel
                                count: modelData.items.length
                                accentColor: Theme.colorForName(modelData.peerLabel)
                                sublabel: modelData.items.length > 0
                                          ? root.formatDate(modelData.items[0].timestamp)
                                          : ""
                                onOpened: root.openedPeerKey = modelData.peerKey
                            }
                        }

                        // Aucun resultat pour la recherche en cours.
                        Label {
                            visible: root.filteredPeerGroups.length === 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: Theme.spacingLarge
                            text: qsTr("Aucun correspondant ne correspond a \u00ab %1 \u00bb").arg(root.searchText)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                // --- Vue "dossier ouvert" : fichiers echanges avec ce correspondant ---
                ListView {
                    id: filesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.spacingSmall
                    clip: true
                    visible: root.openedPeerKey.length > 0
                    model: root.filteredCurrentItems

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }

                    header: RowLayout {
                        width: filesList.width
                        visible: root.currentGroup !== null
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
                            text: root.currentGroup
                                  ? qsTr("%n fichier(s)", "", root.currentGroup.items.length)
                                  : ""
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    // Aucun resultat pour la recherche en cours a l'interieur du dossier.
                    Label {
                        visible: filesList.count === 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: Theme.spacingLarge
                        text: qsTr("Aucun fichier ne correspond a \u00ab %1 \u00bb").arg(root.searchText)
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    delegate: Rectangle {
                        width: filesList.width
                        height: transferDelegate.implicitHeight + Theme.spacingMedium
                        radius: Theme.radiusMedium
                        color: Theme.surfaceAlt

                        ColumnLayout {
                            id: transferDelegate
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSmall
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall

                                // Pastille de direction (envoi / reception).
                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 11
                                    color: modelData.direction === qsTr("Reception") ? Theme.accent : Theme.primary

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.direction === qsTr("Reception") ? "\u2193" : "\u2191"
                                        color: Theme.primaryText
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.fileName
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    elide: Text.ElideMiddle
                                }

                                Label {
                                    text: modelData.statusText
                                    color: modelData.statusText === qsTr("Echoue") ? Theme.error
                                           : modelData.statusText === qsTr("Termine") ? Theme.success
                                           : Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            ProgressBar {
                                id: progressBar
                                Layout.fillWidth: true
                                from: 0
                                to: 100
                                value: modelData.percent

                                background: Rectangle {
                                    implicitHeight: 8
                                    radius: 4
                                    color: Theme.border
                                }

                                contentItem: Item {
                                    implicitHeight: 8

                                    Rectangle {
                                        width: progressBar.visualPosition * parent.width
                                        height: parent.height
                                        radius: 4
                                        color: modelData.statusText === qsTr("Echoue") ? Theme.error : Theme.primary
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                Label {
                                    text: {
                                        const dateText = root.formatDate(modelData.timestamp)
                                        if (modelData.statusText === qsTr("Echoue") && modelData.errorString.length > 0) {
                                            return dateText.length > 0 ? (dateText + " \u2022 " + modelData.errorString) : modelData.errorString
                                        }
                                        const sizeText = qsTr("%1 / %2 (%3 %)")
                                            .arg(root.formatBytes(modelData.bytesTransferred))
                                            .arg(root.formatBytes(modelData.totalBytes))
                                            .arg(modelData.percent)
                                        return dateText.length > 0 ? (dateText + " \u2022 " + sizeText) : sizeText
                                    }
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                // Visible uniquement une fois le transfert
                                // termine : avant cela, le fichier de
                                // destination n'existe pas encore (ou n'est
                                // pas encore a son emplacement final).
                                Button {
                                    text: qsTr("Ouvrir l'emplacement")
                                    visible: modelData.statusText === qsTr("Termine")
                                    onClicked: {
                                        if (root.context && !root.context.openFileLocation(modelData.filePath)) {
                                            console.warn("Impossible d'ouvrir l'emplacement du fichier")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
