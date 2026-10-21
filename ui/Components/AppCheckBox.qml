import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppCheckBox - case a cocher stylisee, coherente avec AppButton/AppTextField
 * (coins arrondis, halo de focus, transition douce), a la place du CheckBox
 * "brut" utilise jusqu'ici dans SharedFolderView.
 *
 * Usage :
 *   AppCheckBox {
 *       text: qsTr("Lecture seule")
 *       checked: someProperty
 *       onToggled: someProperty = checked
 *   }
 */
CheckBox {
    id: root

    implicitHeight: 28
    spacing: Theme.spacingSmall
    font.pixelSize: Theme.fontSizeBody
    font.family: Theme.fontFamily

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    indicator: Rectangle {
        implicitWidth: 20
        implicitHeight: 20
        radius: Theme.radiusSmall
        anchors.verticalCenter: parent.verticalCenter
        color: root.checked ? Theme.primary : Theme.background
        border.width: root.checked ? 0 : (root.activeFocus ? 2 : 1)
        border.color: root.activeFocus ? Theme.primary : Theme.border

        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on border.color { ColorAnimation { duration: 100 } }

        Text {
            anchors.centerIn: parent
            visible: root.checked
            text: "\u2713"
            color: Theme.inkOnAccent
            font.pixelSize: Theme.fs(13)
            font.bold: true
        }
    }

    contentItem: Text {
        text: root.text
        color: root.enabled ? Theme.text : Theme.textTertiary
        font: root.font
        leftPadding: root.indicator.width + root.spacing
        verticalAlignment: Text.AlignVCenter
    }
}
