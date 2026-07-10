import QtQuick
import QtQuick.Controls
import Themes

/*
 * CallView - ecran "Call" (a implementer, Developpeur 1)
 * Theme global applique (issue #7).
 */
Item {
    id: root

    signal backRequested()

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Label {
        anchors.centerIn: parent
        text: "Call - a implementer"
        color: Theme.text
    }
}
