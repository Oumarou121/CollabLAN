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

    signal searchRequested(string query)
    signal notificationsRequested()

    Rectangle {
        anchors.fill: parent
        color: "#FFFFFF"
        border.width: 1
        border.color: "#DDE4E2"
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 8

        // Breadcrumb - selon nouvelle maquette: LocaLink / Vue d'ensemble
        Row {
            spacing: 4

            Label {
                text: "LocaLink"
                color: "#62717A"
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }

            Label {
                text: "/"
                color: "#62717A"
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }

            Label {
                text: "Vue d'ensemble"
                color: "#15222B"
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
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
