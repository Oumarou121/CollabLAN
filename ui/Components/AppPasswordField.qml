import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppPasswordField - meme rendu qu'AppTextField (libelle, focus, erreur),
 * avec un bouton "afficher / masquer le mot de passe" integre a droite.
 *
 *   AppPasswordField {
 *       label: qsTr("Mot de passe")
 *       placeholderText: qsTr("8 caractères minimum")
 *       Layout.fillWidth: true
 *   }
 */
ColumnLayout {
    id: root

    property string label: ""
    property string helperText: ""
    property bool hasError: false
    property bool isRequired: false
    property alias placeholderText: field.placeholderText
    property alias text: field.text
    property alias field: field
    signal accepted()

    spacing: 6

    Text {
        visible: root.label.length > 0
        text: root.label + (root.isRequired ? " *" : "")
        color: Theme.ink2
        font.pixelSize: Theme.fs(12)
        font.weight: Theme.weightSemibold
        font.family: Theme.fontFamily
    }

    TextField {
        id: field
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.controlHeight
        color: field.enabled ? Theme.ink : Theme.inkDisabled
        font.pixelSize: Theme.fs(13)
        font.family: Theme.fontFamily
        leftPadding: 12
        rightPadding: 40
        verticalAlignment: TextInput.AlignVCenter
        selectByMouse: true
        selectionColor: Theme.accentColor
        selectedTextColor: Theme.accentInk
        placeholderTextColor: Theme.ink3
        echoMode: revealButton.revealed ? TextInput.Normal : TextInput.Password
        Accessible.name: root.label.length > 0 ? root.label : field.placeholderText
        Accessible.description: root.helperText

        background: Rectangle {
            radius: Theme.radiusControl
            color: field.enabled ? Theme.surface0 : Theme.sunken
            border.width: 1
            border.color: root.hasError ? Theme.dangerColor
                        : field.activeFocus ? Theme.accentColor
                        : (field.hovered ? Theme.ink3 : Theme.lineStrong)

            Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: parent.radius + 3
                color: "transparent"
                border.width: 3
                border.color: Theme.alpha(root.hasError ? Theme.dangerColor : Theme.accentColor, 0.18)
                visible: field.activeFocus
            }
        }

        IconButton {
            id: revealButton
            property bool revealed: false
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            glyph: revealed ? "" : ""
            size: Theme.controlHeight - 8
            iconSize: Theme.fs(13)
            tooltip: revealed ? qsTr("Masquer le mot de passe") : qsTr("Afficher le mot de passe")
            focusPolicy: Qt.TabFocus
            onClicked: revealed = !revealed
        }

        onAccepted: root.accepted()
    }

    RowLayout {
        visible: root.helperText.length > 0
        Layout.fillWidth: true
        spacing: 6

        FaIcon {
            visible: root.hasError
            glyph: ""
            color: Theme.dangerInk
            font.pixelSize: Theme.fs(11)
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
        }

        Text {
            text: root.helperText
            font.pixelSize: Theme.fs(12)
            font.family: Theme.fontFamily
            color: root.hasError ? Theme.dangerInk : Theme.ink3
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
