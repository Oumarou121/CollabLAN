import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * StatusBadge - pastille de statut du design system.
 *
 * tone  : "neutral" | "accent" | "info" | "success" | "warning"
 *         | "danger" ("error" accepte) | "call"
 * glyph : icone Font Awesome optionnelle ; a defaut un point de couleur.
 *         Le statut n'est jamais porte par la couleur seule : il y a
 *         toujours un libelle, et l'icone/point en double l'information.
 * compact : hauteur reduite (listes denses, tuiles).
 */
Rectangle {
    id: root

    property string tone: "neutral"
    property string text: ""
    property string glyph: ""
    property bool showDot: true
    property bool compact: false

    readonly property string t: root.tone === "error" ? "danger" : root.tone

    readonly property color bgColor: {
        switch (root.t) {
        case "success": return Theme.successSoft
        case "warning": return Theme.warningSoft
        case "danger": return Theme.dangerSoft
        case "info": return Theme.infoSoft
        case "accent": return Theme.accentSoft
        case "call": return Theme.callSoft
        default: return Theme.sunken
        }
    }
    readonly property color fgColor: {
        switch (root.t) {
        case "success": return Theme.successInk
        case "warning": return Theme.warningInk
        case "danger": return Theme.dangerInk
        case "info": return Theme.infoInk
        case "accent": return Theme.darkMode ? Theme.accentHover : Theme.accentColor
        case "call": return Theme.callInk
        default: return Theme.ink2
        }
    }
    readonly property color dotColor: {
        switch (root.t) {
        case "success": return Theme.successColor
        case "warning": return Theme.warningColor
        case "danger": return Theme.dangerColor
        case "info": return Theme.infoColor
        case "accent": return Theme.accentColor
        case "call": return Theme.callColor
        default: return Theme.ink3
        }
    }

    implicitWidth: row.implicitWidth + (root.compact ? 14 : 18)
    implicitHeight: root.compact ? 20 : 22
    radius: Theme.radiusPill
    color: root.bgColor
    Accessible.role: Accessible.StaticText
    Accessible.name: root.text

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Rectangle {
            visible: root.glyph.length === 0 && root.showDot
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            radius: 3
            color: root.dotColor
        }

        FaIcon {
            visible: root.glyph.length > 0
            glyph: root.glyph
            color: root.fgColor
            font.pixelSize: Theme.fs(root.compact ? 10 : 11)
        }

        Text {
            text: root.text
            color: root.fgColor
            font.pixelSize: Theme.fs(root.compact ? 11 : 12)
            font.weight: Theme.weightSemibold
            font.family: Theme.fontFamily
        }
    }
}
