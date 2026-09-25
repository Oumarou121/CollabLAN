import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * DashboardHeader - Header selon la maquette HTML exacte
 * Height: 52px
 * Padding: 0 24px
 */
Item {
    id: root
    height: 52

    property string breadcrumb: "LocaLink / Vue d'ensemble"
    property bool showSearch: true
    property bool showNotifications: true

    // "LocaLink / Transferts / PC-COMPTA-01" -> ["LocaLink", "Transferts", "PC-COMPTA-01"]
    readonly property var breadcrumbParts: root.breadcrumb.split(" / ")

    signal searchRequested(string query)
    signal notificationsRequested()
    // Emis quand un segment non-final du fil d'Ariane est clique (ex.
    // "Transferts" dans "LocaLink / Transferts / PC-COMPTA-01"), pour
    // permettre a l'ecran hote de remonter d'un niveau (arborescence).
    signal segmentClicked(int index, string label)

    Rectangle {
        anchors.fill: parent
        color: "#EEF2F1"
        border.width: 1
        border.color: "#DDE4E2"
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 8

        // Breadcrumb - piloté par root.breadcrumb ("LocaLink / Transferts",
        // "LocaLink / Transferts / PC-COMPTA-01", ...) : seul le dernier
        // segment est mis en avant (gras, couleur texte principale).
        Row {
            spacing: 4

            Repeater {
                model: root.breadcrumbParts

                delegate: Row {
                    spacing: 4
                    readonly property bool isLast: index === root.breadcrumbParts.length - 1
                    readonly property bool crumbHovered: crumbHover.hovered

                    Label {
                        id: crumbLabel
                        text: modelData
                        color: isLast ? "#15222B" : (parent.crumbHovered ? "#15222B" : "#62717A")
                        font.pixelSize: 12
                        font.bold: isLast
                        font.underline: !isLast && parent.crumbHovered
                        font.family: Theme.fontFamily

                        HoverHandler {
                            id: crumbHover
                            enabled: !isLast
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            enabled: !isLast
                            onTapped: root.segmentClicked(index, modelData)
                        }
                    }

                    Label {
                        visible: !isLast
                        text: "/"
                        color: "#62717A"
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Recherche - width 264px, height 32px selon nouvelle maquette
        Rectangle {
            Layout.preferredWidth: 264
            Layout.preferredHeight: 32
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.7)
            border.width: 1
            border.color: "#DDE4E2"
            visible: root.showSearch

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 8

                FaIcon {
                    glyph: "\uf002"
                    color: "#62717A"
                    font.pixelSize: 14
                }

                TextField {
                    Layout.fillWidth: true
                    placeholderText: qsTr("Rechercher")
                    background: Rectangle { color: "transparent" }
                    color: "#15222B"
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                    onAccepted: root.searchRequested(text)
                }
            }
        }

        // Notifications - 32px
        Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 8
            color: "transparent"
            visible: root.showNotifications

            FaIcon {
                anchors.centerIn: parent
                glyph: "\uf0f3"
                color: "#4A5961"
                font.pixelSize: 16
            }

            // Badge notification
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 6
                anchors.rightMargin: 7
                width: 8
                height: 8
                radius: 4
                color: "#C8453B"
                border.width: 2
                border.color: "#EEF2F1"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.notificationsRequested()
            }
        }
    }
}
