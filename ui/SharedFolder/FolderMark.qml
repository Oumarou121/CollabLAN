import QtQuick
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * FolderMark - marque d'un dossier partage (Ligne claire) : plein d'encre
 * pour un dossier partage par ce poste, filet pour un dossier recu, ambre
 * quand il attend encore un emplacement. La pastille dit l'etat qui compte :
 * "conflict" (croix rouge), "sync" (point d'encre), "indexing" (indicateur
 * tournant), "away" (losange : emplacement a choisir).
 */
Item {
    id: root

    property bool received: false
    property bool noPath: false
    property string pip: ""
    property real size: 40

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSheet
        color: !root.received ? Theme.ink : (root.noPath ? Theme.warningSoft : "transparent")
        border.width: root.received ? 1 : 0
        border.color: root.noPath ? Theme.warningColor : Theme.lineStrong
        LineIcon {
            anchors.centerIn: parent
            path: root.received ? Icons.folderIn : Icons.folder
            size: Math.round(root.size * 0.46)
            strokeWidth: 1.6
            color: !root.received ? Theme.inkOnInk : (root.noPath ? Theme.warningInk : Theme.ink2)
        }
    }

    Rectangle {
        visible: root.pip.length > 0
        x: root.width - width + 4
        y: root.height - height + 4
        width: 15
        height: 15
        radius: 7.5
        color: Theme.bg
        StateGlyph {
            visible: root.pip !== "indexing"
            anchors.centerIn: parent
            size: 10
            kind: root.pip === "conflict" ? "error" : root.pip === "sync" ? "transferring" : "decision"
        }
        Spinner {
            visible: root.pip === "indexing"
            running: visible
            anchors.centerIn: parent
            width: 10
            height: 10
            lineWidth: 1.6
        }
    }
}
