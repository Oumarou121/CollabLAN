import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * DashboardCard - carte d'acces rapide utilisee sur l'ecran d'accueil
 * pour presenter les modules disponibles (Chat, Users, Transfert, ...).
 */
Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string description: ""

    signal clicked()

    Layout.preferredHeight: 148
    radius: Theme.radiusLarge
    color: Theme.surface
    border.width: 1
    border.color: mouseArea.containsMouse ? Theme.primary : Theme.border

    Behavior on border.color { ColorAnimation { duration: 120 } }

    scale: mouseArea.containsMouse ? 1.015 : 1.0
    Behavior on scale { NumberAnimation { duration: 120 } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall

        Rectangle {
            width: 40
            height: 40
            radius: Theme.radiusMedium
            color: Theme.primaryMuted

            Text {
                anchors.centerIn: parent
                text: root.icon
                font.pixelSize: 18
                color: Theme.primary
            }
        }

        Label {
            text: root.title
            font.pixelSize: Theme.fontSizeSubheading
            font.bold: true
            font.family: Theme.fontFamily
            color: Theme.text
        }

        Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.description
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.fontFamily
            color: Theme.textSecondary
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignTop
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
