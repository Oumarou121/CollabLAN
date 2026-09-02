import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppMenu - menu contextuel stylise, a la place du Menu "brut" utilise
 * jusqu'ici dans SharedFolderView (menu clic droit sur un dossier/fichier).
 *
 * Ne stylise que le fond du popup : les items doivent etre declares avec
 * AppMenuItem (voir AppMenuItem.qml) et non MenuItem, car `delegate:` ne
 * s'applique pas aux MenuItem declares directement comme enfants QML.
 *
 * Usage :
 *   AppMenu {
 *       id: myMenu
 *       AppMenuItem { text: qsTr("Renommer"); onTriggered: ... }
 *       AppMenuItem { text: qsTr("Supprimer"); danger: true; onTriggered: ... }
 *   }
 */
Menu {
    id: root

    padding: Theme.spacingXs

    background: Rectangle {
        implicitWidth: 200
        radius: Theme.radiusMedium
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        layer.enabled: true
    }
}
