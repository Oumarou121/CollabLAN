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
    height: dialogHeight > 0
            ? Math.min(dialogHeight, (parent ? parent.height : dialogHeight + Theme.spacingXl * 2) - Theme.spacingXl * 2)
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
        radius: Theme.radiusLarge
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
    }

    Rectangle {
        anchors.fill: parent
        z: 100
        visible: root.busy
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.92)
        radius: Theme.radiusLarge

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

    // ---- Header stylise (remplace la barre de titre Qt par defaut) ----
    // IMPORTANT : Popup calcule la taille totale (donc celle du
    // background) a partir de implicitHeight du header/contentItem/
    // footer, pas de height. Sans implicitHeight explicite ici, le
    // background etait calcule trop petit et le contenu (les boutons en
    // bas des dialogs Admin, par ex.) debordait visuellement en dessous
    // de la carte.
    header: Item {
        width: parent ? parent.width : 0
        implicitHeight: 60
        height: implicitHeight
        clip: true

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceAlt
            radius: Theme.radiusLarge
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
