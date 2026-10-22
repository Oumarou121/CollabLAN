import QtQuick
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * MachineFiche - fiche « Vu par les autres » de Parametres > Ce poste : le
 * poste tel que les autres le voient (avant ou apres enregistrement du
 * nouveau nom) et les ecrans ou ce nom apparait.
 */
ColumnLayout {
    id: root

    property string shownName: ""           // vide = nom Windows
    property bool editing: false
    property bool isServer: false
    property string userName: ""

    spacing: 0

    component Where: Item {
        id: w
        property string icon: ""
        property string text: ""
        Layout.fillWidth: true
        implicitHeight: 31
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            LineIcon { anchors.verticalCenter: parent.verticalCenter; path: w.icon; size: 14; strokeWidth: 1.7; color: Theme.ink3 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: w.text; color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5) }
        }
    }

    CapsLabel { text: qsTr("Vu par les autres") }
    Text {
        Layout.topMargin: 6
        text: root.editing ? qsTr("Après enregistrement") : qsTr("Aujourd'hui")
        color: Theme.ink
        font.family: Theme.fontFamilySerif
        font.pixelSize: Theme.fs(20)
        font.weight: Theme.weightBold
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 12
        implicitHeight: 62
        radius: Theme.radiusSheet
        color: Theme.surface0
        border.width: 1
        border.color: Theme.lineStrong
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12
            Rectangle {
                implicitWidth: 36; implicitHeight: 36; radius: 18
                color: "transparent"
                border.width: 1
                border.color: Theme.lineStrong
                LineIcon { anchors.centerIn: parent; path: root.isServer ? Icons.server : Icons.monitor; size: 17; strokeWidth: 1.6; color: Theme.ink2 }
                Rectangle {
                    x: parent.width - width + 2; y: parent.height - height + 2
                    width: 15; height: 15; radius: 7.5
                    color: Theme.surface0
                    StateGlyph { anchors.centerIn: parent; kind: "online"; size: 10 }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: root.shownName.length ? root.shownName : qsTr("Nom Windows de la machine")
                    elide: Text.ElideRight
                    color: root.shownName.length ? Theme.ink : Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(13.5)
                    font.weight: Theme.weightSemibold
                    font.italic: root.shownName.length === 0
                }
                Text {
                    Layout.fillWidth: true
                    text: (root.userName.length ? root.userName + " · " : "") + qsTr("en ligne")
                    elide: Text.ElideRight
                    color: Theme.ink3
                    font.family: "Cascadia Mono"
                    font.pixelSize: Theme.fs(11.5)
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 12
        spacing: 0
        Where { icon: Icons.monitor; text: qsTr("Liste des postes et carte de l'accueil") }
        Where { icon: Icons.phone; text: qsTr("Appels entrants et journal d'appels") }
        Where { icon: Icons.exchange; text: qsTr("Dossiers de Transferts") }
        Where { icon: Icons.folder; text: qsTr("Membres des dossiers partagés") }
    }

    Text {
        Layout.fillWidth: true
        Layout.topMargin: 10
        text: qsTr("Le nom ne change rien aux autorisations : la machine reste reconnue par son identifiant et son certificat.")
        wrapMode: Text.WordWrap
        color: Theme.ink3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
    }
}
