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
    property var currentFiles: []

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

    function openFolder(folderId, name) {
        root.openedFolderId = folderId
        root.openedFolderName = name
        root.refreshFiles()
    }

    function refreshFiles() {
        if (root.context && root.openedFolderId >= 0) {
            root.currentFiles = root.context.filesForFolder(root.openedFolderId)
        } else {
            root.currentFiles = []
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
            createDialog.localPath = selectedFolder.toString().replace("file://", "")
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
    }

    // ---- dialogue de création ----
    Dialog {
        id: createDialog
        title: qsTr("Nouveau dossier partagé")
        modal: true
        anchors.centerIn: parent
        width: 420
        standardButtons: Dialog.NoButton

        property string localPath: ""

        onOpened: {
            nameField.text = ""
            localPath = ""
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
                        if (root.context.createFolder(nameField.text.trim(), createDialog.localPath)) {
                            createDialog.close()
                        }
                    }
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
                    text: qsTr("Réindexer")
                    variant: "secondary"
                    onClicked: {
                        if (root.context) {
                            root.context.shareFolder(root.openedFolderId)
                            root.refreshFiles()
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
                        onOpened: root.openFolder(model.folderId, model.name)

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
            visible: root.openedFolderId >= 0
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
                    width: filesListView.width
                    height: 36
                    color: fileMouseArea.containsMouse ? Theme.surfaceHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingSmall
                        anchors.rightMargin: Theme.spacingSmall

                        Label {
                            Layout.fillWidth: true
                            text: modelData.relativePath
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
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
    }
}
