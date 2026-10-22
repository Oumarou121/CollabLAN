import QtQuick
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * AppearancePreview - fiche « Aperçu » de Parametres > Apparence : une
 * page Transferts en miniature, dessinee avec les jetons du theme. Elle
 * suit donc d'elle-meme le theme, l'accent, la taille du texte (Theme.fs),
 * la densite et la barre laterale reduite.
 */
ColumnLayout {
    id: root
    spacing: 0

    component PvRow: Item {
        id: pr
        property string glyph: "ok"
        property string title: ""
        property string sub: ""
        property string pct: ""
        property bool first: false
        Layout.fillWidth: true
        implicitHeight: prCol.implicitHeight + (Theme.compact ? 8 : 14)
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        StateGlyph { x: 0; y: (Theme.compact ? 4 : 7) + 3; kind: pr.glyph; size: 9 }
        ColumnLayout {
            id: prCol
            x: 18; y: Theme.compact ? 4 : 7
            width: parent.width - 18
            spacing: 1
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: pr.title; elide: Text.ElideRight; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5); font.weight: Theme.weightSemibold }
                Text { visible: pr.pct.length > 0; text: pr.pct; color: Theme.navActiveInk; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(13); font.weight: Theme.weightBold }
            }
            Text { Layout.fillWidth: true; text: pr.sub; elide: Text.ElideRight; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10.5) }
            Rectangle {
                visible: pr.pct.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 3
                implicitHeight: 2
                color: Theme.line
                Rectangle { width: parent.width * 0.62; height: 4; y: -1; color: Theme.accent }
            }
        }
    }

    component PvNav: Rectangle {
        id: pn
        property string icon: ""
        property string label: ""
        property bool current: false
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        implicitHeight: Theme.fs(11) + 13
        radius: 2
        color: pn.current ? Theme.surface0 : "transparent"
        border.width: pn.current ? 1 : 0
        border.color: Theme.line
        Row {
            x: Theme.sidebarCollapsed ? (parent.width - 11) / 2 : 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            LineIcon { anchors.verticalCenter: parent.verticalCenter; path: pn.icon; size: 11; strokeWidth: 1.8; color: pn.current ? Theme.ink : Theme.ink3 }
            Text { visible: !Theme.sidebarCollapsed; anchors.verticalCenter: parent.verticalCenter; text: pn.label; color: pn.current ? Theme.ink : Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10.5); font.weight: pn.current ? Theme.weightSemibold : Theme.weightRegular }
        }
    }

    CapsLabel { text: qsTr("Aperçu") }
    Text {
        Layout.topMargin: 6
        text: qsTr("Ce que vous verrez")
        color: Theme.ink
        font.family: Theme.fontFamilySerif
        font.pixelSize: Theme.fs(20)
        font.weight: Theme.weightBold
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 12
        implicitHeight: pvCol.implicitHeight + 2
        radius: Theme.radiusSheet
        color: Theme.bg
        border.width: 1
        border.color: Theme.lineStrong
        clip: true

        ColumnLayout {
            id: pvCol
            x: 1; y: 1
            width: parent.width - 2
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                Layout.leftMargin: 12
                spacing: 8
                Text { text: qsTr("Transferts"); color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(14); font.weight: Theme.weightBold }
                Text { Layout.fillWidth: true; text: "/ Kadiatou"; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11) }
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                ColumnLayout {
                    Layout.preferredWidth: Theme.sidebarCollapsed ? 34 : 104
                    Layout.fillHeight: true
                    Layout.topMargin: 8
                    Layout.alignment: Qt.AlignTop
                    spacing: 0
                    PvNav { icon: Icons.overview; label: qsTr("Vue d'ensemble") }
                    PvNav { icon: Icons.exchange; label: qsTr("Transferts"); current: true }
                    PvNav { icon: Icons.messageCircle; label: qsTr("Discussions") }
                    PvNav { icon: Icons.monitor; label: qsTr("Postes") }
                    Item { Layout.fillHeight: true }
                }
                Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.ruleInk }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    Layout.topMargin: 10
                    spacing: 0
                    Text {
                        Layout.bottomMargin: 8
                        textFormat: Text.StyledText
                        text: qsTr("<b>2</b> envois en cours.")
                        color: Theme.ink
                        font.family: Theme.fontFamilySerif
                        font.pixelSize: Theme.fs(17)
                    }
                    PvRow { glyph: "online"; title: "Bilan_2026_T3.xlsx"; sub: qsTr("vers PC-COMPTA-01 · 48 Mo"); pct: "62 %" }
                    PvRow { glyph: "ok"; title: "Plan_salle.pdf"; sub: qsTr("de Kadiatou · 2,1 Mo") }
                    PvRow { glyph: "offline"; title: "Archives.zip"; sub: qsTr("vers PC-IT-03 · hors ligne") }
                    Text {
                        Layout.topMargin: 8
                        text: qsTr("Ouvrir le dossier →")
                        color: Theme.navActiveInk
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Theme.weightSemibold
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.topMargin: 10
        text: qsTr("L'aperçu suit vos choix ; toute l'application change en même temps.")
        wrapMode: Text.WordWrap
        color: Theme.ink3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
    }
}
