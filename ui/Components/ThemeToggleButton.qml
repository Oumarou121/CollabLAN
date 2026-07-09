import QtQuick
import QtQuick.Controls
import Themes

/*
 * ThemeToggleButton - petit bouton rond permettant de basculer
 * Theme.darkMode (Light <-> Dark). Reutilisable sur n'importe quel ecran.
 */
Rectangle {
    id: root

    width: 40
    height: 40
    radius: width / 2
    color: mouseArea.containsMouse ? Theme.surfaceAlt : Theme.surface
    border.color: Theme.border
    border.width: 1

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        anchors.centerIn: parent
        text: Theme.darkMode ? "\u263E" : "\u2600"
        font.pixelSize: 18
        color: Theme.darkMode ? "#F2C94C" : "#F2994A"
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Theme.toggle()
    }

    ToolTip.visible: mouseArea.containsMouse
    ToolTip.delay: 400
    ToolTip.text: Theme.darkMode ? qsTr("Passer au theme clair") : qsTr("Passer au theme sombre")
}
