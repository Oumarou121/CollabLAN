import QtQuick
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * FolderInviteSheet - un dossier vient d'etre partage avec ce poste
 * (folderShareConfirmationRequested) : droit accorde, emplacement propose,
 * « Plus tard » (declineFolderShare : l'acces est conserve, le dossier reste
 * dans la liste sans emplacement) ou « Accepter » (acceptFolderShare).
 * Plusieurs invitations se presentent une par une (« 1 sur 2 »).
 */
SheetModal {
    id: root

    property var folderId: -1
    property string folderName: ""
    property string ownerName: ""
    property string suggestedPath: ""
    property bool allowWrite: false
    property int queueIndex: 0
    property int queueTotal: 0

    signal accepted()
    signal postponed()

    readonly property string safe: root.folderName.replace(/&/g, "&amp;").replace(/</g, "&lt;")

    closable: false
    kicker: qsTr("Nouveau dossier partagé avec vous")
    boldTitle: false
    title: root.ownerName.length
           ? qsTr("<b>%1</b> vous partage <b>« %2 »</b>").arg(root.ownerName.replace(/&/g, "&amp;").replace(/</g, "&lt;")).arg(root.safe)
           : qsTr("Un dossier vous est partagé : <b>« %1 »</b>").arg(root.safe)
    counter: root.queueTotal > 1 ? qsTr("%1 sur %2").arg(root.queueIndex).arg(root.queueTotal) : ""
    sheetWidth: 470

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Rectangle {
            implicitWidth: permRow.implicitWidth + 22
            implicitHeight: 24
            radius: 12
            color: "transparent"
            border.width: 1
            border.color: root.allowWrite ? Theme.successColor : Theme.lineStrong
            Row {
                id: permRow
                anchors.centerIn: parent
                spacing: 6
                LineIcon { anchors.verticalCenter: parent.verticalCenter; path: root.allowWrite ? Icons.pencil : Icons.eye; size: 13; strokeWidth: 1.8; color: root.allowWrite ? Theme.successInk : Theme.ink2 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.allowWrite ? qsTr("Lecture et écriture") : qsTr("Lecture seule")
                    color: root.allowWrite ? Theme.successInk : Theme.ink2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Theme.weightSemibold
                }
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 14
            text: qsTr("Si vous acceptez, son contenu sera copié puis tenu à jour dans :")
            color: Theme.ink2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(13)
            wrapMode: Text.WordWrap
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: pathText.implicitHeight + 20
            radius: Theme.radiusSheet
            color: Theme.surface0
            border.width: 1
            border.color: Theme.line
            Text {
                id: pathText
                x: 12
                y: 10
                width: parent.width - 24
                text: root.suggestedPath
                color: Theme.ink
                font.family: "Cascadia Mono"
                font.pixelSize: Theme.fs(12.5)
                font.weight: Theme.weightMedium
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 10
            text: qsTr("« Plus tard » ne refuse pas l'accès : le dossier reste dans votre liste et vous pourrez choisir son emplacement quand vous voudrez.")
            color: Theme.ink3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12)
            wrapMode: Text.WordWrap
        }
    }

    footer: [
        AppButton { variant: "line"; text: qsTr("Plus tard"); onClicked: root.postponed() },
        AppButton { variant: "ink"; text: qsTr("Accepter"); onClicked: root.accepted() }
    ]
}
