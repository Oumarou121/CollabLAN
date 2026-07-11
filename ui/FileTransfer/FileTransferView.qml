import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes

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

                Label {
                    text: qsTr("Transferts")
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.text
                }

                // Etat vide.
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacingLarge
                    visible: transfersList.count === 0
                    spacing: Theme.spacingSmall

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Aucun transfert en cours")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeBody
                    }
                }

                ListView {
                    id: transfersList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.spacingSmall
                    clip: true
                    model: root.context ? root.context.activeTransfers : []

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }

                    delegate: Rectangle {
                        width: transfersList.width
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
                                        if (modelData.statusText === qsTr("Echoue") && modelData.errorString.length > 0) {
                                            return modelData.errorString
                                        }
                                        return qsTr("%1 / %2 (%3 %)")
                                            .arg(root.formatBytes(modelData.bytesTransferred))
                                            .arg(root.formatBytes(modelData.totalBytes))
                                            .arg(modelData.percent)
                                    }
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
