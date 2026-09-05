import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppPasswordField - meme style qu'AppTextField, avec un bouton
 * "afficher/masquer" (glyphe oeil / oeil barre Font Awesome) integre a
 * droite du champ, plutot qu'un mot de passe en clair perpetuellement
 * masque comme c'etait le cas jusqu'ici (echoMode fige a Password).
 *
 * Usage :
 *   AppPasswordField {
 *       label: qsTr("Mot de passe")
 *       placeholderText: qsTr("8 caracteres minimum")
 *       Layout.fillWidth: true
 *   }
 */
ColumnLayout {
    id: root

    property string label: ""
    property string helperText: ""
    property alias placeholderText: field.placeholderText
    property alias text: field.text
    property alias field: field
    signal accepted()

    spacing: Theme.spacingXs

    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }

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
        rightPadding: 40
        selectByMouse: true
        placeholderTextColor: Theme.textTertiary
        echoMode: revealButton.revealed ? TextInput.Normal : TextInput.Password

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.colorTextField
            border.width: field.activeFocus ? 2 : 1
            border.color: field.activeFocus ? Theme.primary : Theme.border

            Behavior on border.color { ColorAnimation { duration: 100 } }
        }

        IconButton {
            id: revealButton
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            property bool revealed: false
            glyph: revealed ? "\uf070" : "\uf06e"
            variant: "ghost"
            size: 30
            onClicked: revealed = !revealed
        }

        onAccepted: root.accepted()
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
