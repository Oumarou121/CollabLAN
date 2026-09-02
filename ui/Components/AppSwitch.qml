import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppSwitch - interrupteur on/off stylise, a la place du Switch "brut"
 * utilise jusqu'ici dans SettingsView.
 *
 * Usage :
 *   AppSwitch {
 *       checked: someProperty
 *       onToggled: someProperty = checked
 *   }
 */
Switch {
    id: root

    implicitWidth: 44
    implicitHeight: 26
    spacing: Theme.spacingSmall
    font.pixelSize: Theme.fontSizeBody
    font.family: Theme.fontFamily

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    indicator: Rectangle {
        x: 0
        y: (root.height - height) / 2
        width: 44
        height: 24
        radius: height / 2
        color: root.checked ? Theme.primary : Theme.surfaceAlt
        border.width: root.checked ? 0 : 1
        border.color: Theme.border

        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
            width: 18
            height: 18
            radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 3
            color: "#FFFFFF"

            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        }
    }

    contentItem: Text {
        visible: root.text.length > 0
        text: root.text
        color: Theme.text
        font: root.font
        leftPadding: root.indicator.width + root.spacing
        verticalAlignment: Text.AlignVCenter
    }
}
