import QtQuick
import QtQuick.Layouts
import Themes

/*
 * IconButton - bouton circulaire/carre a glyphe unique, reutilise partout
 * ou l'on avait auparavant une Rectangle + Text + MouseArea dupliquee
 * (fleche retour, actions compactes, bouton d'envoi...).
 *
 * Utilise la meme police d'icones Font Awesome 4.7.0 que les cartes de
 * Home (Components/DashboardCard.qml), pour un rendu coherent d'un ecran
 * a l'autre au lieu des glyphes Unicode "systeme" (rendu variable selon
 * l'OS/la police par defaut).
 *
 * variant: "ghost" (transparent, survol discret) | "primary" (fond accent)
 *          | "danger" (fond erreur attenue)
 * enabledLook: decouple l'etat visuel "actif" de `enabled` Qt classique --
 * utile pour le bouton d'envoi, qui reste cliquable au clavier (Enter)
 * mais doit visuellement paraitre inactif tant que le champ est vide.
 */
Item {
    id: root

    property string glyph: ""
    property string variant: "ghost"
    property int size: 40
    property int iconSize: Math.round(size * 0.42)
    property int radius: Theme.radiusSmall
    property bool enabledLook: true
    property bool bold: false

    // Permet d'attacher un ToolTip depuis l'exterieur (ex. CallView) sans
    // dupliquer de MouseArea par-dessus le composant.
    readonly property alias hovered: mouseArea.containsMouse

    signal clicked()

    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }
    readonly property string iconFontFamily: iconFont.name

    Layout.preferredWidth: size
    Layout.preferredHeight: size
    implicitWidth: size
    implicitHeight: size

    readonly property bool isPrimary: variant === "primary"
    readonly property bool isDanger: variant === "danger"

    readonly property color baseColor: {
        if (!root.enabledLook) return Theme.surfaceAlt
        if (isPrimary) return mouseArea.pressed ? Theme.primaryHover : Theme.primary
        if (isDanger) return mouseArea.pressed ? Theme.error : Theme.errorMuted
        return mouseArea.containsMouse ? Theme.surfaceHover : "transparent"
    }

    readonly property color glyphColor: {
        if (!root.enabledLook) return Theme.textTertiary
        if (isPrimary || isDanger) return Theme.primaryText
        return Theme.text
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.baseColor

        Behavior on color { ColorAnimation { duration: 100 } }
    }

    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.glyphColor
        font.family: root.iconFontFamily
        font.pixelSize: root.iconSize
        font.bold: root.bold
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
