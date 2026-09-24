import QtQuick
import Themes

/*
 * SkeletonLine - barre de chargement (squelette) avec reflet qui defile,
 * comme la maquette V2.2 (.skel : hauteur 12, rayon 6, cycle 1,6 s).
 * Pas de spinner plein ecran : on garde la forme du contenu a venir.
 */
Rectangle {
    id: root

    property bool animated: true

    implicitWidth: 60
    implicitHeight: 12
    radius: 6
    color: Theme.dashboardLine
    clip: true

    Rectangle {
        id: sheen
        width: root.width * 0.5
        height: root.height
        radius: root.radius

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(Theme.dashboardSurfaceAlt.r, Theme.dashboardSurfaceAlt.g, Theme.dashboardSurfaceAlt.b, 0) }
            GradientStop { position: 0.5; color: Theme.dashboardSurfaceAlt }
            GradientStop { position: 1.0; color: Qt.rgba(Theme.dashboardSurfaceAlt.r, Theme.dashboardSurfaceAlt.g, Theme.dashboardSurfaceAlt.b, 0) }
        }

        NumberAnimation on x {
            running: root.animated && root.visible
            from: -sheen.width
            to: root.width
            duration: 1600
            loops: Animation.Infinite
        }
    }
}
