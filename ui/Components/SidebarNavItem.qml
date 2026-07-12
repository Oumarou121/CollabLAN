import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * SidebarNavItem - entree de navigation laterale (icone + libelle),
 * utilisee dans la sidebar de HomeView (et reutilisable ailleurs).
 */
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property bool active: false

    signal clicked()

    Layout.preferredHeight: 40
    radius: Theme.radiusMedium
    color: active ? Theme.sidebarActive : (mouseArea.containsMouse ? Theme.sidebarHover : "transparent")

    Behavior on color { ColorAnimation { duration: 100 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingSmall
        anchors.rightMargin: Theme.spacingSmall
        spacing: Theme.spacingSmall

        Text {
            text: root.icon
            font.pixelSize: 16
            color: Theme.sidebarText
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            text: root.label
            color: Theme.sidebarText
            font.pixelSize: Theme.fontSizeBody
            font.family: Theme.fontFamily
            Layout.fillWidth: true
            elide: Text.ElideRight
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
