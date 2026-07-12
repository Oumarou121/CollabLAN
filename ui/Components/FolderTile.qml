import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * FolderTile - tuile "dossier" utilisee pour presenter une categorie
 * (ici : un correspondant de transfert de fichiers) sous forme de dossier
 * contenant des elements, a la maniere des interfaces d'archivage par
 * dossiers (icone de dossier + pastille de comptage + libelle + sous-
 * libelle). Reutilisable partout ou une organisation par dossiers a du
 * sens (Transferts, futurs ecrans de documents partages, etc.).
 */
Item {
    id: root

    property string label: ""
    property string sublabel: ""
    property int count: 0
    property color accentColor: Theme.primary
    property bool highlighted: false

    signal opened()

    implicitWidth: 132
    implicitHeight: 128

    Rectangle {
        id: hoverBg
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: mouseArea.containsMouse || root.highlighted ? Theme.surfaceHover : "transparent"
        border.width: root.highlighted ? 1 : 0
        border.color: Theme.primary

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingSmall
        spacing: 6

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 58
            Layout.preferredHeight: 46
            Layout.topMargin: 4

            // Onglet du dossier.
            Rectangle {
                x: 2
                y: 0
                width: 24
                height: 10
                radius: 3
                color: root.accentColor
            }

            // Corps du dossier.
            Rectangle {
                y: 7
                width: parent.width
                height: parent.height - 7
                radius: 7
                color: root.accentColor
                opacity: 0.9

                // Reflet discret pour un rendu moins plat.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                }
            }

            // Pastille de comptage (nombre de fichiers dans ce dossier).
            Rectangle {
                visible: root.count > 0
                width: 22
                height: 22
                radius: 11
                color: Theme.primary
                border.width: 2
                border.color: Theme.surface
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -8
                anchors.topMargin: -6

                Text {
                    anchors.centerIn: parent
                    text: root.count > 99 ? "99+" : root.count
                    font.pixelSize: 10
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.primaryText
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: root.label
            color: Theme.text
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
            font.family: Theme.fontFamily
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Label {
            Layout.fillWidth: true
            visible: root.sublabel.length > 0
            text: root.sublabel
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeCaption
            font.family: Theme.fontFamily
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.opened()
    }
}
