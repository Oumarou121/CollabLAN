import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppDialog - fenetre de dialogue du design system (creation, edition,
 * confirmation). Remplace le Dialog "brut" du style Basic (barre de titre
 * non themee) tout en gardant la facon de declarer le contenu : un
 * ColumnLayout enfant.
 *
 *   AppDialog {
 *       id: myDialog
 *       title: qsTr("Titre")
 *       dialogWidth: 420
 *       ColumnLayout { anchors.fill: parent; ... }
 *   }
 *
 * dialogHeight : hauteur imposee du CONTENU (-1 = hauteur naturelle).
 * busy         : voile + indicateur pendant une operation (clics bloques).
 */
Dialog {
    id: root

    property real dialogWidth: 460
    property real dialogHeight: -1
    // Glyphe Font Awesome optionnel devant le titre.
    property string headerIcon: ""
    // "accent" | "danger" | "warning" : teinte de la pastille d'icone.
    property string headerTone: "accent"
    property bool showCloseButton: true
    property bool showHeader: true
    readonly property int headerAreaHeight: 60
    property bool busy: false
    property string busyText: qsTr("Traitement en cours…")

    modal: true
    focus: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    standardButtons: Dialog.NoButton
    padding: 20
    topPadding: 6

    palette.window: Theme.surface0
    palette.base: Theme.surface1
    palette.alternateBase: Theme.surface0
    palette.button: Theme.surface1
    palette.text: Theme.ink
    palette.buttonText: Theme.ink
    palette.highlight: Theme.accentColor
    palette.highlightedText: Theme.accentInk

    // Hauteur naturelle du contenu declare. Calculee explicitement : le
    // voile "busy" ci-dessous est lui aussi un enfant du contenu, et avec
    // plusieurs enfants Popup ne deduit plus la taille implicite du contenu
    // (le dialogue se reduisait alors a son en-tete).
    readonly property real naturalContentHeight: {
        let h = 0
        for (let i = 0; i < root.contentChildren.length; i++) {
            const c = root.contentChildren[i]
            if (c !== busyVeil && c.visible !== false)
                h = Math.max(h, c.implicitHeight)
        }
        return h
    }
    readonly property real maxHeight: (parent ? parent.height : 800) - Theme.spacingXl * 2

    width: Math.min(dialogWidth, (parent ? parent.width : dialogWidth + Theme.spacingXl * 2) - Theme.spacingXl * 2)
    height: Math.min(maxHeight,
                     (dialogHeight > 0 ? dialogHeight : naturalContentHeight + topPadding + bottomPadding)
                     + (root.showHeader ? root.headerAreaHeight : 0))

    Overlay.modal: Rectangle {
        color: Theme.scrim
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationFast }
        NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: Theme.durationNormal; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
    }

    background: Rectangle {
        radius: Theme.radiusLarge
        color: Theme.surface0
        border.width: 1
        border.color: Theme.line

        // Ombre portee douce : fenetre flottante.
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.topMargin: 8
            anchors.bottomMargin: -16
            anchors.leftMargin: -4
            anchors.rightMargin: -4
            radius: parent.radius + 6
            color: Theme.shadowStrong
            opacity: 0.55
        }
    }

    font.family: Theme.fontFamily

    // Voile d'operation en cours.
    Rectangle {
        id: busyVeil
        anchors.fill: parent
        z: 100
        visible: root.busy
        color: Qt.rgba(Theme.surface0.r, Theme.surface0.g, Theme.surface0.b, 0.92)
        radius: Theme.radiusLarge

        MouseArea {
            anchors.fill: parent
            preventStealing: true
            onClicked: { /* bloque les clics pendant l'operation */ }
        }

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingMedium

            Spinner {
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.busy
                width: 32
                height: 32
            }

            Text {
                text: root.busyText
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.ink2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
            }
        }
    }

    header: Item {
        width: parent ? parent.width : 0
        implicitHeight: root.showHeader ? root.headerAreaHeight : 0
        height: implicitHeight
        visible: root.showHeader
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 12
            spacing: 12

            Rectangle {
                visible: root.headerIcon.length > 0
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 9
                color: root.headerTone === "danger" ? Theme.dangerSoft
                     : root.headerTone === "warning" ? Theme.warningSoft
                     : Theme.accentSoft

                FaIcon {
                    anchors.centerIn: parent
                    glyph: root.headerIcon
                    color: root.headerTone === "danger" ? Theme.dangerInk
                         : root.headerTone === "warning" ? Theme.warningInk
                         : (Theme.darkMode ? Theme.accentHover : Theme.accentColor)
                    font.pixelSize: Theme.fs(14)
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Theme.fs(16)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
                color: Theme.ink
                elide: Text.ElideRight
                Accessible.role: Accessible.Heading
            }

            IconButton {
                visible: root.showCloseButton
                glyph: ""
                size: 32
                iconSize: Theme.fs(13)
                tooltip: qsTr("Fermer")
                onClicked: root.close()
            }
        }
    }
}
