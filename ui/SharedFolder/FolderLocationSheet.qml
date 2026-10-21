import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * FolderLocationSheet - « Où recevoir… » : dossier de destination d'un
 * dossier recu (setFolderLocalPath). Le choix reste explicite : l'emplacement
 * propose d'apres les parametres n'est qu'une indication (le dossier doit
 * exister ; on le choisit ou on le glisse ici).
 */
SheetModal {
    id: root

    property string folderName: ""
    property string ownerName: ""
    property string suggestedPath: ""
    property bool hasPath: false            // changement d'un emplacement existant
    property string localPath: ""

    signal browseRequested()
    signal confirmed()

    function cleanUrl(url) {
        let path = decodeURIComponent(url.toString()).replace(/^file:\/\//, "")
        if (/^\/[A-Za-z]:/.test(path)) path = path.substring(1)
        return path
    }

    kicker: qsTr("Emplacement sur ce poste")
    boldTitle: false
    title: qsTr("Où recevoir <b>« %1 »</b> ?").arg(root.folderName.replace(/&/g, "&amp;").replace(/</g, "&lt;"))
    lead: root.hasPath
          ? qsTr("Choisissez le dossier de ce poste dans lequel ce partage est tenu à jour.")
          : qsTr("%1 partage ce dossier avec vous. Ses fichiers seront copiés puis tenus à jour ici.")
            .arg(root.ownerName.length ? root.ownerName : qsTr("Un autre poste"))
    sheetWidth: 480

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text { Layout.bottomMargin: 6; text: qsTr("Dossier de destination"); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightSemibold }

        Item {
            id: box
            Layout.fillWidth: true
            implicitHeight: boxRow.implicitHeight + 32
            readonly property bool filled: root.localPath.length > 0
            Rectangle {
                anchors.fill: parent
                visible: box.filled
                radius: Theme.radiusSheet
                color: Theme.surface0
                border.width: 1
                border.color: Theme.ruleInk
            }
            Shape {
                visible: !box.filled
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: boxHover.hovered || boxDrop.containsDrag ? Theme.selectWash : "transparent"
                    strokeColor: boxHover.hovered || boxDrop.containsDrag ? Theme.ink3 : Theme.lineStrong
                    strokeWidth: 1.5
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [3, 2.5]
                    startX: 1; startY: 1
                    PathLine { x: box.width - 1; y: 1 }
                    PathLine { x: box.width - 1; y: box.height - 1 }
                    PathLine { x: 1; y: box.height - 1 }
                    PathLine { x: 1; y: 1 }
                }
            }
            HoverHandler { id: boxHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.browseRequested() }
            DropArea {
                id: boxDrop
                anchors.fill: parent
                onDropped: function(drop) { if (drop.hasUrls && drop.urls.length > 0) root.localPath = root.cleanUrl(drop.urls[0]) }
            }
            RowLayout {
                id: boxRow
                anchors.verticalCenter: parent.verticalCenter
                x: 16
                width: parent.width - 32
                spacing: 12
                LineIcon { path: Icons.folderIn; size: 24; strokeWidth: 1.4; color: Theme.ink2 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: box.filled ? root.localPath : qsTr("Déposez le dossier de destination ici")
                        color: Theme.ink
                        font.family: box.filled ? "Cascadia Mono" : Theme.fontFamilySerif
                        font.pixelSize: box.filled ? Theme.fs(12.5) : Theme.fs(15)
                        font.weight: box.filled ? Theme.weightMedium : Theme.weightBold
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                    Text {
                        Layout.fillWidth: true
                        text: box.filled ? qsTr("Un dossier vide est préférable.")
                              : (root.suggestedPath.length ? qsTr("ou cliquez pour le choisir · proposé : %1").arg(root.suggestedPath) : qsTr("ou cliquez pour le choisir"))
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }
                AppButton { variant: box.filled ? "line" : "ink"; size: "small"; text: box.filled ? qsTr("Changer…") : qsTr("Choisir…"); onClicked: root.browseRequested() }
            }
        }
    }

    footer: [
        AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.closeRequested() },
        AppButton { variant: "ink"; text: qsTr("Recevoir ici"); enabled: root.localPath.length > 0; onClicked: root.confirmed() }
    ]
}
