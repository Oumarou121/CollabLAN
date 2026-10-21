import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppButton - bouton texte du design system LocaLink.
 *
 * variant : "primary"   action principale de l'ecran (une seule par zone)
 *           "secondary" action courante (contour neutre) - defaut
 *           "ghost"     action tertiaire, sans contour (alias "tertiary")
 *           "soft"      action accentuee discrete (voile d'accent)
 *           "outline"   contour d'accent
 *           "danger"    action destructrice (plein rouge)
 *           "dangerGhost" action destructrice discrete (texte rouge)
 *           "ink"     Ligne claire : action principale, plein d'encre
 *           "line"    Ligne claire : action courante, filet d'encre
 * size    : "normal" (Theme.controlHeight) | "small" | "large"
 * iconGlyph : glyphe Font Awesome optionnel avant le texte.
 * iconPath  : icone filaire (chemin SVG de icons.js) avant le texte.
 * loading : affiche un indicateur et bloque les clics.
 *
 * "iconGlyph" et non "icon" : Button expose deja une propriete groupee
 * "icon" declaree FINAL depuis Qt 6.3.
 */
Button {
    id: root

    property string variant: "secondary"
    property string size: "normal"
    property string iconGlyph: ""
    property string iconPath: ""
    property bool fullWidth: false
    property bool loading: false
    property string tooltip: ""

    readonly property bool isPrimary: variant === "primary"
    readonly property bool isDanger: variant === "danger"
    readonly property bool isDangerGhost: variant === "dangerGhost"
    readonly property bool isGhost: variant === "ghost" || variant === "tertiary"
    readonly property bool isOutline: variant === "outline"
    readonly property bool isSoft: variant === "soft"
    readonly property bool isInk: variant === "ink"
    readonly property bool isLine: variant === "line"
    readonly property bool editorial: isInk || isLine
    readonly property bool filled: isPrimary || isDanger || isInk

    readonly property int controlHeight: size === "small" ? Theme.controlHeightSmall
                                         : size === "large" ? Theme.controlHeight + 6
                                         : editorial ? Theme.controlHeightEditorial
                                         : Theme.controlHeight
    readonly property int hPad: size === "small" ? 10 : (size === "large" ? 18 : 14)

    // Texte sur fond plein : en sombre, l'accent et le rouge s'eclaircissent,
    // le texte passe donc en encre foncee (contraste >= 4,5:1).
    readonly property color inkOnFill: Theme.darkMode ? "#0B1018" : "#FFFFFF"

    readonly property color baseColor: {
        if (isPrimary) return Theme.accentColor
        if (isDanger) return Theme.dangerColor
        if (isInk) return Theme.ink
        if (isSoft) return Theme.accentSoft
        if (variant === "secondary") return Theme.surface0
        return "transparent"
    }
    readonly property color hoverColor: {
        if (isPrimary) return Theme.accentHover
        if (isDanger) return Theme.dangerHover
        if (isInk) return Theme.accentHover
        if (isLine) return Theme.selectWash
        if (isSoft) return Theme.accentMuted
        if (isOutline) return Theme.accentSoft
        if (isDangerGhost) return Theme.dangerSoft
        return Theme.hover
    }
    readonly property color labelColor: {
        if (!root.enabled) return Theme.inkDisabled
        if (isInk) return Theme.inkOnInk
        if (filled) return inkOnFill
        if (isOutline || isSoft) return Theme.darkMode ? Theme.accentHover : Theme.accentColor
        if (isDangerGhost) return Theme.dangerInk
        return Theme.ink
    }

    Layout.fillWidth: fullWidth
    implicitHeight: controlHeight
    implicitWidth: Math.max(controlHeight, contentRow.implicitWidth + 2 * hPad)
    leftPadding: hPad
    rightPadding: hPad
    topPadding: 0
    bottomPadding: 0
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: root.text.length > 0 ? root.text : root.tooltip

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    // Pendant le chargement, les clics sont absorbes (sans toucher a
    // `enabled`, que l'ecran hote peut deja piloter).
    MouseArea {
        anchors.fill: parent
        visible: root.loading
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BusyCursor
    }

    ToolTip.visible: root.tooltip.length > 0 && root.hovered
    ToolTip.text: root.tooltip
    ToolTip.delay: 400

    background: Rectangle {
        radius: root.editorial ? Theme.radiusSheet : Theme.radiusControl
        color: {
            if (!root.enabled)
                return root.filled ? Theme.sunken : "transparent"
            if (root.down)
                return Qt.darker(root.hoverColor, Theme.darkMode ? 0.92 : 1.06)
            return root.hovered ? root.hoverColor : root.baseColor
        }
        border.width: (root.variant === "secondary" || root.isOutline || root.isLine) ? 1 : 0
        border.color: root.isOutline ? Theme.accentColor
                    : root.isLine ? (root.hovered ? Theme.ink : Theme.lineStrong)
                                     : (root.hovered ? Theme.lineStrong : Theme.line)

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        // Anneau de focus clavier (jamais au clic souris).
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
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: 7

            // En cours : l'indicateur remplace l'icone, le libelle reste lisible
            // (ex. "Connexion…").
            Spinner {
                visible: root.loading
                running: root.loading
                color: root.labelColor
                Layout.preferredWidth: Theme.fs(root.size === "small" ? 12 : 14)
                Layout.preferredHeight: Layout.preferredWidth
            }

            LineIcon {
                visible: root.iconPath.length > 0 && !root.loading
                path: root.iconPath
                color: root.labelColor
                size: Theme.fs(root.size === "small" ? 13 : 15)
                strokeWidth: 1.8
            }

            FaIcon {
                visible: root.iconGlyph.length > 0 && !root.loading
                glyph: root.iconGlyph
                color: root.labelColor
                font.pixelSize: Theme.fs(root.size === "small" ? 12 : 13)
            }

            Text {
                visible: root.text.length > 0
                text: root.text
                color: root.labelColor
                font.pixelSize: Theme.fs(root.size === "small" ? 12 : 13)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
                elide: Text.ElideRight
            }
        }
    }
}
