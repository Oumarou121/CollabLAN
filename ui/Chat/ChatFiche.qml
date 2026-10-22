import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * ChatFiche - fiche de la discussion ouverte (Ligne claire), colonne droite
 * repliable. Personne : presence, poste et adresse tant qu'elle est sur le
 * reseau local, Appeler, Envoyer un fichier, Dossier d'echanges (Transferts).
 * Groupe : nombre de membres (la liste n'est pas exposee a l'interface),
 * messages charges, non lus ; pour son proprietaire, Renommer et Supprimer.
 */
Rectangle {
    id: root

    property string name: ""
    property bool group: false
    property string status: "offline"
    property string machineName: ""
    property string address: ""
    property int memberCount: 0
    property int messageCount: 0
    property int unreadCount: 0
    readonly property bool reachable: root.machineName.length > 0
    property bool canManageGroup: false     // proprietaire du groupe

    signal callRequested()
    signal sendFileRequested()
    signal exchangesRequested()
    signal renameRequested()
    signal deleteRequested()

    color: Theme.bg

    function presenceWord(s) {
        switch (s) {
        case "online": return qsTr("En ligne")
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        }
        return qsTr("Hors ligne")
    }

    component Fact: RowLayout {
        property string key: ""
        property string value: ""
        Layout.fillWidth: true
        Text { text: parent.key; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: parent.value; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); elide: Text.ElideMiddle; font.features: ({ "tnum": 1 }) }
    }
    component FicheAction: AbstractButton {
        id: fa
        property string iconPath: ""
        property string hint: ""
        property bool first: false
        Layout.fillWidth: true
        implicitHeight: 40
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: fa.text
        HoverHandler { cursorShape: fa.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Rectangle {
            color: fa.hovered && fa.enabled ? Theme.ink : "transparent"
            border.width: fa.visualFocus ? 2 : 0
            border.color: Theme.focusRing
            Rectangle { visible: !fa.first; width: parent.width; height: 1; color: Theme.lineStrong }
        }
        contentItem: RowLayout {
            spacing: 10
            LineIcon { Layout.leftMargin: 12; path: fa.iconPath; size: 15; strokeWidth: 1.8; color: !fa.enabled ? Theme.inkDisabled : fa.hovered ? Theme.inkOnInk : Theme.ink3 }
            Text { Layout.fillWidth: true; text: fa.text; color: !fa.enabled ? Theme.inkDisabled : fa.hovered ? Theme.inkOnInk : Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold }
            Text { Layout.rightMargin: 12; visible: fa.hint.length > 0; text: fa.hint; color: fa.hovered && fa.enabled ? Theme.inkOnInk : Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 22
        anchors.rightMargin: 4
        contentWidth: width
        contentHeight: col.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            y: 16
            width: parent.width - 18
            spacing: 0

            CapsLabel { text: root.group ? qsTr("Groupe") : qsTr("Fiche") }
            ChatMonogram {
                Layout.topMargin: 10
                size: 56
                label: root.name
                group: root.group
                status: root.group ? "" : root.status
                memberCount: root.memberCount
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 10
                text: root.name
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(21)
                font.weight: Theme.weightBold
                wrapMode: Text.WordWrap
            }
            Row {
                visible: !root.group
                Layout.topMargin: 6
                spacing: 7
                StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: root.status === "online" || root.status === "away" || root.status === "busy" ? root.status : "offline"; size: 10 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: root.presenceWord(root.status); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: 14; Layout.bottomMargin: 10; Layout.preferredHeight: 1; color: Theme.line }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 7
                Fact { visible: !root.group; key: qsTr("Poste"); value: root.reachable ? root.machineName : "—" }
                Fact { visible: !root.group; key: qsTr("Adresse"); value: root.reachable && root.address.length ? root.address : "—" }
                Fact { visible: root.group; key: qsTr("Membres"); value: root.memberCount > 0 ? qsTr("%1, vous compris").arg(root.memberCount) : "—" }
                Fact { key: qsTr("Messages chargés"); value: String(root.messageCount) }
                Fact { visible: root.group; key: qsTr("Non lus"); value: String(root.unreadCount) }
            }

            Rectangle {
                visible: !root.group
                Layout.fillWidth: true
                Layout.topMargin: 16
                implicitHeight: actions.implicitHeight + 2
                radius: Theme.radiusSheet
                color: "transparent"
                border.width: 1
                border.color: Theme.lineStrong
                clip: true
                ColumnLayout {
                    id: actions
                    x: 1; y: 1
                    width: parent.width - 2
                    spacing: 0
                    FicheAction { first: true; text: qsTr("Appeler"); iconPath: Icons.phone; enabled: root.reachable; hint: root.reachable ? "" : qsTr("hors ligne"); onClicked: root.callRequested() }
                    FicheAction { text: qsTr("Envoyer un fichier"); iconPath: Icons.arrowUp; enabled: root.reachable; onClicked: root.sendFileRequested() }
                    FicheAction { text: qsTr("Dossier d'échanges"); iconPath: Icons.folder; hint: qsTr("Transferts"); onClicked: root.exchangesRequested() }
                }
            }
            Rectangle {
                visible: root.group && root.canManageGroup
                Layout.fillWidth: true
                Layout.topMargin: 16
                implicitHeight: groupActions.implicitHeight + 2
                radius: Theme.radiusSheet
                color: "transparent"
                border.width: 1
                border.color: Theme.lineStrong
                clip: true
                ColumnLayout {
                    id: groupActions
                    x: 1; y: 1
                    width: parent.width - 2
                    spacing: 0
                    FicheAction { first: true; text: qsTr("Renommer le groupe"); iconPath: Icons.pencil; onClicked: root.renameRequested() }
                    FicheAction { text: qsTr("Supprimer le groupe"); iconPath: Icons.trash; hint: qsTr("pour tous"); onClicked: root.deleteRequested() }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 14
                wrapMode: Text.WordWrap
                text: root.group ? qsTr("La liste des membres n'est pas encore affichée ici ; seul leur nombre est connu.")
                      : root.reachable ? qsTr("Poste et adresse viennent du réseau local, tant que la personne est connectée.")
                      : qsTr("Hors ligne : les messages lui seront remis à sa prochaine connexion.")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
            }
        }
    }
}
