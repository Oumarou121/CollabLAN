import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * NetworkRegistry - le Registre de Ligne claire : les memes postes que
 * l'hemicycle, sous forme de tableau. Colonnes fixes, noms longs sur deux
 * lignes, tri par etat / poste / utilisateur, actions par ligne (au survol,
 * sur la ligne selectionnee ou au clavier). La selection et les filtres
 * d'etat sont ceux de l'accueil : ils sont communs aux deux vues.
 *
 * peers : [{ id, name, address, userName, status, server, transfer }]
 */
Item {
    id: root

    property var peers: []
    property string selectedId: ""
    property var hiddenStatuses: []
    property bool isAdmin: false
    // Fonctions fournies par l'hote : texte d'activite et de confiance.
    property var activityOf: function(p) { return "" }
    property var trustOf: function(p) { return "" }

    signal peerSelected(string peerId)
    signal messageRequested(var peer)
    signal fileRequested(var peer)
    signal callRequested(var peer)

    readonly property var stateOrder: ["calling", "transferring", "online", "busy", "away", "offline"]
    readonly property var stateLabels: ({
        calling: qsTr("En appel"), transferring: qsTr("En transfert"), online: qsTr("En ligne"),
        busy: qsTr("Occupé"), away: qsTr("Absent"), offline: qsTr("Hors ligne")
    })

    property string sortKey: "state"
    property int sortDir: 1

    function toggleSort(key) {
        if (root.sortKey === key)
            root.sortDir = -root.sortDir
        else {
            root.sortKey = key
            root.sortDir = 1
        }
    }

    readonly property var rows: {
        const key = root.sortKey, dir = root.sortDir, order = root.stateOrder
        return root.peers.filter(function(p) { return root.hiddenStatuses.indexOf(p.status) < 0 })
            .sort(function(a, b) {
                let r
                if (key === "name") r = String(a.name).localeCompare(String(b.name))
                else if (key === "user") r = String(a.userName || "~").localeCompare(String(b.userName || "~"))
                else r = (order.indexOf(a.status) - order.indexOf(b.status)) || String(a.name).localeCompare(String(b.name))
                return r * dir
            })
    }

    // Colonnes : largeurs fixes, la colonne « Poste » prend le reste.
    readonly property real colState: 124
    readonly property real colAddress: 118
    readonly property real colTrust: root.isAdmin ? 92 : 0
    readonly property real colActions: 96
    readonly property real colUser: Math.max(100, list.width * 0.15)
    readonly property real colActivity: Math.max(96, list.width * 0.13)
    readonly property real colName: Math.max(150, list.width - 20 - 12 - root.colState - root.colUser - root.colAddress
                                                  - root.colActivity - root.colTrust - root.colActions)

    component HeaderCell: AbstractButton {
        id: hc
        property string key: ""
        readonly property bool sortable: key.length > 0
        readonly property bool active: sortable && root.sortKey === key
        height: 34
        padding: 0
        enabled: sortable
        focusPolicy: sortable ? Qt.TabFocus : Qt.NoFocus
        Accessible.role: Accessible.ColumnHeader
        Accessible.name: hc.text + (hc.active ? (root.sortDir > 0 ? qsTr(", tri croissant") : qsTr(", tri décroissant")) : "")
        onClicked: root.toggleSort(hc.key)
        HoverHandler { enabled: hc.sortable; cursorShape: Qt.PointingHandCursor }

        background: Rectangle {
            color: "transparent"
            border.width: hc.visualFocus ? 2 : 0
            border.color: Theme.focusRing
        }
        contentItem: Row {
            spacing: 4
            CapsLabel {
                anchors.verticalCenter: parent.verticalCenter
                text: hc.text
                color: hc.active || hc.hovered ? Theme.ink2 : Theme.ink3
            }
            LineIcon {
                visible: hc.active
                anchors.verticalCenter: parent.verticalCenter
                path: root.sortDir > 0 ? Icons.chevronDown : "M6 14.5l6-6 6 6"
                size: 12
                strokeWidth: 2
                color: Theme.ink2
            }
        }
    }

    component RowAction: AbstractButton {
        id: ra
        property string iconPath: ""
        property string tip: ""
        width: 28
        height: 28
        hoverEnabled: true
        focusPolicy: Qt.TabFocus
        Accessible.name: ra.tip
        HoverHandler { cursorShape: ra.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        ToolTip.visible: ra.hovered && ra.tip.length > 0
        ToolTip.text: ra.tip
        ToolTip.delay: 400

        background: Rectangle {
            radius: Theme.radiusSheet
            color: ra.hovered && ra.enabled ? Theme.ink : "transparent"
            border.width: ra.visualFocus ? 2 : 0
            border.color: Theme.focusRing
        }
        contentItem: Item {
            LineIcon {
                anchors.centerIn: parent
                path: ra.iconPath
                size: 15
                strokeWidth: 1.7
                color: !ra.enabled ? Theme.inkDisabled : (ra.hovered ? Theme.inkOnInk : Theme.ink2)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- En-tete fixe ----------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 34

            Row {
                x: 20
                height: parent.height
                HeaderCell { width: root.colState; text: qsTr("État"); key: "state" }
                HeaderCell { width: root.colName; text: qsTr("Personne"); key: "user" }
                HeaderCell { width: root.colUser; text: qsTr("Poste"); key: "name" }
                HeaderCell { width: root.colAddress; text: qsTr("Adresse") }
                HeaderCell { width: root.colActivity; text: qsTr("Activité") }
                HeaderCell { width: root.colTrust; visible: root.isAdmin; text: qsTr("Confiance") }
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.lineStrong
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.rows
            keyNavigationEnabled: true
            currentIndex: {
                for (let i = 0; i < root.rows.length; i++)
                    if (root.rows[i].id === root.selectedId)
                        return i
                return -1
            }
            onCurrentIndexChanged: if (activeFocus && currentIndex >= 0 && root.rows[currentIndex]
                                       && root.rows[currentIndex].id !== root.selectedId)
                                       root.peerSelected(root.rows[currentIndex].id)
            Accessible.role: Accessible.Table
            Accessible.name: qsTr("Registre des postes")
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: modelData.id === root.selectedId
                readonly property bool off: modelData.status === "offline"
                readonly property bool showActions: rowHover.hovered || row.selected || row.activeFocus
                width: ListView.view.width
                height: Math.max(44, nameText.implicitHeight + 18)
                color: row.selected ? Theme.accentSoft : (rowHover.hovered ? Theme.selectWash : "transparent")
                Accessible.role: Accessible.Row
                Accessible.name: (modelData.userName || modelData.name) + ", " + (root.stateLabels[modelData.status] || "")
                                 + (row.selected ? qsTr(", sélectionné") : "")

                // Ligne selectionnee : filet d'encre a gauche (pas seulement la couleur).
                Rectangle {
                    visible: row.selected
                    width: 3
                    height: parent.height
                    color: Theme.ruleInk
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.line
                }

                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.peerSelected(row.modelData.id) }

                Row {
                    x: 20
                    height: parent.height

                    Item {
                        width: root.colState
                        height: parent.height
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: row.modelData.status; size: 12 }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.stateLabels[row.modelData.status] || ""
                                color: Theme.ink2
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(13)
                            }
                        }
                    }
                    Item {
                        width: root.colName
                        height: parent.height
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 12
                            Text {
                                id: nameText
                                width: parent.width
                                // La personne (compte connecte ou dernier vu), sinon le poste.
                                text: row.modelData.userName || row.modelData.name
                                color: Theme.ink
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(13)
                                font.weight: Theme.weightSemibold
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            CapsLabel {
                                visible: !!row.modelData.server
                                text: qsTr("Serveur")
                                font.pixelSize: Theme.fs(9.5)
                            }
                        }
                    }
                    Text {
                        width: root.colUser - 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.userName ? row.modelData.name : qsTr("aucun compte")
                        color: row.modelData.userName ? Theme.ink : Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        elide: Text.ElideRight
                    }
                    Item { width: 12; height: 1 }
                    Text {
                        width: root.colAddress
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.address
                        color: Theme.ink3
                        font.family: "Cascadia Mono, Consolas, monospace"
                        font.pixelSize: Theme.fs(12)
                        elide: Text.ElideRight
                    }
                    Text {
                        width: root.colActivity - 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.activityOf(row.modelData)
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                        elide: Text.ElideRight
                    }
                    Item { width: 8; height: 1 }
                    Text {
                        visible: root.isAdmin
                        width: root.colTrust
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.trustOf(row.modelData)
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                        elide: Text.ElideRight
                    }
                    Row {
                        width: root.colActions
                        anchors.verticalCenter: parent.verticalCenter
                        layoutDirection: Qt.RightToLeft
                        spacing: 2
                        opacity: row.showActions ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

                        RowAction {
                            iconPath: Icons.phone
                            tip: qsTr("Appeler %1").arg(row.modelData.userName || row.modelData.name)
                            enabled: !row.off && row.modelData.status !== "calling"
                            onClicked: root.callRequested(row.modelData)
                        }
                        RowAction {
                            iconPath: "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                            tip: qsTr("Envoyer un fichier à %1").arg(row.modelData.userName || row.modelData.name)
                            enabled: !row.off
                            onClicked: root.fileRequested(row.modelData)
                        }
                        RowAction {
                            iconPath: Icons.messageCircle
                            tip: qsTr("Message à %1").arg(row.modelData.userName || row.modelData.name)
                            enabled: !row.off && !!row.modelData.userName
                            onClicked: root.messageRequested(row.modelData)
                        }
                    }
                }
            }
        }
    }
}
