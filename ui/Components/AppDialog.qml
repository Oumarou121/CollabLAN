import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppDialog - Dialog reutilisable, stylise, pour remplacer les
 * QtQuick.Controls.Dialog "bruts" utilises jusqu'ici (Admin,
 * SharedFolder, ...).
 *
 * Pourquoi : le style Qt Quick Controls global de l'appli est "Basic"
 * (voir app/main.cpp), donc un Dialog standard affiche une barre de
 * titre par defaut non themee (police systeme, pas de Theme.text, pas
 * d'arrondi), en contraste avec le reste de l'UI qui est tres
 * travaillee. AppDialog remplace le header et l'overlay pour rester
 * coherent avec le style "corporate" bleu-gris (Login/Home/Settings/
 * Admin), sans changer la facon de declarer le contenu : on continue a
 * declarer un ColumnLayout enfant comme avant.
 *
 * Usage (identique aux Dialog existants) :
 *   AppDialog {
 *       id: myDialog
 *       title: qsTr("Titre")
 *       dialogWidth: 420
 *
 *       ColumnLayout {
 *           anchors.fill: parent
 *           spacing: Theme.spacingMedium
 *           // ... champs ...
 *       }
 *   }
 */
Dialog {
    id: root

    // Largeur "souhaitee", plafonnee a la largeur de la fenetre moins
    // marge (utile en fenetre partagee / petit ecran).
    property real dialogWidth: 460
    // Hauteur "souhaitee" optionnelle. -1 (defaut) = hauteur automatique
    // selon le contenu (implicitHeight). Si fournie, elle est plafonnee
    // a la hauteur de la fenetre moins marge : sans ca, un dialog a
    // hauteur fixe (ex. 680px) pouvait deborder de la fenetre a sa
    // taille minimale (640x480, cf. Main.qml minimumHeight).
    property real dialogHeight: -1
    // Icone Font Awesome optionnelle affichee a cote du titre.
    property string headerIcon: ""
    // Masque le bouton fermer (X) du header, pour les dialogs qui ne
    // doivent etre fermes que via une action explicite (ex. confirmation
    // bloquante).
    property bool showCloseButton: true
    // Masque entierement la barre d'en-tete (icone+titre+fermer), pour
    // les modales de type "alerte" qui composent leur propre en-tete
    // visuel dans le contenu (icone centree en grand format, cf.
    // "Acces refuse"). NB: on ne peut pas se contenter de visible:false
    // sur le header -- Popup se base sur son implicitHeight pour
    // calculer la taille totale de la fenetre (cf. commentaire plus bas),
    // donc un header invisible mais de hauteur non nulle laisse un bandeau
    // vide en haut de la modale.
    property bool showHeader: true
    // Hauteur reelle du header (icone+titre+croix), reutilisee a la fois
    // par le header lui-meme (ligne ~163) et par le calcul de `height`
    // ci-dessous. Avant, ce `60` etait duplique/oublie : dialogHeight
    // fourni par l'appelant (cf. AdminView.qml) ne comptait que le
    // contenu + padding, jamais le header, ce qui faisait deborder le
    // contenu (ex. les boutons Annuler/Ajouter) sous la carte de la
    // modale des que showHeader:true.
    readonly property int headerAreaHeight: 60
    // Etat d'une operation longue : verrouille le contenu et affiche un
    // retour visuel uniforme dans toutes les modales.
    property bool busy: false
    property string busyText: qsTr("Traitement en cours…")

    modal: true
    focus: true
    anchors.centerIn: parent
    standardButtons: Dialog.NoButton
    padding: Theme.spacingMedium

    // Certains contrôles Qt Quick utilisent encore la palette native si elle
    // n'est pas définie explicitement. Cela produisait des surfaces noires
    // dans les modales en thème clair (ComboBox, ScrollView, champs, etc.).
    palette.window: Theme.surface
    palette.base: Theme.surfaceAlt
    palette.alternateBase: Theme.surface
    palette.button: Theme.surfaceAlt
    palette.text: Theme.text
    palette.buttonText: Theme.text
    palette.highlight: Theme.primary
    palette.highlightedText: Theme.primaryText

    width: Math.min(dialogWidth, (parent ? parent.width : dialogWidth + Theme.spacingXl * 2) - Theme.spacingXl * 2)
    // dialogHeight (fourni par l'appelant) represente la hauteur du
    // CONTENU + son padding (cf. commentaires dans AdminView.qml : "Hauteur
    // calculee sur le contenu reel"). On y ajoute ici la hauteur du header
    // pour obtenir la hauteur totale reelle du Popup, sinon le contenu
    // deborde de la carte des que showHeader:true.
    height: dialogHeight > 0
            ? Math.min(dialogHeight + (root.showHeader ? root.headerAreaHeight : 0),
                        (parent ? parent.height : dialogHeight + Theme.spacingXl * 2) - Theme.spacingXl * 2)
            : implicitHeight

    // ---- Overlay d'arriere-plan assombri, coherent avec Theme.overlay --
    Overlay.modal: Rectangle {
        color: Theme.overlay
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 120; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 }
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
    }

    font.family: Theme.fontFamily

    Rectangle {
        anchors.fill: parent
        z: 100
        visible: root.busy
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.92)
        radius: Theme.radiusSmall

        MouseArea {
            anchors.fill: parent
            preventStealing: true
            onClicked: { /* bloque les clics pendant l'operation */ }
        }

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingMedium

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.busy
                width: 42
                height: 42
            }

            Label {
                text: root.busyText
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
            }
        }
    }

    // NB : une tentative anterieure de surcharger `contentItem` ici pour
    // remonter automatiquement l'implicitHeight du contenu a ete
    // abandonnee -- elle cassait le rattachement automatique des enfants
    // declares par l'appelant (le formulaire se retrouvait rendu hors de
    // la carte, sur le fond de l'ecran). A la place, chaque dialog qui a
    // besoin d'une hauteur automatique calcule sa propre `dialogHeight`
    // a partir de l'implicitHeight de son ColumnLayout (cf. AdminView.qml,
    // dialogs "Ajouter une machine"/"Ajouter un utilisateur"/"Acces
    // refuse"), sans jamais utiliser `anchors.fill: parent` sur ce
    // ColumnLayout (seulement `width: parent.width`) pour eviter une
    // dependance circulaire.

    // ---- Header stylise (remplace la barre de titre Qt par defaut) ----
    // IMPORTANT : Popup calcule la taille totale (donc celle du
    // background) a partir de implicitHeight du header/contentItem/
    // footer, pas de height. Sans implicitHeight explicite ici, le
    // background etait calcule trop petit et le contenu (les boutons en
    // bas des dialogs Admin, par ex.) debordait visuellement en dessous
    // de la carte.
    header: Item {
        width: parent ? parent.width : 0
        implicitHeight: root.showHeader ? root.headerAreaHeight : 0
        height: implicitHeight
        visible: root.showHeader
        clip: true

        // NB : QtQuick.Rectangle n'a pas de radius par coin (pas de
        // bottomLeftRadius/bottomRightRadius, indisponibles avant Qt 6.7,
        // et le projet cible juste "Qt6" sans version minor precise). Le
        // rectangle etait arrondi sur ses 4 coins alors que le header ne
        // doit l'etre qu'en haut (pour suivre l'arrondi de la carte) --
        // ca laissait un petit "mordillage" arrondi visible aux 2 coins
        // bas du bandeau, la ou il rejoint le contenu blanc en dessous.
        // Fix : on etend le rectangle sous la zone visible du header
        // (qui a clip:true) de `radius` pixels ; ses coins bas arrondis
        // se retrouvent alors hors du clip et sont simplement coupes,
        // ne laissant que des bords bas bien droits.
        Rectangle {
            x: 0
            y: 0
            width: parent.width
            height: parent.height + Theme.radiusSmall
            color: Theme.surfaceAlt
            radius: Theme.radiusSmall
        }

        // Meme police Font Awesome 4.7 embarquee que les autres
        // composants (DashboardCard, IconButton...), pour un rendu
        // coherent du glyphe d'en-tete optionnel.
        FontLoader {
            id: headerIconFont
            source: "../Assets/fonts/fontawesome-webfont.ttf"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingMedium
            anchors.rightMargin: Theme.spacingSmall
            spacing: Theme.spacingMedium

            Text {
                visible: root.headerIcon.length > 0
                text: root.headerIcon
                font.family: headerIconFont.name
                font.pixelSize: Theme.fontSizeSubheading
                color: Theme.primary
            }

            Label {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Theme.fontSizeSubheading
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.text
                elide: Text.ElideRight
            }

            IconButton {
                visible: root.showCloseButton
                glyph: "\u2715"
                size: 32
                onClicked: root.close()
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.border
        }
    }
}
