import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppSearchField - champ de recherche / filtre du design system.
 *
 * Loupe a gauche, bouton d'effacement a droite des qu'un texte est saisi,
 * Echap efface. compact : hauteur reduite (barres d'outils).
 */
Rectangle {
    id: root

    property bool compact: false
    property alias text: field.text
    property alias placeholderText: field.placeholderText
    property alias field: field
    property real rightInset: 0

    signal cleared()

    implicitHeight: compact ? Theme.controlHeightSmall : Theme.controlHeight
    implicitWidth: 260
    radius: Theme.radiusControl
    color: field.activeFocus ? Theme.surface0 : Theme.surface1
    border.width: 1
    border.color: field.activeFocus ? Theme.accentColor : (hover.hovered ? Theme.ink3 : Theme.lineStrong)

    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

    HoverHandler { id: hover }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: parent.radius + 3
        color: "transparent"
        border.width: 3
        border.color: Theme.alpha(Theme.accentColor, 0.18)
        visible: field.activeFocus
    }

    FaIcon {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: root.compact ? 9 : 11
        anchors.verticalCenter: parent.verticalCenter
        glyph: ""
        color: Theme.ink3
        font.pixelSize: Theme.fs(12)
    }

    TextField {
        id: field
        anchors.left: icon.right
        anchors.leftMargin: 8
        anchors.right: clearButton.visible ? clearButton.left : parent.right
        anchors.rightMargin: (clearButton.visible ? 2 : 10) + root.rightInset
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        color: Theme.ink
        font.pixelSize: Theme.fs(13)
        font.family: Theme.fontFamily
        placeholderTextColor: Theme.ink3
        selectionColor: Theme.accentColor
        selectedTextColor: Theme.accentInk
        selectByMouse: true
        leftPadding: 0
        rightPadding: 0
        verticalAlignment: TextInput.AlignVCenter
        background: Item {}
        Accessible.name: field.placeholderText
        Keys.onEscapePressed: function(event) {
            if (field.text.length > 0) {
                field.text = ""
                root.cleared()
                event.accepted = true
            } else {
                event.accepted = false
            }
        }
    }

    IconButton {
        id: clearButton
        visible: field.text.length > 0
        anchors.right: parent.right
        anchors.rightMargin: 4 + root.rightInset
        anchors.verticalCenter: parent.verticalCenter
        glyph: ""
        size: root.compact ? 22 : 26
        iconSize: Theme.fs(11)
        tooltip: qsTr("Effacer la recherche")
        onClicked: {
            field.text = ""
            field.forceActiveFocus()
            root.cleared()
        }
    }
}
