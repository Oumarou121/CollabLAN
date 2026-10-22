import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * FieldBox - champ de saisie des reglages : fond feuille, filet qui passe
 * a l'encre au focus et au rouge en erreur. Entree = accepted(),
 * Echap = escaped().
 */
Rectangle {
    id: root

    property alias text: field.text
    property alias placeholderText: field.placeholderText
    property alias field: field
    property bool mono: false
    property bool error: false
    property string accessibleName: ""
    signal edited()
    signal accepted()
    signal escaped()

    Layout.fillWidth: true
    Layout.maximumWidth: 560
    implicitHeight: 36
    radius: Theme.radiusSheet
    color: Theme.surface0
    border.width: root.error || field.activeFocus ? 1.5 : 1
    border.color: root.error ? Theme.dangerColor : field.activeFocus ? Theme.ink : Theme.lineStrong

    TextField {
        id: field
        anchors.fill: parent
        leftPadding: 12
        rightPadding: 12
        placeholderTextColor: Theme.ink3
        color: Theme.ink
        font.family: root.mono ? "Cascadia Mono" : Theme.fontFamily
        font.pixelSize: root.mono ? Theme.fs(12.5) : Theme.fs(13.5)
        background: Item {}
        selectByMouse: true
        Accessible.name: root.accessibleName
        onTextEdited: root.edited()
        onAccepted: root.accepted()
        Keys.onEscapePressed: root.escaped()
    }
}
