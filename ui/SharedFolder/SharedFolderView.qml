import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes

/*
 * SharedFolderView - liste des dossiers partages (Phase 11 de la
 * fonctionnalite "Shared Folder").
 *
 * Affiche les dossiers actifs (issus de sharedFoldersModel, mis a jour en
 * temps reel), permet d'en creer un nouveau (nom + selection d'un
 * dossier local via FolderDialog) et d'ouvrir l'historique de
 * synchronisation d'un dossier (SharedFolderDetailView.qml).
 */
Item {
    id: root

    property var model: (typeof sharedFoldersModel !== "undefined") ? sharedFoldersModel : null
    property var manager: (typeof sharedFolderManager !== "undefined") ? sharedFolderManager : null

    signal backRequested()
    signal folderOpened(int folderId, string folderName)

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Connections {
        target: root.manager
        function onFolderOperationFailed(reason) {
            errorLabel.text = reason
            errorLabel.visible = true
        }
        function onFolderCreated() {
            errorLabel.visible = false
            nameField.text = ""
            pathField.text = ""
        }
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Choisir un dossier a partager")
        onAccepted: {
            pathField.text = String(selectedFolder).replace("file://", "")
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
                text: qsTr("Dossiers partages")
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.text
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: countLabel.implicitWidth + Theme.spacingMedium
                Layout.preferredHeight: 28
                radius: height / 2
                color: Theme.surfaceAlt
                border.color: Theme.border
                border.width: 1

                Label {
                    id: countLabel
                    anchors.centerIn: parent
                    text: root.model ? qsTr("%n dossier(s)", "", root.model.count) : qsTr("0 dossier")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        // Formulaire de creation
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: creationLayout.implicitHeight + Theme.spacingMedium * 2
            radius: Theme.radiusLarge
            color: Theme.surface
            border.color: Theme.border
            border.width: 1

            ColumnLayout {
                id: creationLayout
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Label {
                    text: qsTr("Partager un nouveau dossier")
                    font.bold: true
                    color: Theme.text
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    TextField {
                        id: nameField
                        Layout.preferredWidth: 200
                        placeholderText: qsTr("Nom du dossier partage")
                    }

                    TextField {
                        id: pathField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Chemin local")
                        readOnly: true
                    }

                    Button {
                        text: qsTr("Parcourir...")
                        onClicked: folderDialog.open()
                    }

                    Button {
                        text: qsTr("Partager")
                        enabled: nameField.text.length > 0 && pathField.text.length > 0
                        onClicked: {
                            if (root.manager) {
                                // ownerId=1 : utilisateur admin par defaut (pas encore de
                                // session utilisateur propagee jusqu'a cette vue).
                                root.manager.createFolder(nameField.text, pathField.text, 1)
                            }
                        }
                    }
                }

                Label {
                    id: errorLabel
                    Layout.fillWidth: true
                    visible: false
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.spacingSmall
                visible: listView.count === 0
                width: parent.width * 0.7

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Aucun dossier partage pour le moment")
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.text
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    text: qsTr("Utilisez le formulaire ci-dessus pour partager un premier dossier avec les autres postes du reseau.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            ListView {
                id: listView
                anchors.fill: parent
                anchors.margins: Theme.spacingSmall
                spacing: Theme.spacingSmall
                clip: true
                model: root.model

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
                }

                delegate: Rectangle {
                    width: listView.width
                    height: 64
                    radius: Theme.radiusMedium
                    color: Theme.surfaceAlt

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.folderOpened(folderId, name)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMedium
                        anchors.rightMargin: Theme.spacingMedium
                        spacing: Theme.spacingMedium

                        Rectangle {
                            width: 36
                            height: 36
                            radius: 10
                            color: Theme.primary

                            Text {
                                anchors.centerIn: parent
                                text: "\uD83D\uDCC1"
                                font.pixelSize: 16
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                text: name
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Label {
                                text: localPath
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        Label {
                            text: qsTr("%n fichier(s)", "", fileCount)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }
        }
    }
}
