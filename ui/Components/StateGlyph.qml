import QtQuick
import QtQuick.Shapes
import Themes

/*
 * StateGlyph - glyphe d'etat de Ligne claire. La FORME porte l'etat autant
 * que la couleur (jamais la couleur seule) :
 *
 *   postes      online (plein) | away (demi) | busy (barre) |
 *               transferring (plein, encre) | calling (plein, prune) |
 *               offline (cercle pointille)
 *   natures     decision (losange ambre) | error (croix rouge) |
 *               watch (cercle gris) | ok (coche verte)
 *   puces       brand | call | unread | read
 *
 * Dessine a la taille `size` (carre) ; meme langage que l'hemicycle.
 */
Item {
    id: root

    property string kind: "online"
    property real size: 12

    implicitWidth: size
    implicitHeight: size

    readonly property real c: size / 2
    readonly property real r: size / 2

    function circle(q) {
        return "M " + (c - q) + " " + c + " A " + q + " " + q + " 0 1 0 " + (c + q) + " " + c
             + " A " + q + " " + q + " 0 1 0 " + (c - q) + " " + c + " Z"
    }

    // [chemin, remplissage, trait, epaisseur, pointille]
    readonly property var base: {
        switch (kind) {
        case "online": return [circle(r), Theme.successColor, "transparent", 0, false]
        case "busy": return [circle(r), Theme.warningColor, "transparent", 0, false]
        case "away": return [circle(r - 0.8), Theme.surface0, Theme.warningColor, 1.5, false]
        case "transferring": return [circle(r), Theme.markTransfer, "transparent", 0, false]
        case "calling": return [circle(r), Theme.callColor, "transparent", 0, false]
        case "offline": return [circle(r - 0.8), "transparent", Theme.nodeOfflineLine, 1.4, true]
        case "watch": return [circle(r - 1), "transparent", Theme.nodeOfflineLine, 1.5, false]
        case "brand": return [circle(r * 0.75), Theme.markTransfer, "transparent", 0, false]
        case "call": return [circle(r * 0.75), Theme.callColor, "transparent", 0, false]
        case "unread": return [circle(r * 0.6), Theme.markTransfer, "transparent", 0, false]
        case "read": return [circle(r * 0.55), "transparent", Theme.inkDisabled, 1.3, false]
        }
        return ["", "transparent", "transparent", 0, false]
    }

    // Surcouche pleine : demi-disque (absent), barre (occupe), losange (decision).
    readonly property var overlay: {
        switch (kind) {
        case "away":
            return ["M " + c + " " + (c - r + 0.8) + " A " + (r - 0.8) + " " + (r - 0.8) + " 0 0 0 "
                    + c + " " + (c + r - 0.8) + " Z", Theme.warningColor]
        case "busy":
            return ["M " + (c - r * 0.52) + " " + (c - r * 0.15) + " h " + (r * 1.04) + " v " + (r * 0.3)
                    + " h " + (-r * 1.04) + " Z", Theme.surface0]
        case "decision":
            return ["M " + c + " " + (c - r * 0.95) + " L " + (c + r * 0.95) + " " + c + " L " + c + " "
                    + (c + r * 0.95) + " L " + (c - r * 0.95) + " " + c + " Z", Theme.warningColor]
        }
        return ["", "transparent"]
    }

    // Trait seul : croix (erreur), coche (reussite).
    readonly property var mark: {
        const k = r * 0.68
        switch (kind) {
        case "error":
            return ["M " + (c - k) + " " + (c - k) + " L " + (c + k) + " " + (c + k)
                    + " M " + (c + k) + " " + (c - k) + " L " + (c - k) + " " + (c + k), Theme.dangerColor]
        case "ok":
            return ["M " + (c - r * 0.72) + " " + c + " L " + (c - r * 0.2) + " " + (c + r * 0.55)
                    + " L " + (c + r * 0.78) + " " + (c - r * 0.6), Theme.successColor]
        }
        return ["", "transparent"]
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.base[1]
            strokeColor: root.base[3] > 0 ? root.base[2] : "transparent"
            strokeWidth: Math.max(0.01, root.base[3])
            strokeStyle: root.base[4] ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: [1.5, 1.4]
            PathSvg { path: root.base[0] }
        }
        ShapePath {
            fillColor: root.overlay[1]
            strokeColor: "transparent"
            PathSvg { path: root.overlay[0] }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.mark[1]
            strokeWidth: Math.max(1.6, root.size * 0.17)
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.mark[0] }
        }
    }
}
