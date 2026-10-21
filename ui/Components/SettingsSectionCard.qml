import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * SettingsSectionCard - section de la page Parametres : carte avec pastille
 * d'icone, titre, sous-titre, puis le contenu declare dans
 * SettingsSectionCard { ... } (empile verticalement).
 */
ColumnLayout {
    id: root

    default property alias content: contentColumn.children
    property string icon: ""
    property string title: ""
    property string subtitle: ""

    spacing: 0

    // Conservee pour compatibilite (police d'icones desormais globale).
    readonly property string iconFontFamily: "FontAwesome"

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: cardColumn.implicitHeight + Theme.cardPadding * 2
        radius: Theme.radiusCard
        color: Theme.surface0
        border.width: 1
        border.color: Theme.line

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: Theme.cardPadding
            spacing: Theme.spacingMedium

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 9
                    color: Theme.accentSoft
                    visible: root.icon.length > 0

                    FaIcon {
                        anchors.centerIn: parent
                        glyph: root.icon
                        font.pixelSize: Theme.fs(14)
                        color: Theme.darkMode ? Theme.accentHover : Theme.accentColor
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: root.title
                        font.pixelSize: Theme.fontSizeCardTitle
                        font.weight: Theme.weightSemibold
                        font.family: Theme.fontFamily
                        color: Theme.ink
                        Accessible.role: Accessible.Heading
                    }
                    Text {
                        text: root.subtitle
                        visible: root.subtitle.length > 0
                        font.pixelSize: Theme.fs(12)
                        font.family: Theme.fontFamily
                        color: Theme.ink3
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            ColumnLayout {
                id: contentColumn
                Layout.fillWidth: true
                spacing: Theme.spacingMedium
            }
        }
    }
}
