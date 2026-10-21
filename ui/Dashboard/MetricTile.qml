import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * MetricTile - indicateur compact du tableau de bord (refonte 2026).
 *
 *   [icone]  Libelle
 *            Valeur  unite              (mini-barres optionnelles)
 *            Contexte / pastilles / lien
 *
 * La tuile entiere est un bouton (clavier + souris) qui ouvre la section
 * correspondante quand `interactive` est vrai. Un zero reste en encre
 * tertiaire : c'est une information, pas une alerte.
 */
AbstractButton {
    id: root

    property string overline: ""
    property string glyph: ""
    property string value: "0"
    property string unit: ""
    property string footnote: ""
    property string linkText: ""
    // "neutral" | "accent" | "warning" | "danger" | "success" | "call"
    property string tone: "neutral"
    property real meterValue: -1
    property var bars: []
    property var chips: []
    property bool muted: false
    property bool interactive: true

    signal linkActivated()

    readonly property color toneColor: {
        switch (root.tone) {
        case "warning": return Theme.warningColor
        case "danger": return Theme.dangerColor
        case "success": return Theme.successColor
        case "call": return Theme.callColor
        case "accent": return Theme.accentColor
        default: return Theme.ink2
        }
    }
    readonly property color toneSoft: {
        switch (root.tone) {
        case "warning": return Theme.warningSoft
        case "danger": return Theme.dangerSoft
        case "success": return Theme.successSoft
        case "call": return Theme.callSoft
        case "accent": return Theme.accentSoft
        default: return Theme.sunken
        }
    }
    readonly property color toneInk: {
        switch (root.tone) {
        case "warning": return Theme.warningInk
        case "danger": return Theme.dangerInk
        case "success": return Theme.successInk
        case "call": return Theme.callInk
        case "accent": return Theme.darkMode ? Theme.accentHover : Theme.accentColor
        default: return Theme.ink2
        }
    }

    hoverEnabled: root.interactive
    focusPolicy: root.interactive ? Qt.TabFocus : Qt.NoFocus
    padding: Theme.cardPadding - 2
    implicitHeight: tileRow.implicitHeight + topPadding + bottomPadding
    implicitWidth: 220
    Accessible.name: root.overline + " : " + root.value + " " + root.unit
                     + (root.footnote.length > 0 ? ", " + root.footnote : "")
    Accessible.role: root.interactive ? Accessible.Button : Accessible.StaticText

    HoverHandler { cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor }

    background: Rectangle {
        radius: Theme.radiusCard
        color: Theme.surface0
        border.width: 1
        border.color: root.interactive && root.hovered ? Theme.lineStrong : Theme.line
        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

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

    contentItem: RowLayout {
        id: tileRow
        spacing: 12

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: 10
            color: root.toneSoft

            FaIcon {
                anchors.centerIn: parent
                glyph: root.glyph
                color: root.toneInk
                font.pixelSize: Theme.fs(15)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: root.overline
                    color: Theme.ink2
                    font.pixelSize: Theme.fs(12)
                    font.weight: Theme.weightMedium
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                FaIcon {
                    visible: root.interactive && root.hovered
                    glyph: ""
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(12)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: root.value
                    color: root.muted ? Theme.ink3 : Theme.ink
                    font.pixelSize: Theme.fontSizeMetric
                    font.weight: Theme.weightBold
                    font.letterSpacing: -0.5
                    font.family: Theme.fontFamily
                    font.features: ({ "tnum": 1 })
                }

                Text {
                    visible: root.unit.length > 0
                    text: root.unit
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(13)
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 4
                }

                Item { Layout.fillWidth: true; visible: root.unit.length === 0 }

                // Mini-barres : progression de chaque element en cours.
                Row {
                    visible: root.bars.length > 0
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 5
                    spacing: 3

                    Repeater {
                        model: root.bars
                        delegate: Item {
                            id: barSlot
                            required property real modelData
                            width: 6
                            height: 22

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: parent.height
                                radius: 2
                                color: Theme.sunken
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.max(3, parent.height * Math.max(0, Math.min(1, barSlot.modelData)))
                                radius: 2
                                color: Theme.markTransfer
                            }
                        }
                    }
                }
            }

            // Jauge fine
            Rectangle {
                visible: root.meterValue >= 0
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.preferredHeight: 4
                radius: 2
                color: Theme.sunken

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.meterValue))
                    height: parent.height
                    radius: 2
                    color: root.tone === "neutral" ? Theme.accentColor : root.toneColor
                    visible: root.meterValue > 0
                }
            }

            // Pastilles
            Flow {
                visible: root.chips.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 5

                Repeater {
                    model: root.chips
                    delegate: StatusBadge {
                        required property var modelData
                        text: modelData.text || ""
                        tone: modelData.tone || "neutral"
                        compact: true
                    }
                }
            }

            Text {
                visible: root.footnote.length > 0 && root.chips.length === 0
                text: root.footnote
                color: Theme.ink3
                font.pixelSize: Theme.fs(12)
                font.family: Theme.fontFamily
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                visible: root.linkText.length > 0
                text: root.linkText
                color: Theme.darkMode ? Theme.accentHover : Theme.accentColor
                font.pixelSize: Theme.fs(12)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
                Layout.topMargin: 2

                TapHandler { onTapped: root.linkActivated() }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }
    }
}
