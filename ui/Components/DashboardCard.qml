import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * DashboardCard - carte d'acces rapide utilisee sur l'ecran d'accueil
 * pour presenter les modules disponibles (Chat, Users, Transfert, ...).
 *
 * Design revu (juillet) : bandeau colore avec badge d'icone, coin
 * "replie" façon dossier (signature partagee avec la carte de LoginView),
 * pied de carte avec titre/description et fleche d'acces.
 */
Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string description: ""

    signal clicked()

    readonly property color blue700: Theme.darkMode ? "#5B8FB0" : "#2A5C85"
    readonly property color blue600: Theme.darkMode ? "#79A8C6" : "#336F9E"
    readonly property color gold600: Theme.darkMode ? "#D6A94F" : "#B6862F"
    readonly property color paper: Theme.darkMode ? "#12151B" : "#EEF1EC"
    readonly property color chipIdle: Theme.darkMode ? "#232A35" : "#E4EDF3"

    Layout.preferredHeight: 190
    radius: Theme.radiusLarge
    color: Theme.surface
    border.width: 1
    border.color: mouseArea.containsMouse ? root.blue600 : Theme.border
    clip: true

    Behavior on border.color { ColorAnimation { duration: 120 } }
    scale: mouseArea.containsMouse ? 1.012 : 1.0
    Behavior on scale { NumberAnimation { duration: 120 } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Bandeau colore avec badge d'icone ----------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 100

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.blue600 }
                GradientStop { position: 1.0; color: root.blue700 }
            }

            // Cercle decoratif
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -26
                anchors.bottomMargin: -30
                width: 100
                height: 100
                radius: 50
                color: "#14ffffff"
            }

            // Badge d'icone
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spacingMedium
                width: 44
                height: 44
                radius: 22
                color: "#2effffff"
                border.width: 1
                border.color: "#48ffffff"

                Text {
                    anchors.centerIn: parent
                    text: root.icon
                    font.pixelSize: 19
                    color: "#ffffff"
                }
            }
        }

        // ---- Pied : titre + description + fleche --------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Theme.spacingMedium
            spacing: Theme.spacingSmall

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: Theme.fontSizeSubheading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                    elide: Text.ElideRight
                }

                Label {
                    Layout.fillWidth: true
                    text: root.description
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: mouseArea.containsMouse ? root.gold600 : root.chipIdle
                border.width: 1
                border.color: mouseArea.containsMouse ? root.gold600 : root.blue700
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "→"
                    color: mouseArea.containsMouse ? "#ffffff" : root.blue700
                    font.pixelSize: 13
                    font.bold: true
                }
            }
        }
    }

    // Repli de coin façon dossier
    Rectangle {
        width: 22
        height: 22
        rotation: 45
        color: root.paper
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -11
        anchors.rightMargin: -11
        z: 5
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
