import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * StatPill - indicateur compact de l'en-tete "Supervision du reseau" :
 * pastille d'icone, valeur, libelle. Cliquable (ouvre la section liee).
 */
AbstractButton {
    id: root

    property string glyph: ""
    property string tone: "neutral"
    property string value: ""
    property string label: ""
    property string tooltip: ""

    implicitHeight: 42
    implicitWidth: row.implicitWidth + 6 + 14
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    Accessible.name: root.value + " " + root.label

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    ToolTip.visible: root.tooltip.length > 0 && root.hovered
    ToolTip.text: root.tooltip
    ToolTip.delay: 500

    background: Rectangle {
        radius: Theme.radiusMedium
        color: root.hovered ? Theme.hover : Theme.surface0
        border.width: 1
        border.color: root.hovered ? Theme.lineStrong : Theme.line

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: parent.radius + 3
            color: "transparent"
            border.width: 2
            border.color: Theme.focusRing
            visible: root.visualFocus
        }
    }

    contentItem: Item {
        RowLayout {
            id: row
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9

            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 9
                color: Theme.toneSoft(root.tone)

                FaIcon {
                    anchors.centerIn: parent
                    glyph: root.glyph
                    color: Theme.toneInk(root.tone)
                    font.pixelSize: Theme.fs(12.5)
                }
            }
            Text {
                text: root.value
                color: Theme.ink
                font.pixelSize: Theme.fs(17)
                font.weight: Theme.weightBold
                font.family: Theme.fontFamily
            }
            Text {
                text: root.label
                color: Theme.ink2
                font.pixelSize: Theme.fs(12)
                font.family: Theme.fontFamily
            }
        }
    }
}
