import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * IconButton - bouton a glyphe unique (Font Awesome 4.7) du design system.
 *
 * variant : "ghost" (defaut, transparent) | "secondary" (contour)
 *           | "soft" (voile d'accent) | "primary" (plein accent)
 *           | "danger" (voile rouge)
 * tooltip : libelle affiche au survol ET nom accessible (lecteurs
 *           d'ecran) - obligatoire pour un bouton sans texte.
 * enabledLook : decouple l'aspect "actif" de `enabled` (ex. bouton
 *           d'envoi cliquable au clavier mais grise tant que le champ est
 *           vide).
 *
 * Base AbstractButton : focus clavier (Tab), activation Espace/Entree et
 * anneau de focus, contrairement a l'ancienne version Item + MouseArea.
 */
AbstractButton {
    id: root

    property string glyph: ""
    property string variant: "ghost"
    property int size: Theme.controlHeight
    property int iconSize: Math.round(size * 0.42)
    property int radius: Theme.radiusControl
    property bool enabledLook: true
    property bool bold: false
    property string tooltip: ""
    // Couleur de glyphe imposee (ex. statut) - vide = selon la variante.
    property color glyphColorOverride: "transparent"

    readonly property bool isPrimary: variant === "primary"
    readonly property bool isDanger: variant === "danger"
    readonly property bool isSoft: variant === "soft"

    Layout.preferredWidth: size
    Layout.preferredHeight: size
    implicitWidth: size
    implicitHeight: size
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    padding: 0
    Accessible.name: root.tooltip.length > 0 ? root.tooltip : root.text
    Accessible.role: Accessible.Button

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    ToolTip.visible: root.tooltip.length > 0 && root.hovered
    ToolTip.text: root.tooltip
    ToolTip.delay: 400

    readonly property color baseColor: {
        if (!root.enabledLook || !root.enabled)
            return (isPrimary || isDanger) ? Theme.sunken : "transparent"
        if (isPrimary) return root.down ? Theme.accentHover : (root.hovered ? Theme.accentHover : Theme.accentColor)
        if (isDanger) return root.hovered ? Theme.dangerColor : Theme.dangerSoft
        if (isSoft) return root.hovered ? Theme.accentMuted : Theme.accentSoft
        if (variant === "secondary") return root.hovered ? Theme.hover : Theme.surface0
        return root.hovered || root.down ? Theme.hover : "transparent"
    }

    readonly property color glyphColor: {
        if (root.glyphColorOverride.a > 0) return root.glyphColorOverride
        if (!root.enabledLook || !root.enabled) return Theme.inkDisabled
        if (isPrimary) return Theme.accentInk
        if (isDanger) return root.hovered ? (Theme.darkMode ? "#0B1018" : "#FFFFFF") : Theme.dangerInk
        if (isSoft) return Theme.darkMode ? Theme.accentHover : Theme.accentColor
        return root.hovered ? Theme.ink : Theme.ink2
    }

    background: Rectangle {
        radius: root.radius
        color: root.baseColor
        border.width: root.variant === "secondary" ? 1 : 0
        border.color: Theme.line

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: parent.radius + 3
            color: "transparent"
            border.width: 2
            border.color: Theme.focusRing
            visible: root.visualFocus
        }
    }

    contentItem: Item {
        FaIcon {
            anchors.centerIn: parent
            glyph: root.glyph
            color: root.glyphColor
            font.pixelSize: root.iconSize
            font.bold: root.bold
        }
    }
}
