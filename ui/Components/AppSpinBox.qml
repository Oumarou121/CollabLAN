import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppSpinBox - selecteur numerique stylise, a la place du SpinBox "brut"
 * utilise jusqu'ici dans SettingsView (plusieurs occurrences).
 *
 * Usage :
 *   AppSpinBox {
 *       from: 0; to: 100
 *       value: someProperty
 *       onValueModified: someProperty = value
 *   }
 */
SpinBox {
    id: root

    // false pour les identifiants numeriques (ports...) : pas de
    // separateur de milliers ("7845", pas "7 845").
    property bool groupDigits: true

    textFromValue: function(value, locale) {
        return root.groupDigits ? Number(value).toLocaleString(locale, "f", 0) : value.toString()
    }
    valueFromText: function(text, locale) {
        return root.groupDigits ? Number.fromLocaleString(locale, text) : parseInt(text.replace(/[^0-9-]/g, ""), 10)
    }

    implicitHeight: Theme.controlHeight
    implicitWidth: 140
    font.pixelSize: Theme.fontSizeBody
    font.family: Theme.fontFamily

    contentItem: TextInput {
        text: root.textFromValue(root.value, root.locale)
        color: Theme.text
        font: root.font
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        selectByMouse: true
        readOnly: !root.editable
        validator: root.validator
        inputMethodHints: Qt.ImhDigitsOnly
    }

    up.indicator: Rectangle {
        x: root.width - width
        implicitWidth: 32
        height: root.height
        radius: Theme.radiusMedium
        color: root.up.pressed ? Theme.surfaceHover : "transparent"

        Text {
            anchors.centerIn: parent
            text: "+"
            font.pixelSize: Theme.fontSizeSubheading
            color: root.up.pressed ? Theme.primary : Theme.textSecondary
        }
    }

    down.indicator: Rectangle {
        x: 0
        implicitWidth: 32
        height: root.height
        radius: Theme.radiusMedium
        color: root.down.pressed ? Theme.surfaceHover : "transparent"

        Text {
            anchors.centerIn: parent
            text: "\u2212"
            font.pixelSize: Theme.fontSizeSubheading
            color: root.down.pressed ? Theme.primary : Theme.textSecondary
        }
    }

    background: Rectangle {
        radius: Theme.radiusMedium
        color: Theme.background
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Theme.primary : Theme.border

        Behavior on border.color { ColorAnimation { duration: 100 } }
    }
}
