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

    Layout.preferredHeight: 44
    radius: Theme.radiusSmall
    color: active ? Theme.sidebarActive : (mouseArea.containsMouse ? Theme.sidebarHover : "transparent")

    Behavior on color { ColorAnimation { duration: 100 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingMedium
        anchors.rightMargin: Theme.spacingMedium
        spacing: Theme.spacingSmall

        Text {
            text: root.icon
            font.pixelSize: Theme.fs(17)
            color: Theme.sidebarText
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            text: root.label
            color: Theme.sidebarText
            font.pixelSize: Theme.fontSizeSubheading
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
