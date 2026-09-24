import QtQuick
import QtQuick.Shapes

/*
 * LineIcon - icone filaire (trait) definie par un chemin SVG sur une
 * grille 24 x 24 (style Lucide), identique aux icones de la maquette V2.2.
 *
 * path: donnees de chemin SVG (sous-chemins en "M"/"L"/"H"/"V" absolus ou
 *       "l"/"h"/"v" relatifs ; ne pas commencer un sous-chemin par "m").
 */
Item {
    id: root

    property string path: ""
    property color color: "#000000"
    property real size: 20
    property real strokeWidth: 1.75

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: root.size / 24

        // Sur-echantillonnage : le Shape est rasterise plus grand que sa
        // taille logique pour rester net une fois mis a l'echelle.
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(root.size * 4, root.size * 4)

        ShapePath {
            strokeColor: root.color
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg { path: root.path }
        }
    }
}
