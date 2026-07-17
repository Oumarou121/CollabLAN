import QtQuick
import Themes

/*
 * BrandMark - Logo de marque CollabLAN
 *
 * Composant reutilisable affichant le logo fourni par l'equipe dans un
 * badge clair, pour rester lisible aussi bien en theme clair qu'en theme
 * sombre. Utilise sur l'ecran Login et l'ecran Home.
 */
Rectangle {
    id: root

    property int size: 40

    width: size
    height: size
    radius: size * 0.28
    color: Theme.darkMode ? "#232A35" : "#FFFFFF"
    border.width: 1
    border.color: Theme.border

    Image {
        anchors.fill: parent
        anchors.margins: root.size * 0.12
        source: "../Assets/logo.png"
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
}
