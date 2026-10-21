import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppMenuItem - entree d'AppMenu.
 *
 * iconGlyph : glyphe Font Awesome optionnel avant le texte.
 * danger    : action destructrice (texte et icone rouges).
 * shortcutText : raccourci affiche a droite (purement informatif).
 * checkable/checked (MenuItem) : coche a gauche, pour les choix exclusifs
 *              (ex. statut En ligne / Absent / Occupe).
 */
MenuItem {
    id: root

    property string iconGlyph: ""
    property bool danger: false
    property string shortcutText: ""

    implicitHeight: Theme.compact ? 30 : 34
    implicitWidth: 210
    leftPadding: 10
    rightPadding: 10

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    readonly property color tone: !root.enabled ? Theme.inkDisabled
                                  : (root.danger ? Theme.dangerInk : Theme.ink)

    indicator: Item {}
    arrow: Item {}

    contentItem: RowLayout {
        spacing: 9

        Item {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            visible: root.iconGlyph.length > 0 || root.checkable

            FaIcon {
                anchors.centerIn: parent
                glyph: root.checkable ? (root.checked ? "" : "") : root.iconGlyph
                color: root.checkable ? Theme.accentColor
                                      : (root.danger ? Theme.dangerInk : Theme.ink2)
                font.pixelSize: Theme.fs(13)
            }
        }

        Text {
            text: root.text
            color: root.tone
            font.pixelSize: Theme.fs(13)
            font.family: Theme.fontFamily
            font.weight: root.checked ? Theme.weightSemibold : Theme.weightRegular
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Text {
            visible: root.shortcutText.length > 0
            text: root.shortcutText
            color: Theme.ink3
            font.pixelSize: Theme.fs(11)
            font.family: Theme.fontFamily
        }
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: root.highlighted
               ? (root.danger ? Theme.dangerSoft : Theme.hover)
               : "transparent"
    }
}
