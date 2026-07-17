import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppButton - bouton reutilisable avec variantes coherentes dans toute
 * l'application (evite de redefinir background/contentItem a chaque
 * ecran, comme c'etait le cas auparavant).
 *
 * variant: "primary" | "secondary" | "ghost" | "danger" | "outline"
 * iconGlyph: glyphe unicode optionnel affiche avant le texte
 *
 * Note: on utilise "iconGlyph" et non "icon" car Button expose deja
 * une propriete groupee "icon" (icon.name, icon.source, ...) declaree
 * FINAL depuis Qt 6.3 ; la redefinir provoque une erreur QML fatale
 * ("Cannot override FINAL property") qui rend AppButton indisponible.
 */
Button {
    id: root

    property string variant: "secondary"
    property string iconGlyph: ""
    property bool fullWidth: false

    readonly property bool isPrimary: variant === "primary"
    readonly property bool isDanger: variant === "danger"
    readonly property bool isGhost: variant === "ghost"
    readonly property bool isOutline: variant === "outline"

    readonly property color baseColor: {
        if (isPrimary) return Theme.primary
        if (isDanger) return Theme.error
        return "transparent"
    }
    readonly property color hoverColor: {
        if (isPrimary) return Theme.primaryHover
        if (isDanger) return Theme.error
        if (isOutline) return Theme.primaryMuted
        if (isGhost) return Theme.surfaceHover
        return Theme.surfaceHover
    }
    readonly property color labelColor: {
        if (isPrimary || isDanger) return "#FFFFFF"
        if (isOutline) return Theme.primary
        return Theme.text
    }

    Layout.fillWidth: fullWidth
    implicitHeight: 40
    implicitWidth: contentItem.implicitWidth + Theme.spacingLarge
    hoverEnabled: true
    opacity: enabled ? 1.0 : 0.55

    // Note: Control/Item n'exposent pas "cursorShape" directement en QML
    // (c'est une propriete C++ de QQuickItem, non exposee sur Control).
    // On passe par HoverHandler, qui expose cursorShape depuis Qt 5.15.
    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    background: Rectangle {
        radius: Theme.radiusMedium
        color: root.pressed ? Qt.darker(root.hovered ? root.hoverColor : root.baseColor, 1.08)
                             : (root.hovered ? root.hoverColor : root.baseColor)
        border.width: (root.isGhost || root.variant === "secondary" || root.isOutline) ? 1 : 0
        border.color: root.isOutline ? Theme.primary : Theme.border

        Behavior on color { ColorAnimation { duration: 100 } }
    }

    contentItem: Row {
        spacing: Theme.spacingXs
        anchors.centerIn: parent

        Text {
            visible: root.iconGlyph.length > 0
            text: root.iconGlyph
            font.pixelSize: Theme.fontSizeBody
            color: root.labelColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.text
            color: root.labelColor
            font.pixelSize: Theme.fontSizeBody
            font.bold: root.isPrimary || root.isDanger
            font.family: Theme.fontFamily
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
