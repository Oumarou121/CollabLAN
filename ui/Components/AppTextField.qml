import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppTextField - champ de formulaire standard (label + champ + texte
 * d'aide optionnel), a la place du motif Label/TextField/background
 * duplique a l'identique dans chaque dialog (AdminView notamment).
 *
 * Ajoute un anneau de focus (absent des TextField "bruts" utilises
 * jusqu'ici) et un texte d'aide sous le champ, comme dans les
 * maquettes des modales Admin.
 *
 * Usage :
 *   AppTextField {
 *       label: qsTr("Nom d'utilisateur")
 *       placeholderText: qsTr("marie.dupont")
 *       Layout.fillWidth: true
 *   }
 *
 * `text`/`echoMode`/`validator` etc. se passent directement (alias sur
 * le TextField interne), exactement comme sur un TextField normal.
 */
ColumnLayout {
    id: root

    property string label: ""
    property string helperText: ""
    property alias placeholderText: field.placeholderText
    property alias text: field.text
    property alias echoMode: field.echoMode
    property alias validator: field.validator
    property alias inputMethodHints: field.inputMethodHints
    property alias fontFamily: field.font.family
    property alias field: field

    spacing: Theme.spacingXs

    Label {
        visible: root.label.length > 0
        text: root.label
        font.pixelSize: Theme.fontSizeSmall
        font.family: Theme.fontFamily
        color: Theme.textSecondary
    }

    TextField {
        id: field
        Layout.fillWidth: true
        Layout.preferredHeight: 48
        color: Theme.text
        font.pixelSize: Theme.fontSizeBody
        font.family: Theme.fontFamily
        leftPadding: Theme.spacingMedium
        rightPadding: Theme.spacingMedium
        selectByMouse: true
        placeholderTextColor: Theme.textTertiary

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.colorTextField
            border.width: field.activeFocus ? 2 : 1
            border.color: field.activeFocus ? Theme.primary : Theme.border

            Behavior on border.color { ColorAnimation { duration: 100 } }
        }
    }

    Label {
        visible: root.helperText.length > 0
        text: root.helperText
        font.pixelSize: Theme.fontSizeCaption
        font.family: Theme.fontFamily
        color: Theme.textTertiary
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}
