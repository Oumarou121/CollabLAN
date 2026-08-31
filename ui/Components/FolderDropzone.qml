import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * FolderDropzone - grande zone cliquable en pointilles pour choisir un
 * dossier local, utilisee dans les modales de partage de dossier
 * (creation + definition du chemin local d'un dossier distant).
 * Direction visuelle validee sur les maquettes (remplace la simple
 * ligne "chemin + bouton Parcourir…").
 *
 * Reste un clic classique (pas de drag&drop OS reel ici) mais invite
 * visuellement au depot.
 */
Rectangle {
    id: root

    property string path: ""
    property string emptyHint: qsTr("Cliquez pour choisir un dossier local")
    property string emptySubHint: qsTr("ou glissez-le ici")
    property string filledActionLabel: qsTr("Changer…")

    signal browseRequested()

    Layout.fillWidth: true
    Layout.preferredHeight: path.length > 0 ? 64 : 108
    radius: Theme.radiusMedium
    color: dropzoneArea.containsMouse ? Theme.primaryMuted : Theme.surfaceAlt
    border.width: 1.5
    border.color: path.length > 0 ? Theme.primary : Theme.border

    Behavior on Layout.preferredHeight { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 120 } }

    // Bordure en pointilles simulee (Qt Quick n'a pas de border.style
    // dashed) via un Canvas fin superpose.
    Canvas {
        anchors.fill: parent
        visible: root.path.length === 0
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = Theme.primary
            ctx.lineWidth = 1.5
            ctx.setLineDash([6, 5])
            ctx.strokeRect(1, 1, width - 2, height - 2)
        }
    }

    MouseArea {
        id: dropzoneArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.browseRequested()
    }

    // Etat vide : icone + texte d'invite centres.
    ColumnLayout {
        anchors.centerIn: parent
        visible: root.path.length === 0
        spacing: 4

        FaIcon {
            Layout.alignment: Qt.AlignHCenter
            glyph: "\uf07b"
            font.pixelSize: 22
            color: Theme.primary
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.emptyHint
            color: Theme.text
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.emptySubHint
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSizeCaption
        }
    }

    // Etat rempli : chemin choisi + bouton pour changer.
    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        visible: root.path.length > 0
        spacing: Theme.spacingSmall

        FaIcon {
            glyph: "\uf07b"
            font.pixelSize: 16
            color: Theme.primary
        }
        Label {
            Layout.fillWidth: true
            text: root.path
            color: Theme.text
            elide: Text.ElideMiddle
            font.pixelSize: Theme.fontSizeSmall
        }
        AppButton {
            text: root.filledActionLabel
            variant: "secondary"
            onClicked: root.browseRequested()
        }
    }
}
