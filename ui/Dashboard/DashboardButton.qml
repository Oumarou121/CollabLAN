import QtQuick
import QtQuick.Controls
import Themes
import "../Components"

/*
 * DashboardButton - bouton du systeme Dashboard V2.x (maquette `.btn`) :
 * hauteur 36, rayon 8, padding 14, texte 14 / 600, icone filaire optionnelle.
 *
 * Variantes : "primary" | "secondary" | "soft" | "ghost".
 * `active` fige l'etat actif d'un bouton bascule ; `iconOnly` produit un
 * bouton carre (le `tooltip` sert alors de nom accessible).
 * Tous les jetons viennent de Theme.dashboardXxx : clair et sombre.
 */
Button {
    id: root

    property string variant: "secondary"
    property string iconPath: ""
    property bool iconOnly: false
    property bool active: false
    property int controlHeight: 36
    property string tooltip: ""

    readonly property bool isPrimary: variant === "primary"
    readonly property int sidePadding: controlHeight >= 36 ? 14 : 12

    // dashboardPrimary est un bleu-vert clair en mode sombre : le texte du
    // bouton primaire y passe en encre fonce.
    readonly property color primaryForeground: Theme.darkMode ? Theme.dashboardBackground
                                                              : Theme.dashboardPrimaryText

    readonly property color foreground: {
        if (!root.enabled)
            return Theme.dashboardInkTertiary
        if (root.isPrimary)
            return root.primaryForeground
        if (root.active || root.variant === "soft")
            return Theme.dashboardPrimary
        if (root.variant === "ghost")
            return root.hovered ? Theme.dashboardInk : Theme.dashboardInkSecondary
        return Theme.dashboardInk
    }

    readonly property color fill: {
        if (!root.enabled)
            return (root.isPrimary || root.variant === "secondary") ? Theme.dashboardSurfaceAlt : "transparent"
        if (root.active)
            return Theme.dashboardPrimarySoft
        switch (root.variant) {
        case "primary": return root.hovered || root.down ? Theme.dashboardPrimaryHover : Theme.dashboardPrimary
        case "soft":    return root.hovered ? Theme.dashboardPrimaryMuted : Theme.dashboardPrimarySoft
        case "ghost":   return root.hovered ? Theme.dashboardSurfaceAlt : "transparent"
        default:        return root.hovered ? Theme.dashboardSurfaceAlt : Theme.dashboardSurface
        }
    }

    readonly property color outline: {
        if (root.visualFocus)
            return Theme.dashboardPrimary
        if (!root.enabled)
            return (root.isPrimary || root.variant === "secondary") ? Theme.dashboardLine : "transparent"
        if (root.variant === "secondary")
            return root.hovered ? Theme.dashboardLineStrong : Theme.dashboardLine
        return "transparent"
    }

    implicitHeight: controlHeight
    implicitWidth: iconOnly ? controlHeight : row.implicitWidth + sidePadding * 2
    padding: 0
    hoverEnabled: true

    Accessible.name: root.iconOnly ? root.tooltip : root.text

    ToolTip.visible: root.hovered && root.tooltip.length > 0
    ToolTip.text: root.tooltip
    ToolTip.delay: 500

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: root.fill
        border.width: (root.outline.a > 0) ? (root.visualFocus ? 2 : 1) : 0
        border.color: root.outline

        Behavior on color { ColorAnimation { duration: 100 } }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 7

            LineIcon {
                visible: root.iconPath.length > 0
                anchors.verticalCenter: parent.verticalCenter
                path: root.iconPath
                size: root.controlHeight >= 36 ? 16 : 15
                strokeWidth: 2
                color: root.foreground
            }

            Label {
                visible: !root.iconOnly && root.text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                color: root.foreground
                font.pixelSize: root.controlHeight >= 36 ? 14 : 13
                font.weight: Font.DemiBold
                font.family: Theme.fontFamily
            }
        }
    }
}
