import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * SheetField - champ de formulaire des fenetres Ligne claire : libelle,
 * champ a filet (encre au focus, rouge en erreur), aide ou erreur dessous.
 */
ColumnLayout {
    id: root

    property string label: ""
    property string optional: ""          // ex. « facultatif »
    property string hint: ""
    property string error: ""
    property bool mono: false
    property bool password: false
    property alias text: field.text
    property alias placeholderText: field.placeholderText
    property alias field: field
    signal accepted()

    Layout.fillWidth: true
    spacing: 5

    Row {
        spacing: 6
        Text { text: root.label; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
        Text { visible: root.optional.length > 0; text: root.optional; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 36
        radius: Theme.radiusSheet
        color: Theme.surface0
        border.width: root.error.length || field.activeFocus ? 1.5 : 1
        border.color: root.error.length ? Theme.dangerColor : field.activeFocus ? Theme.ink : Theme.lineStrong
        TextField {
            id: field
            anchors.fill: parent
            leftPadding: 12
            rightPadding: 12
            echoMode: root.password ? TextInput.Password : TextInput.Normal
            placeholderTextColor: Theme.ink3
            color: Theme.ink
            font.family: root.mono ? "Cascadia Mono" : Theme.fontFamily
            font.pixelSize: root.mono ? Theme.fs(12.5) : Theme.fs(13.5)
            background: Item {}
            selectByMouse: true
            Accessible.name: root.label
            onAccepted: root.accepted()
        }
    }
    Text {
        visible: root.error.length > 0 || root.hint.length > 0
        Layout.fillWidth: true
        text: root.error.length ? root.error : root.hint
        color: root.error.length ? Theme.dangerInk : Theme.ink3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
        font.weight: root.error.length ? Theme.weightSemibold : Theme.weightRegular
        wrapMode: Text.WordWrap
    }
}
