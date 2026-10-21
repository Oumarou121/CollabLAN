import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Themes
import "icons.js" as Icons

/*
 * SheetModal - fenetre de Ligne claire : feuille centree, filet d'encre,
 * angles de 3 px. En-tete (surtitre en capitales, titre serif, chapeau),
 * corps defilant, pied separe par un filet d'encre.
 *
 * C'est un Item pose au-dessus de l'ecran hote (pas un Popup) : il se
 * capture comme le reste de la page et suit son theme.
 *
 *   SheetModal {
 *       kicker: qsTr("Accès"); title: qsTr("Qui peut ouvrir <b>« X »</b>")
 *       ColumnLayout { ... }                        // corps
 *       footer: [ AppButton { ... } ]               // boutons du pied
 *   }
 *
 * `title` accepte du texte riche (StyledText) : la graisse normale est
 * celle du titre, <b> marque le nom de l'objet.
 */
Item {
    id: root

    property bool open: false
    property string kicker: ""
    property string title: ""
    property string lead: ""
    property string counter: ""          // ex. « 1 sur 2 », a la place de la croix
    property string footNote: ""
    property bool closable: true
    property bool boldTitle: true
    property real sheetWidth: 540
    default property alias content: bodyColumn.data
    property alias footer: footRow.data

    signal closeRequested()

    anchors.fill: parent
    z: 60
    visible: root.open
    opacity: root.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

    Shortcut {
        sequences: [StandardKey.Cancel]
        enabled: root.open && root.closable
        onActivated: root.closeRequested()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: if (root.closable) root.closeRequested()
        }
    }

    // Ombre portee douce : la seule de la fenetre.
    RectangularShadow {
        anchors.fill: sheet
        offset.y: 14
        blur: 36
        spread: -4
        radius: sheet.radius
        color: Theme.shadowStrong
        scale: sheet.scale
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(root.sheetWidth, root.width - 32)
        height: Math.min(layout.implicitHeight, root.height - 40)
        radius: Theme.radiusSheet
        color: Theme.bg
        border.width: 1
        border.color: Theme.ruleInk
        scale: root.open ? 1 : 0.98
        Behavior on scale { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        ColumnLayout {
            id: layout
            anchors.fill: parent
            spacing: 0

            // ---- En-tete ---------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 14
                Layout.topMargin: 18
                Layout.bottomMargin: 14
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    CapsLabel { Layout.fillWidth: true; visible: root.kicker.length > 0; text: root.kicker }
                    Text {
                        Layout.fillWidth: true
                        text: root.title
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        color: Theme.ink
                        font.family: Theme.fontFamilySerif
                        font.pixelSize: Theme.fs(22)
                        font.weight: root.boldTitle ? Theme.weightBold : Theme.weightRegular
                        lineHeight: 1.08
                        Accessible.role: Accessible.Heading
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        visible: root.lead.length > 0
                        text: root.lead
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        color: Theme.ink2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 2
                    Layout.rightMargin: 8
                    visible: root.counter.length > 0
                    text: root.counter
                    color: Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11.5)
                }
                AbstractButton {
                    id: closeBtn
                    visible: root.closable && root.counter.length === 0
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    Layout.topMargin: -4
                    hoverEnabled: true
                    Accessible.name: qsTr("Fermer")
                    onClicked: root.closeRequested()
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    background: Rectangle {
                        radius: 17
                        color: closeBtn.hovered ? Theme.selectWash : "transparent"
                        border.width: closeBtn.visualFocus ? 2 : 0
                        border.color: Theme.focusRing
                    }
                    contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.close; size: 17; strokeWidth: 1.8; color: Theme.ink2 } }
                }
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line }

            // ---- Corps -----------------------------------------------------
            Flickable {
                id: bodyFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: bodyColumn.implicitHeight + 34
                implicitHeight: bodyColumn.implicitHeight + 34
                clip: true
                contentWidth: width
                contentHeight: bodyColumn.implicitHeight + 34
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: bodyColumn
                    x: 22
                    y: 16
                    width: bodyFlick.width - 44
                    spacing: 0
                }
            }

            // ---- Pied ------------------------------------------------------
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk; visible: footRow.children.length > 0 }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                Layout.preferredHeight: 58
                visible: footRow.children.length > 0
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: root.footNote
                    color: Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    wrapMode: Text.WordWrap
                }
                Row {
                    id: footRow
                    spacing: 8
                }
            }
        }
    }
}
