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
    readonly property color primary: Theme.primary
    readonly property color primaryDark: Theme.primaryDeep
    readonly property color primaryLight: Theme.primaryMuted
    readonly property color primaryMid: Theme.selectionBackgroundHover
    readonly property color borderIdle: Theme.border

    readonly property int bannerHeight: 116

    Layout.preferredHeight: 184
    Layout.minimumWidth: 220
    radius: Theme.radiusLarge
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
        Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
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
            Layout.minimumHeight: root.bannerHeight
            clip: true

            Rectangle {
                anchors.fill: parent
                   topLeftRadius: Theme.radiusLarge
                   topRightRadius: Theme.radiusLarge
                bottomLeftRadius: 0
                bottomRightRadius: 0

                   color: root.primaryDark

                // Cercle decoratif en fond de bandeau (cf. reference SCSS
                // ::after - width/height 110px, decale en bas-droite).
                // Opacite plus elevee en dark mode : le degrade y est plus
                // clair (#4E86B8->#3E6C99) qu'en mode clair (#2E6BAA->#1E3A5F),
                // donc le cercle blanc s'y fondait davantage a opacite egale.
                Rectangle {
                    width: 110
                    height: 110
                    radius: 55
                    color: "#ffffff"
                       opacity: Theme.darkMode ? 0.08 : 0.05
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
                    font.pixelSize: Theme.fs(34)
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
                //     font.pixelSize: Theme.fs(22)
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

        // ---- Pied : titre + description + chevron circulaire ----------------
        RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 48
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                Layout.leftMargin: Theme.spacingMedium
                Layout.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingSmall

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

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

                Label {
                    Layout.fillWidth: true
                    text: root.description
                    visible: root.description.length > 0
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
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
                    font.pixelSize: Theme.fs(13)
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
