import QtQuick
import QtQuick.Shapes
import Themes

/*
 * BrandMark - logo LocaLink : trois postes autour du serveur central,
 * relies par un cercle interrompu et par trois rayons. Dessine en vecteur
 * sur une grille 64 d'apres l'image de reference choisie par l'utilisateur.
 *
 * Postes, cercle et rayons a l'encre du texte, serveur a l'accent : le logo
 * suit le theme et l'accent choisi. Pour une version d'une seule couleur,
 * donner a `accentColor` la meme valeur que `inkColor`.
 *
 * Aux petites tailles, les traits s'epaississent pour rester lisibles.
 * Utilise par la navigation, la connexion, le chargement et "A propos".
 */
Item {
    id: root

    property int size: 40
    property color inkColor: Theme.ink
    property color accentColor: Theme.accentColor

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Accessible.role: Accessible.Graphic
    Accessible.name: "LocaLink"

    // Traces (viewBox 0 0 64 64).
    readonly property string arcs: "M19.74 16.74A22.31 22.31 0 0 0 9.92 38.18M44.36 16.74A22.31 22.31 0 0 1 54.17 38.18M19.64 53.88A22.31 22.31 0 0 0 44.46 53.88"
    readonly property string monitors: "M24.99 5.79H39.1A1.04 1.04 0 0 1 40.14 6.83V16.23A1.04 1.04 0 0 1 39.1 17.27H24.99A1.04 1.04 0 0 1 23.95 16.23V6.83A1.04 1.04 0 0 1 24.99 5.79Z"
                                       + "M4.1 42.02H16.42A1.04 1.04 0 0 1 17.46 43.06V51.81A1.04 1.04 0 0 1 16.42 52.85H4.1A1.04 1.04 0 0 1 3.06 51.81V43.06A1.04 1.04 0 0 1 4.1 42.02Z"
                                       + "M47.68 42.02H59.9A1.04 1.04 0 0 1 60.94 43.06V51.81A1.04 1.04 0 0 1 59.9 52.85H47.68A1.04 1.04 0 0 1 46.64 51.81V43.06A1.04 1.04 0 0 1 47.68 42.02Z"
    readonly property string necks: "M30.64 18.2H34.02V20.6H30.64ZM8.52 53.9H11.15V55.8H8.52ZM52.94 53.9H55.58V55.8H52.94Z"
    readonly property string feet: "M29.32 20.75L34.68 20.75M7.67 56.42L12.94 56.42M51.15 56.42L56.42 56.42"
    readonly property string spokes: "M32.05 23.29L32.05 28M23.11 37.98L20.09 42.02M40.99 37.98L44 42.02"
    readonly property string server: "M26.96 29.41H37.13A2.35 2.35 0 0 1 39.48 31.76V42.03A2.35 2.35 0 0 1 37.13 44.38H26.96A2.35 2.35 0 0 1 24.61 42.03V31.76A2.35 2.35 0 0 1 26.96 29.41Z"
    // Epaississement des traits sous 32 px (un trait de 2,6 / 64 tomberait sous le pixel).
    readonly property real weight: size < 24 ? 1.5 : size < 32 ? 1.25 : 1

    component Stroke: ShapePath {
        property alias d: svg.path
        fillColor: "transparent"
        strokeColor: root.inkColor
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { id: svg }
    }
    component Fill: ShapePath {
        property alias d: svgFill.path
        strokeColor: "transparent"
        strokeWidth: 0
        PathSvg { id: svgFill }
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

        Stroke { d: root.arcs; strokeWidth: 2.8 * root.weight; capStyle: ShapePath.FlatCap }
        Stroke { d: root.monitors; strokeWidth: 2.64 * root.weight }
        Fill { d: root.necks; fillColor: root.inkColor }
        Stroke { d: root.feet; strokeWidth: 2.35 * root.weight }
        Stroke { d: root.spokes; strokeWidth: 2.4 * root.weight; capStyle: ShapePath.FlatCap }
        Fill { d: root.server; fillColor: root.accentColor }
    }
}
