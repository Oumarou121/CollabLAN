import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * DashboardCard - carte d'acces rapide utilisee sur l'ecran d'accueil
 * pour presenter les modules disponibles (Chat, Users, Transfert, ...).
 *
 * Design aligne (juillet) sur la maquette de reference SIRH-DOC : bandeau
 * degrade avec grande icone, indicateur "main" decoratif en coin, cercle
 * decoratif en fond de bandeau, pied de carte avec titre + chevron circulaire,
 * leger effet de "lift" (translation + bordure accentuee) au survol.
 *
 * Dimensions realignees sur la reference (admin-home.component.scss) :
 * bandeau 120px, radius 20px, icone ~2.8rem (45px).
 */
Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string description: ""

    signal clicked()

    // Police d'icones Font Awesome 4.7.0 (memes glyphes que la reference
    // admin-home.component.html/scss, fa fa-*), pour un rendu monochrome
    // fiable au lieu de "Segoe UI Symbol" (glyphes couleur selon l'OS).
    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }
    readonly property string iconFontFamily: iconFont.name

    // Jetons alignes sur LoginView (meme palette navy que le reste de
    // l'app : primary / primary-dark / primary-light / primary-mid).
    readonly property color primary: Theme.darkMode ? "#4E86B8" : "#2E6BAA"
    readonly property color primaryDark: Theme.darkMode ? "#3E6C99" : "#1E3A5F"
    readonly property color primaryLight: Theme.darkMode ? "#1B2531" : "#E8F1F9"
    readonly property color primaryMid: Theme.darkMode ? "#2E3D4E" : "#C2D9EE"
    readonly property color borderIdle: Theme.darkMode ? Theme.border : "#242E6BAA"

    readonly property int bannerHeight: 126

    Layout.preferredHeight: 170
    Layout.minimumWidth: 220
    radius: 20
    color: Theme.surface
    border.width: 1
    border.color: mouseArea.containsMouse ? root.primaryMid : root.borderIdle
    clip: true
    antialiasing: true

    Behavior on border.color { ColorAnimation { duration: 150 } }

    // Effet de "lift" au survol (equivalent translateY(-4px) de la maquette).
    // Utilise une transformation visuelle plutot que la propriete y, car
    // celle-ci est geree par le GridLayout parent - la modifier directement
    // entrait en conflit avec le positionnement et provoquait un
    // chevauchement visuel entre les cartes.
    transform: Translate {
        y: mouseArea.containsMouse ? -4 : 0
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Bandeau degrade -----------------------------------------------
        // root est desormais clip:true et porte le radius : plus besoin du
        // hack "hauteur+18 / radius dupplique" pour masquer les coins bas du
        // bandeau, ce qui evitait un leger artefact de rendu (liseré) sur les
        // coins hauts (deux rectangles arrondis superposes).
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.bannerHeight
            clip: true

            Rectangle {
                anchors.fill: parent
                topLeftRadius: 20
                topRightRadius: 20
                bottomLeftRadius: 0
                bottomRightRadius: 0

                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: root.primary }
                    GradientStop { position: 1.0; color: root.primaryDark }
                }

                // Cercle decoratif en fond de bandeau (cf. reference SCSS
                // ::after - width/height 110px, decale en bas-droite).
                Rectangle {
                    width: 110
                    height: 110
                    radius: 55
                    color: "#ffffff"
                    opacity: 0.07
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -24
                    anchors.bottomMargin: -28
                }

                // Grande icone, alignee en haut a gauche
                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingMedium
                    font.family: root.iconFontFamily
                    text: root.icon
                    font.pixelSize: 45
                    color: "#ffffff"
                    opacity: 0.94
                }

                // Indicateur "main" decoratif, en haut a droite - glisse
                // legerement au survol pour suggerer l'interaction.
                // Text {
                //     anchors.right: parent.right
                //     anchors.top: parent.top
                //     anchors.margins: Theme.spacingMedium
                //     text: "\u261D"
                //     font.pixelSize: 22
                //     color: "#ffffff"
                //     opacity: mouseArea.containsMouse ? 0.9 : 0.5
                //     x: mouseArea.containsMouse ? 2 : 0
                //     y: mouseArea.containsMouse ? -2 : 0
                //     Behavior on opacity { NumberAnimation { duration: 150 } }
                //     Behavior on x { NumberAnimation { duration: 150 } }
                //     Behavior on y { NumberAnimation { duration: 150 } }
                // }
            }
        }

        // ---- Pied : titre + chevron circulaire ------------------------------
        RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 35          // hauteur fixe au lieu de fillHeight
                Layout.alignment: Qt.AlignVCenter        // colle le pied en haut de sa zone
                Layout.bottomMargin: 7                 // padding-top: 14px (reference SCSS)
                Layout.leftMargin: Theme.spacingMedium
                Layout.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingSmall

            Label {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Theme.fontSizeSubheading
                font.bold: true
                font.family: Theme.fontFamily
                font.letterSpacing: -0.1
                color: Theme.text
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: mouseArea.containsMouse ? root.primary : root.primaryLight
                border.width: 1
                border.color: mouseArea.containsMouse ? root.primaryDark : root.primaryMid
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
                scale: mouseArea.containsMouse ? 1.1 : 1.0
                Behavior on scale { NumberAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "→"
                    color: mouseArea.containsMouse ? "#ffffff" : root.primary
                    font.pixelSize: 13
                    font.bold: true
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
