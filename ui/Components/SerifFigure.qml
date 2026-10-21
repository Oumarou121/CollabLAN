import QtQuick
import QtQuick.Controls
import Themes

/*
 * SerifFigure - chiffre cle de Ligne claire : rubrique en petites capitales,
 * valeur en PT Serif (suffixe facultatif, ex. « /10 »), ligne de contexte.
 * Cliquable : ouvre la section correspondante. `attention` colore la valeur
 * en ambre et ajoute un losange devant la rubrique (jamais la couleur seule).
 */
AbstractButton {
    id: root

    property string label: ""
    property string value: "0"
    property string suffix: ""
    property string context: ""
    property bool attention: false
    property string tooltip: ""
    property real valueSize: Theme.fontSizeFigure

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    padding: 0
    implicitWidth: Math.max(col.implicitWidth, 96)
    implicitHeight: col.implicitHeight
    Accessible.name: root.label + " : " + root.value + root.suffix + (root.context.length ? ", " + root.context : "")

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    ToolTip.visible: root.tooltip.length > 0 && root.hovered
    ToolTip.text: root.tooltip
    ToolTip.delay: 600

    background: Rectangle {
        color: "transparent"
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: Theme.radiusSheet
            color: "transparent"
            border.width: 2
            border.color: Theme.focusRing
            visible: root.visualFocus
        }
    }

    contentItem: Column {
        id: col
        spacing: 3

        Row {
            spacing: 5
            StateGlyph {
                visible: root.attention
                kind: "decision"
                size: 8
                anchors.verticalCenter: parent.verticalCenter
            }
            CapsLabel { text: root.label }
        }
        Row {
            spacing: 1
            Text {
                id: valueText
                text: root.value
                color: root.attention ? Theme.warningInk : (root.hovered ? Theme.navActiveInk : Theme.ink)
                font.family: Theme.fontFamilySerif
                font.pixelSize: root.valueSize
                font.features: ({ "tnum": 1, "lnum": 1 })
                lineHeight: 1.0
            }
            Text {
                visible: root.suffix.length > 0
                anchors.baseline: valueText.baseline
                text: root.suffix
                color: Theme.ink3
                font.family: Theme.fontFamilySerif
                font.pixelSize: Math.round(root.valueSize / 2)
            }
        }
        Text {
            text: root.context
            color: Theme.ink3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12)
            textFormat: Text.StyledText
            elide: Text.ElideRight
            width: Math.max(implicitWidth, 1)
        }
    }
}
