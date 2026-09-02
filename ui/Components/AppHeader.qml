import QtQuick
import QtQuick.Layouts
import Themes

/*
 * AppHeader - barre superieure standard des ecrans secondaires (Postes
 * connectes, Parametres, Appels...).
 *
 * Factorise un motif jusque-la duplique a l'identique dans plusieurs
 * vues (Rectangle 64px + separateur 1px + bouton retour circulaire 36px
 * + titre + badge optionnel a droite) : le dupliquer rendait la moindre
 * evolution (hauteur, taille du bouton retour...) sujette a divergence
 * entre ecrans (cf. Home qui etait reste a 76px pendant que les autres
 * etaient a 64px).
 *
 * Usage minimal :
 *   AppHeader {
 *       title: qsTr("Parametres")
 *       onBackRequested: root.backRequested()
 *   }
 *
 * Avec une icone de contexte (comme le badge "Appels" dans CallView) et
 * du contenu a droite (badge, compteur...), a placer dans le slot par
 * defaut :
 *   AppHeader {
 *       title: qsTr("Appels")
 *       leadingIcon: "\uf095"
 *       leadingIconFontFamily: root.iconFontFamily
 *       onBackRequested: root.backRequested()
 *
 *       Rectangle { ... } // ajoute apres l'espace extensible
 *   }
 */
Rectangle {
    id: root

    // Propriete Layout habituelle : le parent (ColumnLayout) doit fixer
    // Layout.fillWidth: true sur cet element, comme pour n'importe quel
    // autre enfant de ColumnLayout.
    Layout.fillWidth: true
    Layout.preferredHeight: 72
    color: Theme.surface

    // Titre affiche apres le bouton retour / l'icone de contexte.
    property string title: ""

    // Masque le bouton retour (ex : ecran racine, ou reutilisation en
    // panneau embarque comme ConversationsView.showBackButton).
    property bool showBackButton: true

    // Icone de contexte optionnelle (glyphe Font Awesome) affichee dans
    // un badge carre entre le bouton retour et le titre - ex. l'icone
    // "telephone" de CallView. Vide = pas de badge.
    property string leadingIcon: ""
    property string leadingIconFontFamily: ""

    signal backRequested()

    // Separateur bas : desactivable quand l'ecran appelant empile un
    // second bandeau juste en dessous (ex. la ligne d'onglets d'AdminView)
    // et prefere garder un seul trait, place plus bas, plutot que deux.
    property bool showDivider: true

    // Emplacement libre pour le contenu de droite (badge de comptage,
    // pastille de statut...), ajoute apres l'espace extensible. Toute
    // Item declaree comme enfant direct de AppHeader dans le QML
    // appelant atterrit ici plutot que d'etre un enfant classique de
    // Rectangle, via cet alias sur le default property.
    default property alias trailingContent: trailingRow.data

    // Separateur bas, identique sur tous les ecrans qui utilisaient deja
    // ce motif.
    Rectangle {
        visible: root.showDivider
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingLarge
        anchors.rightMargin: Theme.spacingLarge
        spacing: Theme.spacingMedium

        IconButton {
            visible: root.showBackButton
            glyph: "\uf060"
            variant: "ghost"
            size: 40
            onClicked: root.backRequested()
        }

        Rectangle {
            visible: root.leadingIcon.length > 0
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: Theme.radiusMedium
            color: Theme.primaryMuted

            Text {
                anchors.centerIn: parent
                text: root.leadingIcon
                font.family: root.leadingIconFontFamily
                font.pixelSize: 15
                color: Theme.primary
            }
        }

        Text {
            text: root.title
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            font.family: Theme.fontFamily
            color: Theme.text
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            // Ne s'etire jamais : c'est l'Item suivant (spacer) qui
            // absorbe l'espace disponible, pour que le titre garde une
            // largeur naturelle et que trailingContent reste colle a
            // droite quelle que soit la resolution.
            Layout.fillWidth: false
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            id: trailingRow
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacingSmall
        }
    }
}
