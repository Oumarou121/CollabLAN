import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppMenu - menu contextuel / deroulant du design system.
 *
 * Les entrees se declarent avec AppMenuItem (pas MenuItem : `delegate:` ne
 * s'applique pas aux MenuItem declares directement comme enfants), et les
 * separateurs avec AppMenuSeparator.
 *
 *   AppMenu {
 *       AppMenuItem { text: qsTr("Renommer"); iconGlyph: ""; onTriggered: ... }
 *       AppMenuSeparator {}
 *       AppMenuItem { text: qsTr("Supprimer"); danger: true; onTriggered: ... }
 *   }
 */
Menu {
    id: root

    padding: 5
    implicitWidth: 220

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationFast }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
    }

    background: Rectangle {
        implicitWidth: 220
        radius: Theme.radiusMedium
        color: Theme.surface0
        border.width: 1
        border.color: Theme.line

        // Ombre portee legere (deux couches decalees, sans effet graphique
        // supplementaire).
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.topMargin: 3
            anchors.bottomMargin: -6
            anchors.leftMargin: 1
            anchors.rightMargin: -1
            radius: parent.radius + 2
            color: Theme.shadowColor
        }
    }
}
