import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * RecipientPicker - petit panneau modal affiche par-dessus FileTransferView
 * une fois qu'un fichier a ete choisi via le FileDialog, pour demander a
 * qui l'envoyer (TransferContext::availableRecipients()).
 */
Item {
    id: root

    property var recipients: []
    property string pendingFilePath: ""
    readonly property string pendingFileName: {
        if (pendingFilePath.length === 0) return ""
        const parts = pendingFilePath.split("/")
        return parts[parts.length - 1]
    }

    signal recipientChosen(string filePath, string address, int port)

    visible: opacity > 0
    opacity: 0
    z: 50
    Behavior on opacity { NumberAnimation { duration: 120 } }

    function openFor(filePath) {
        root.pendingFilePath = filePath
        root.opacity = 1
    }
    function close() {
        root.opacity = 0
    }

    // voile
    Rectangle {
        anchors.fill: parent
        color: Theme.overlay
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        width: Math.min(360, root.width - 40)
        height: Math.min(420, contentCol.implicitHeight + 32)
        anchors.centerIn: parent
        radius: Theme.radiusMedium
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: qsTr("Envoyer à…")
                    font.pixelSize: Theme.fontSizeSubheading
                    font.weight: Font.Medium
                    font.family: Theme.fontFamily
                    color: Theme.text
                }
                IconButton {
                    glyph: "\uf00d"
                    variant: "ghost"
                    size: 26
                    onClicked: root.close()
                }
            }

            Label {
                Layout.fillWidth: true
                text: root.pendingFileName
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                font.family: Theme.fontFamily
                elide: Text.ElideMiddle
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            Label {
                Layout.fillWidth: true
                visible: root.recipients.length === 0
                text: qsTr("Aucun correspondant disponible sur le réseau.")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: root.recipients.length > 0
                model: root.recipients
                spacing: 2

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 44
                    radius: Theme.radiusSmall
                    color: rArea.containsMouse ? Theme.surfaceHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: Theme.colorForName(modelData.name || modelData.address || "")
                            Text {
                                anchors.centerIn: parent
                                text: (modelData.name && modelData.name.length > 0
                                       ? modelData.name.charAt(0) : "?").toUpperCase()
                                color: "#FFFFFF"
                                font.pixelSize: Theme.fs(12)
                                font.bold: true
                                font.family: Theme.fontFamily
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                text: modelData.name && modelData.name.length > 0 ? modelData.name : modelData.address
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Label {
                                visible: modelData.name && modelData.name.length > 0
                                text: modelData.address
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    MouseArea {
                        id: rArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.recipientChosen(root.pendingFilePath, modelData.address,
                                                  modelData.port !== undefined ? modelData.port : -1)
                            root.close()
                        }
                    }
                }
            }
        }
    }
}
