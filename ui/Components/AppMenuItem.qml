import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppMenuItem - entree de menu stylisee, a utiliser a l'interieur d'un
 * AppMenu (voir AppMenu.qml) a la place de MenuItem.
 *
 * iconGlyph : glyphe unicode optionnel affiche avant le texte.
 * danger    : true pour les actions destructrices (ex. "Supprimer"),
 *             colore le texte/icone en rouge (Theme.error).
 */
MenuItem {
    id: root

    property string iconGlyph: ""
    property bool danger: false

    implicitHeight: 34
    implicitWidth: 200

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: Row {
        spacing: Theme.spacingSmall
        leftPadding: Theme.spacingSmall
        rightPadding: Theme.spacingSmall

        Text {
            visible: root.iconGlyph.length > 0
            text: root.iconGlyph
            font.pixelSize: Theme.fontSizeBody
            color: root.danger ? Theme.error : Theme.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.text
            font.pixelSize: Theme.fontSizeBody
            font.family: Theme.fontFamily
            color: root.danger ? Theme.error : Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: root.highlighted
               ? (root.danger ? Theme.errorMuted : Theme.surfaceHover)
               : "transparent"
    }
}
