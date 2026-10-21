import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * UsersView - "Postes" : le parc local tel que le voit ce poste.
 *
 * Donnees : peersModel (DiscoveryService, mis a jour en temps reel) et,
 * pour un administrateur, authorizedMachineModel (etat de confiance :
 * autorise / en attente / revoque). Aucune donnee n'est fabriquee : une
 * colonne sans information reste vide plutot que d'afficher une valeur
 * par defaut trompeuse.
 *
 * Deux presentations : tableau (tri par colonne, recherche) ou cartes.
 * Actions reelles : envoyer un fichier, appeler. Autoriser / revoquer une
 * machine reste dans Administration (operation sensible, confirmee et
 * controlee cote metier).
 */
Item {
    id: root

    property var model: (typeof peersModel !== "undefined") ? peersModel : null
    readonly property bool isAdmin: (typeof userManager !== "undefined" && userManager)
                                    ? userManager.currentUserIsAdmin : false

    signal backRequested()
    signal fileTransferRequested(var peer)
    signal adminRequested()

    // ---- Donnees ----------------------------------------------------------
    property var rows: []
    property string searchText: ""
    property string sortKey: "name"
    property bool sortAscending: true
    property string viewMode: "table"   // "table" | "cards"
    property string statusFilter: "all" // "all" | "online" | "away" | "busy"

    function statusLabel(status) {
        switch (status) {
        case "online": return qsTr("En ligne")
        case "busy": return qsTr("Occupé")
        case "away": return qsTr("Absent")
        default: return qsTr("Inconnu")
        }
    }
    function statusTone(status) {
        switch (status) {
        case "online": return "success"
        case "busy": return "warning"
        case "away": return "warning"
        default: return "neutral"
        }
    }

    // Etat de confiance par adresse / identifiant (administrateur).
    function trustMap() {
        const map = { byId: {}, byIp: {} }
        if (!root.isAdmin || typeof authorizedMachineModel === "undefined" || !authorizedMachineModel)
            return map
        const total = authorizedMachineModel.rowCount ? authorizedMachineModel.rowCount() : 0
        for (let i = 0; i < total; i++) {
            const idx = authorizedMachineModel.index(i, 0)
            const authorized = authorizedMachineModel.data(idx, authorizedMachineModel.AuthorizedRole)
            const status = authorizedMachineModel.data(idx, authorizedMachineModel.StatusRole) || ""
            const id = authorizedMachineModel.data(idx, authorizedMachineModel.MachineIdRole) || ""
            const ip = authorizedMachineModel.data(idx, authorizedMachineModel.IpAddressRole) || ""
            const trust = status === "revoked" ? "revoked" : (authorized ? "authorized" : "pending")
            if (id) map.byId[id] = trust
            if (ip) map.byIp[ip] = trust
        }
        return map
    }

    function refresh() {
        const out = []
        if (root.model) {
            const trust = root.trustMap()
            for (let i = 0; i < root.model.count; i++) {
                const idx = root.model.index(i, 0)
                const id = root.model.data(idx, 257) || ""
                const address = root.model.data(idx, 261) || ""
                out.push({
                    peerId: id,
                    name: root.model.data(idx, 258) || address,
                    userUuid: root.model.data(idx, 259) || "",
                    status: root.model.data(idx, 260) || "",
                    address: address,
                    port: root.model.data(idx, 262) || 0,
                    lastSeenMs: root.model.data(idx, 265) || 0,
                    trust: trust.byId[id] || trust.byIp[address] || ""
                })
            }
        }
        root.rows = out
    }

    readonly property var visibleRows: {
        const q = root.searchText.trim().toLowerCase()
        const filtered = root.rows.filter(function(r) {
            if (root.statusFilter !== "all" && r.status !== root.statusFilter)
                return false
            if (q.length === 0)
                return true
            return r.name.toLowerCase().indexOf(q) >= 0 || r.address.indexOf(q) >= 0
        })
        const key = root.sortKey
        const dir = root.sortAscending ? 1 : -1
        const statusRank = { "online": 0, "busy": 1, "away": 2 }
        filtered.sort(function(a, b) {
            let va = a[key], vb = b[key]
            if (key === "status") { va = statusRank[a.status] ?? 9; vb = statusRank[b.status] ?? 9 }
            if (key === "address") {
                va = a.address.split(".").map(function(n) { return ("00" + n).slice(-3) }).join(".")
                vb = b.address.split(".").map(function(n) { return ("00" + n).slice(-3) }).join(".")
            }
            if (va < vb) return -1 * dir
            if (va > vb) return 1 * dir
            return 0
        })
        return filtered
    }

    readonly property int onlineCount: root.rows.filter(function(r) { return r.status === "online" }).length

    function seenLabel(ms) {
        if (!ms || ms < 1e12)
            return ""
        const seconds = Math.max(0, Math.round((Date.now() - ms) / 1000))
        if (seconds < 30) return qsTr("à l'instant")
        if (seconds < 3600) return qsTr("il y a %1 min").arg(Math.max(1, Math.round(seconds / 60)))
        return new Date(ms).toLocaleTimeString(Qt.locale(), "HH:mm")
    }

    function sortBy(key) {
        if (root.sortKey === key)
            root.sortAscending = !root.sortAscending
        else {
            root.sortKey = key
            root.sortAscending = true
        }
    }

    function peerObject(r) {
        return { id: r.peerId, name: r.name, address: r.address, status: r.status, userUuid: r.userUuid }
    }

    function callPeer(r) {
        if (typeof callContext !== "undefined" && callContext && r.address)
            callContext.call(r.address)
    }

    Component.onCompleted: root.refresh()

    Connections {
        target: root.model
        ignoreUnknownSignals: true
        function onCountChanged() { root.refresh() }
        function onDataChanged() { root.refresh() }
        function onModelReset() { root.refresh() }
        function onRowsInserted() { root.refresh() }
        function onRowsRemoved() { root.refresh() }
    }

    // "Vu il y a..." doit vieillir avec le temps.
    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: root.refresh()
    }

    // ---- Mise en page ------------------------------------------------------
    readonly property var columns: [
        { title: qsTr("Poste"), fill: true, sortKey: "name" },
        { title: qsTr("Disponibilité"), width: 130, sortKey: "status" },
        { title: qsTr("Confiance"), width: 120, sortKey: "trust", visible: root.isAdmin },
        { title: qsTr("Adresse"), width: 150, sortKey: "address", visible: root.width >= 820 },
        { title: qsTr("Vu"), width: 90, visible: root.width >= 980 },
        { title: "", width: 84 }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        AppHeader {
            title: qsTr("Postes")
            subtitle: root.rows.length === 0
                      ? qsTr("Aucun autre poste détecté sur le réseau local pour le moment.")
                      : qsTr("%1 poste(s) détecté(s) · %2 en ligne · mise à jour automatique")
                            .arg(root.rows.length).arg(root.onlineCount)

            AppButton {
                visible: root.isAdmin
                text: qsTr("Gérer les autorisations")
                iconGlyph: ""
                variant: "secondary"
                onClicked: root.adminRequested()
            }
        }

        // Barre d'outils : recherche, filtre d'etat, presentation.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            Layout.bottomMargin: Theme.spacingMedium
            spacing: 10

            AppSearchField {
                Layout.preferredWidth: 300
                Layout.fillWidth: root.width < 760
                placeholderText: qsTr("Rechercher par nom ou adresse")
                onTextChanged: root.searchText = text
            }

            AppSegmentedControl {
                visible: root.width >= 760
                stretch: false
                model: [ { label: qsTr("Tous") }, { label: qsTr("En ligne") },
                         { label: qsTr("Absents") }, { label: qsTr("Occupés") } ]
                currentIndex: ["all", "online", "away", "busy"].indexOf(root.statusFilter)
                onActivated: function(index) { root.statusFilter = ["all", "online", "away", "busy"][index] }
            }

            Item { Layout.fillWidth: true }

            AppSegmentedControl {
                stretch: false
                model: [ { label: qsTr("Tableau"), glyph: "" }, { label: qsTr("Cartes"), glyph: "" } ]
                currentIndex: root.viewMode === "cards" ? 1 : 0
                onActivated: function(index) { root.viewMode = index === 1 ? "cards" : "table" }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            Layout.bottomMargin: Theme.pagePadding
            contentPadding: 0
            clip: true

            // ---- Etats vides ----
            EmptyState {
                visible: root.rows.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                iconName: "peers"
                title: qsTr("Aucun poste détecté")
                description: qsTr("Les postes qui lancent LocaLink sur le même réseau local apparaissent ici automatiquement.")
            }
            EmptyState {
                visible: root.rows.length > 0 && root.visibleRows.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                iconName: "search"
                title: qsTr("Aucun poste ne correspond")
                description: qsTr("Modifiez la recherche ou le filtre de disponibilité.")
                actionText: qsTr("Réinitialiser les filtres")
                onActionClicked: { root.statusFilter = "all"; root.searchText = "" }
            }

            // ---- Tableau ----
            TableHeader {
                visible: root.viewMode === "table" && root.visibleRows.length > 0
                Layout.fillWidth: true
                columns: root.columns
                sortKey: root.sortKey
                sortAscending: root.sortAscending
                onSortRequested: function(key) { root.sortBy(key) }
            }

            ListView {
                id: tableView
                visible: root.viewMode === "table" && root.visibleRows.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.visibleRows
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                delegate: ItemDelegate {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: Theme.rowHeight
                    padding: 0
                    leftPadding: Theme.cardPadding
                    rightPadding: Theme.cardPadding
                    hoverEnabled: true
                    Accessible.name: row.modelData.name + ", " + root.statusLabel(row.modelData.status)

                    background: Rectangle {
                        color: row.hovered ? Theme.hover : "transparent"
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Theme.line
                        }
                    }

                    contentItem: RowLayout {
                        spacing: 12

                        // Poste
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 100
                            Layout.minimumWidth: 80
                            spacing: 10

                            Avatar {
                                name: row.modelData.name
                                size: 30
                                showStatus: true
                                status: row.modelData.status
                            }
                            Text {
                                text: row.modelData.name
                                color: Theme.ink
                                font.pixelSize: Theme.fs(13)
                                font.weight: Theme.weightMedium
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Disponibilite
                        Item {
                            Layout.preferredWidth: 130
                            Layout.minimumWidth: 130
                            Layout.fillHeight: true
                            StatusBadge {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.statusLabel(row.modelData.status)
                                tone: root.statusTone(row.modelData.status)
                                compact: true
                            }
                        }

                        // Confiance (administrateur)
                        Item {
                            visible: root.isAdmin
                            Layout.preferredWidth: 120
                            Layout.minimumWidth: 120
                            Layout.fillHeight: true
                            StatusBadge {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: row.modelData.trust.length > 0
                                text: row.modelData.trust === "authorized" ? qsTr("Autorisé")
                                    : row.modelData.trust === "pending" ? qsTr("En attente")
                                    : qsTr("Révoqué")
                                tone: row.modelData.trust === "authorized" ? "neutral"
                                    : row.modelData.trust === "pending" ? "warning" : "danger"
                                glyph: row.modelData.trust === "authorized" ? ""
                                     : row.modelData.trust === "pending" ? "" : ""
                                compact: true
                            }
                        }

                        // Adresse
                        Text {
                            visible: root.width >= 820
                            Layout.preferredWidth: 150
                            Layout.minimumWidth: 150
                            text: row.modelData.address + (row.modelData.port ? ":" + row.modelData.port : "")
                            color: Theme.ink2
                            font.pixelSize: Theme.fs(12)
                            font.family: Theme.fontFamily
                            font.features: ({ "tnum": 1 })
                            elide: Text.ElideRight
                        }

                        // Vu
                        Text {
                            visible: root.width >= 980
                            Layout.preferredWidth: 90
                            Layout.minimumWidth: 90
                            text: root.seenLabel(row.modelData.lastSeenMs)
                            color: Theme.ink3
                            font.pixelSize: Theme.fs(12)
                            font.family: Theme.fontFamily
                        }

                        // Actions
                        RowLayout {
                            Layout.preferredWidth: 84
                            Layout.minimumWidth: 84
                            Layout.maximumWidth: 84
                            spacing: 4
                            // Pleine opacite : une action attenuee se confondait avec
                            // l etat desactive (inkDisabled).

                            Item { Layout.fillWidth: true }
                            IconButton {
                                id: sendBtn
                                glyph: ""
                                size: 32
                                iconSize: Theme.fs(13)
                                tooltip: qsTr("Envoyer un fichier à %1").arg(row.modelData.name)
                                onClicked: root.fileTransferRequested(root.peerObject(row.modelData))
                            }
                            IconButton {
                                id: callBtn
                                glyph: ""
                                size: 32
                                iconSize: Theme.fs(13)
                                tooltip: qsTr("Appeler %1").arg(row.modelData.name)
                                enabled: row.modelData.address.length > 0
                                onClicked: root.callPeer(row.modelData)
                            }
                        }
                    }
                }
            }

            // ---- Cartes ----
            GridView {
                id: gridView
                visible: root.viewMode === "cards" && root.visibleRows.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 10
                clip: true
                model: root.visibleRows
                readonly property int columns: Math.max(1, Math.floor(width / 280))
                cellWidth: Math.floor(width / columns)
                cellHeight: 132
                ScrollBar.vertical: ScrollBar {}

                delegate: Item {
                    id: cardCell
                    required property var modelData
                    width: gridView.cellWidth
                    height: gridView.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: Theme.radiusMedium
                        color: Theme.surface0
                        border.width: 1
                        border.color: cardHover.hovered ? Theme.lineStrong : Theme.line

                        HoverHandler { id: cardHover }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Avatar {
                                    name: cardCell.modelData.name
                                    size: 36
                                    showStatus: true
                                    status: cardCell.modelData.status
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        text: cardCell.modelData.name
                                        color: Theme.ink
                                        font.pixelSize: Theme.fs(13)
                                        font.weight: Theme.weightSemibold
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: cardCell.modelData.address
                                        color: Theme.ink3
                                        font.pixelSize: Theme.fs(12)
                                        font.family: Theme.fontFamily
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                StatusBadge {
                                    text: root.statusLabel(cardCell.modelData.status)
                                    tone: root.statusTone(cardCell.modelData.status)
                                    compact: true
                                }
                                StatusBadge {
                                    visible: root.isAdmin && cardCell.modelData.trust === "pending"
                                    text: qsTr("En attente")
                                    tone: "warning"
                                    glyph: ""
                                    compact: true
                                }
                                Item { Layout.fillWidth: true }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                AppButton {
                                    text: qsTr("Envoyer")
                                    iconGlyph: ""
                                    variant: "secondary"
                                    size: "small"
                                    onClicked: root.fileTransferRequested(root.peerObject(cardCell.modelData))
                                }
                                AppButton {
                                    text: qsTr("Appeler")
                                    iconGlyph: ""
                                    variant: "ghost"
                                    size: "small"
                                    onClicked: root.callPeer(cardCell.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
