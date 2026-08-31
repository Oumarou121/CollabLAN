import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppDivider - separateur horizontal avec un libelle centre (ex. "ou
 * saisir manuellement"), utilise pour scinder un formulaire en deux
 * sections sans passer par un GroupBox complet.
 *
 * Usage :
 *   AppDivider { label: qsTr("ou saisir manuellement") }
 */
RowLayout {
    id: root

    property string label: ""

    spacing: Theme.spacingSmall
    Layout.fillWidth: true

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.border
    }

    Label {
        visible: root.label.length > 0
        text: root.label
        font.pixelSize: Theme.fontSizeCaption
        font.family: Theme.fontFamily
        color: Theme.textTertiary
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.border
    }
}
