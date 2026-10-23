import QtQuick
import QtQuick.Shapes
import Themes

/*
 * BrandMark - logo LocaLink en Ligne claire : deux personnes dont les bras
 * se rejoignent en V, dessinees en vecteur sur une grille 64 (d'apres
 * l'ancien ui/Assets/logo.png, cf. design/.../marque-ligne-claire).
 *
 * Corps = deux arcs d'un meme cercle (trait 11), bras = traits a 45°
 * (trait 10), tetes = disques. La personne de gauche prend l'encre du
 * texte, celle de droite l'accent : le logo suit le theme et l'accent.
 * Celle de droite passe devant, detouree d'un lisere couleur du fond
 * (`paperColor`, a ajuster si le logo est pose sur une autre surface).
 *
 * Utilise par la navigation, la connexion, le chargement et "A propos".
 */
Item {
    id: root

    property int size: 40
    property color inkColor: Theme.ink
    property color accentColor: Theme.accentColor
    property color paperColor: Theme.bg

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Accessible.role: Accessible.Graphic
    Accessible.name: "LocaLink"

    // Traces (viewBox 0 0 64 64).
    readonly property string leftBody: "M13.57 20.59A22.5 22.5 0 0 0 38.95 54.9"
    readonly property string leftArm: "M14 20.68L32 39"
    readonly property string rightBody: "M50.43 20.59A22.5 22.5 0 0 1 25.05 54.9"
    readonly property string rightArm: "M50 20.68L31.4 39.6"
    readonly property real bodyWidth: 11
    readonly property real armWidth: 10
    readonly property real halo: 1.7

    component Stroke: ShapePath {
        property alias d: svg.path
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { id: svg }
    }
    component Head: ShapePath {
        property real cx: 0
        strokeColor: "transparent"
        strokeWidth: 0
        PathAngleArc { centerX: cx; centerY: 7.2; radiusX: 6.2; radiusY: 6.2; startAngle: 0; sweepAngle: 360 }
    }

    Shape {
        width: 64
        height: 64
        anchors.centerIn: parent
        scale: root.size / 64
        // Meme rendu que LineIcon : analytique, puis rasterise plus grand
        // que sa taille logique pour rester net une fois mis a l'echelle.
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(root.size * 4, root.size * 4)

        Head { cx: 13.4; fillColor: root.inkColor }
        Head { cx: 50.6; fillColor: root.accentColor }
        Stroke { d: root.leftBody; strokeColor: root.inkColor; strokeWidth: root.bodyWidth }
        Stroke { d: root.leftArm; strokeColor: root.inkColor; strokeWidth: root.armWidth }
        Stroke { d: root.rightBody; strokeColor: root.paperColor; strokeWidth: root.bodyWidth + 2 * root.halo }
        Stroke { d: root.rightArm; strokeColor: root.paperColor; strokeWidth: root.armWidth + 2 * root.halo }
        Stroke { d: root.rightBody; strokeColor: root.accentColor; strokeWidth: root.bodyWidth }
        Stroke { d: root.rightArm; strokeColor: root.accentColor; strokeWidth: root.armWidth }
    }
}
