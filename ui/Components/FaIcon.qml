import QtQuick

/*
 * FaIcon - simple glyphe Font Awesome 4.7.0 (icone seule, sans etat de
 * survol/clic - pour ca voir Components/IconButton.qml). Charge sa propre
 * police, comme le reste des ecrans de l'application (DashboardCard,
 * ConversationsView, IconButton...), pour un rendu monochrome/teinte
 * fiable a la place des glyphes Unicode "systeme".
 */
Text {
    id: root

    property string glyph: ""

    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }

    text: root.glyph
    font.family: iconFont.name
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
