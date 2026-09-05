import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * FolderDropzone - grande zone cliquable pour choisir un dossier local,
 * utilisee dans les modales de partage de dossier (creation + definition
 * du chemin local d'un dossier distant).
 *
 * Accepte desormais un vrai glisser-deposer depuis l'explorateur de
 * fichiers du systeme (DropArea) en plus du clic -> selecteur natif.
 * Le composant ne valide pas lui-meme que l'URL deposee est bien un
 * dossier (pas d'acces au systeme de fichiers cote QML) : c'est au
 * consommateur, via pathDropped, de verifier et de rejeter si besoin
 * (ex : afficher une erreur si un fichier a ete depose au lieu d'un
 * dossier).
 */
Rectangle {
    id: root

    property string path: ""
    property string emptyHint: qsTr("Cliquez ou glissez un dossier ici")
    property string emptySubHint: qsTr("Depuis l'explorateur de fichiers")
    property string filledActionLabel: qsTr("Changer…")

    // Nom + chemin parent, derives de path pour l'etat "rempli" (ex :
    // "C:/Users/marie/Documents/Projet" -> "Projet" / "C:/Users/marie/Documents").
    readonly property string folderName: {
        if (path.length === 0) return ""
        const normalized = path.replace(/[\\/]+$/, "")
        const idx = Math.max(normalized.lastIndexOf("/"), normalized.lastIndexOf("\\"))
        return idx >= 0 ? normalized.substring(idx + 1) : normalized
    }
    readonly property string parentPath: {
        if (path.length === 0) return ""
        const normalized = path.replace(/[\\/]+$/, "")
        const idx = Math.max(normalized.lastIndexOf("/"), normalized.lastIndexOf("\\"))
        return idx > 0 ? normalized.substring(0, idx) : ""
    }

    signal browseRequested()
    // Emis quand un element est depose sur la zone ; le consommateur
    // decide de l'accepter (path = url) ou de l'ignorer/afficher une
    // erreur si ce n'est pas un dossier valide.
    signal pathDropped(string droppedPath)

    Layout.fillWidth: true
    Layout.preferredHeight: path.length > 0 ? 68 : 116
    radius: Theme.radiusMedium
    color: dragArea.containsDrag ? Theme.primaryMuted
           : (dropzoneArea.containsMouse ? Theme.primaryMuted : Theme.surfaceAlt)
    border.width: dragArea.containsDrag ? 2 : 1.5
    border.color: (path.length > 0 || dragArea.containsDrag) ? Theme.primary : Theme.border
    scale: dragArea.containsDrag ? 1.015 : 1.0

    Behavior on Layout.preferredHeight { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    // Bordure en pointilles simulee (Qt Quick n'a pas de border.style
    // dashed) via un Canvas fin superpose. Pointilles plus resserres et
    // plus visibles pendant le survol d'un glisser-deposer.
    Canvas {
        id: dashedBorder
        anchors.fill: parent
        visible: root.path.length === 0
        readonly property bool dragging: dragArea.containsDrag
        onDraggingChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = Theme.primary
            ctx.lineWidth = dragging ? 2 : 1.5
            ctx.setLineDash(dragging ? [4, 4] : [6, 5])

            const inset = ctx.lineWidth / 2
            const left = inset
            const top = inset
            const right = width - inset
            const bottom = height - inset
            const radius = Math.max(0, Math.min(root.radius - inset,
                                                (right - left) / 2,
                                                (bottom - top) / 2))

            ctx.beginPath()
            ctx.moveTo(left + radius, top)
            ctx.lineTo(right - radius, top)
            ctx.quadraticCurveTo(right, top, right, top + radius)
            ctx.lineTo(right, bottom - radius)
            ctx.quadraticCurveTo(right, bottom, right - radius, bottom)
            ctx.lineTo(left + radius, bottom)
            ctx.quadraticCurveTo(left, bottom, left, bottom - radius)
            ctx.lineTo(left, top + radius)
            ctx.quadraticCurveTo(left, top, left + radius, top)
            ctx.stroke()
        }
    }

    MouseArea {
        id: dropzoneArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.browseRequested()
    }

    DropArea {
        id: dragArea
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: function (drop) {
            if (drop.urls.length > 0) {
                root.pathDropped(drop.urls[0].toString().replace(/^file:\/{2,3}/, ""))
            }
        }
    }

    // Etat vide : icone + texte d'invite centres.
    ColumnLayout {
        anchors.centerIn: parent
        visible: root.path.length === 0
        spacing: 4

        FaIcon {
            Layout.alignment: Qt.AlignHCenter
            glyph: dragArea.containsDrag ? "\uf063" : "\uf07b"
            font.pixelSize: 24
            color: Theme.primary
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: dragArea.containsDrag ? qsTr("Relâchez pour choisir ce dossier") : root.emptyHint
            color: Theme.text
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            visible: !dragArea.containsDrag
            text: root.emptySubHint
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSizeCaption
        }
    }

    // Etat rempli : nom du dossier mis en avant + chemin parent en
    // second plan (plus lisible qu'un chemin complet brut, surtout sur
    // les arborescences profondes), et bouton pour changer.
    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        visible: root.path.length > 0
        spacing: Theme.spacingSmall

        Rectangle {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: Theme.radiusSmall
            color: Theme.primaryMuted

            FaIcon {
                anchors.centerIn: parent
                glyph: "\uf07b"
                font.pixelSize: 16
                color: Theme.primary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Label {
                Layout.fillWidth: true
                text: root.folderName
                color: Theme.text
                font.bold: true
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
            }
            Label {
                Layout.fillWidth: true
                visible: root.parentPath.length > 0
                text: root.parentPath
                color: Theme.textTertiary
                elide: Text.ElideMiddle
                font.pixelSize: Theme.fontSizeCaption
            }
        }

        AppButton {
            text: root.filledActionLabel
            variant: "secondary"
            onClicked: root.browseRequested()
        }
    }
}
