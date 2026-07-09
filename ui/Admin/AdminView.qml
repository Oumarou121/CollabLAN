import QtQuick
import QtQuick.Controls
import Themes

/*
 * AdminView - ecran "Admin" (a implementer, Developpeur 1)
 * Theme global applique (issue #7).
 */
Item {
    id: root

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Label {
        anchors.centerIn: parent
        text: "Admin - a implementer"
        color: Theme.text
    }
}
