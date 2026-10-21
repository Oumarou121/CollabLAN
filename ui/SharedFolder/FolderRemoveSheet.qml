import QtQuick
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * FolderRemoveSheet - « Arrêter le partage » (dossier de ce poste) ou
 * « Retirer de ce poste » (dossier recu). removeFolder() ne supprime que
 * l'enregistrement dans LocaLink : les fichiers restent sur le disque.
 */
SheetModal {
    id: root

    property string folderName: ""
    property bool received: false
    property string ownerName: ""
    property string localPath: ""
    property int memberCount: 0

    signal confirmed()

    readonly property string safeName: root.folderName.replace(/&/g, "&amp;").replace(/</g, "&lt;")

    kicker: root.received ? qsTr("Retirer de ce poste") : qsTr("Arrêter le partage")
    title: root.received ? qsTr("Retirer « %1 » ?").arg(root.safeName) : qsTr("Arrêter de partager « %1 » ?").arg(root.safeName)
    sheetWidth: 460

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: warnRow.implicitHeight + 24
        color: Theme.dangerSoft
        Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
        RowLayout {
            id: warnRow
            x: 14
            y: 12
            width: parent.width - 28
            spacing: 12
            LineIcon { Layout.alignment: Qt.AlignTop; path: Icons.alertTriangle; size: 18; strokeWidth: 1.8; color: Theme.dangerInk }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.received
                          ? qsTr("Ce poste ne recevra plus les modifications de %1.").arg(root.ownerName.length ? root.ownerName : qsTr("son propriétaire"))
                          : (root.memberCount > 1 ? qsTr("Les %1 membres ne recevront plus les modifications de ce dossier.").arg(root.memberCount)
                             : root.memberCount === 1 ? qsTr("Le membre ne recevra plus les modifications de ce dossier.")
                             : qsTr("Le dossier ne sera plus indexé ni partagé."))
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(13)
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    textFormat: Text.StyledText
                    text: qsTr("Les fichiers restent intacts sur le disque%1 : seul l'enregistrement dans LocaLink est supprimé.")
                          .arg(root.localPath.length ? " (<tt>" + root.localPath.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</tt>)" : "")
                    color: Theme.ink2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                }
            }
        }
    }

    footer: [
        AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.closeRequested() },
        AppButton {
            variant: "danger"
            text: root.received ? qsTr("Retirer de ce poste") : qsTr("Arrêter le partage")
            onClicked: root.confirmed()
        }
    ]
}
