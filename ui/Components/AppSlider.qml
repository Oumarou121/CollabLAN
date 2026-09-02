import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppSlider - curseur stylise, a la place du Slider "brut" utilise
 * jusqu'ici dans SettingsView.
 *
 * Usage :
 *   AppSlider {
 *       from: 0; to: 100
 *       value: someProperty
 *       onMoved: someProperty = value
 *   }
 */
Slider {
    id: root

    implicitHeight: 24

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.availableWidth
        height: 4
        radius: 2
        color: Theme.surfaceAlt

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: Theme.primary
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight / 2 - height / 2
        implicitWidth: 18
        implicitHeight: 18
        radius: 9
        color: "#FFFFFF"
        border.width: 2
        border.color: Theme.primary

        Behavior on x { enabled: !root.pressed; NumberAnimation { duration: 100 } }
    }
}
