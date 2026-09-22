import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * HomeView - tableau de bord principal LocaLink.
 *
 * La vue reprend la composition de la maquette Workspace V2.1 :
 * sidebar claire, carte réseau, actions à traiter, transferts et activité.
 * Les sources de données restent les modèles exposés par Application :
 * peersModel, transferContext, auditLogModel et electionService.
 */
Item {
    id: root
    objectName: "homeView"

    property string username: ""

    signal logoutRequested()
    signal usersRequested()
    signal chatRequested()
    signal fileTransferRequested()
    signal callRequested()
    signal adminRequested()
    signal settingsRequested()
    signal sharedFoldersRequested()
    signal aboutRequested()

    readonly property bool isAdmin: (typeof userManager !== "undefined" && userManager)
                                    ? userManager.currentUserIsAdmin : false
    readonly property var election: (typeof electionService !== "undefined")
                                    ? electionService : null
    readonly property int peersCount: (typeof peersModel !== "undefined" && peersModel)
                                      ? peersModel.count : 0
    readonly property color pageBackground: Theme.darkMode ? "#0E1517" : "#F1F4F3"
    readonly property color surface: Theme.darkMode ? "#152024" : "#FFFFFF"
    readonly property color surfaceAlt: Theme.darkMode ? "#1A272B" : "#E7EDEC"
    readonly property color surfaceSoft: Theme.darkMode ? "#1B292D" : "#F7F9F8"
    readonly property color line: Theme.darkMode ? "#2A3A3F" : "#DDE4E2"
    readonly property color ink: Theme.darkMode ? "#EAF1F2" : "#15222B"
    readonly property color ink2: Theme.darkMode ? "#B3C2C6" : "#4A5961"
    readonly property color ink3: Theme.darkMode ? "#93A5AB" : "#62717A"
    readonly property color primary: Theme.darkMode ? "#7FC4D6" : "#0B5C70"
    readonly property color primarySoft: Theme.darkMode ? "#173139" : "#E0EEF2"
    readonly property color success: Theme.darkMode ? "#55C88A" : "#258A68"
    readonly property color successSoft: Theme.darkMode ? "#18362D" : "#E3F3EC"
    readonly property color warning: Theme.darkMode ? "#F5BE55" : "#B87513"
    readonly property color warningSoft: Theme.darkMode ? "#3A301C" : "#FFF2D9"
    readonly property color danger: Theme.darkMode ? "#F58D91" : "#C34F55"
    readonly property color dangerSoft: Theme.darkMode ? "#3A2024" : "#FBE7E8"
    readonly property color info: Theme.darkMode ? "#86B8F4" : "#477DB8"
    readonly property color infoSoft: Theme.darkMode ? "#1C3046" : "#E9F1FB"
    readonly property string serverStatusLabel: {
        if (!root.election)
            return qsTr("Réseau local")
        if (root.election.roleLabel === "TEMP_SERVER")
            return qsTr("Mode secours")
        if (root.election.roleLabel === "SERVER")
            return qsTr("Serveur actif")
        return qsTr("Connecté au serveur")
    }
    readonly property color serverStatusColor: {
        if (!root.election)
            return root.success
        if (root.election.roleLabel === "TEMP_SERVER")
            return root.warning
        return root.success
    }

    property var transferItems: []

    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }

    function refreshTransfers() {
        if (typeof transferContext === "undefined" || !transferContext) {
            transferItems = []
            return
        }
        const all = transferContext.activeTransfers || []
        transferItems = all.filter(function(item) {
            return item && item.statusText === qsTr("En cours")
        }).slice(-4).reverse()
    }

    function readableBytes(value) {
        const bytes = Number(value || 0)
        if (bytes < 1024 * 1024)
            return Math.max(1, Math.round(bytes / 1024)) + " Ko"
        return (bytes / (1024 * 1024)).toFixed(bytes >= 100 * 1024 * 1024 ? 0 : 1) + " Mo"
    }

    function eventLabel(value) {
        switch (value) {
        case "connection": return qsTr("Connexion")
        case "message": return qsTr("Message")
        case "transfer": return qsTr("Transfert")
        case "call": return qsTr("Appel")
        case "access_denied": return qsTr("Accès refusé")
        default: return value || qsTr("Activité")
        }
    }

    function eventColor(value) {
        switch (value) {
        case "connection": return root.success
        case "message": return root.info
        case "transfer": return root.primary
        case "call": return "#8A63B6"
        case "access_denied": return root.danger
        default: return root.ink3
        }
    }

    function timeLabel(value) {
        const date = new Date(value)
        if (isNaN(date.getTime()))
            return value || ""
        return Qt.formatTime(date, "hh:mm")
    }

    function openRoute(route) {
        switch (route) {
        case "chat": root.chatRequested(); break
        case "transfer": root.fileTransferRequested(); break
        case "folder": root.sharedFoldersRequested(); break
        case "call": root.callRequested(); break
        case "peers": root.usersRequested(); break
        case "admin": root.adminRequested(); break
        case "settings": root.settingsRequested(); break
        case "logout": root.logoutRequested(); break
        }
    }

    Component.onCompleted: refreshTransfers()

    Connections {
        target: (typeof transferContext !== "undefined") ? transferContext : null
        function onActiveTransfersChanged() { root.refreshTransfers() }
    }

    Rectangle {
        anchors.fill: parent
        color: root.pageBackground
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ------------------------------------------------------------------
        // Sidebar
        // ------------------------------------------------------------------
        Rectangle {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: 216
            Layout.minimumWidth: 216
            color: root.surfaceAlt

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 14
                anchors.bottomMargin: 12
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    spacing: 10

                    Image {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        source: "../Assets/logo.png"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Label {
                            text: qsTr("LocaLink")
                            color: root.ink
                            font.pixelSize: 15
                            font.bold: true
                            font.family: Theme.fontFamily
                        }
                        Label {
                            text: qsTr("Espace entreprise")
                            color: root.ink3
                            font.pixelSize: 11
                            font.family: Theme.fontFamily
                        }
                    }
                }

                Repeater {
                    model: ListModel {
                        ListElement { route: "home"; icon: "\uf015"; label: "Vue d’ensemble"; count: ""; accent: false }
                        ListElement { route: "chat"; icon: "\uf0e5"; label: "Discussions"; count: ""; accent: true }
                        ListElement { route: "transfer"; icon: "\uf1d8"; label: "Transferts"; count: ""; accent: true }
                        ListElement { route: "folder"; icon: "\uf07b"; label: "Dossiers partagés"; count: ""; accent: false }
                        ListElement { route: "call"; icon: "\uf095"; label: "Appels"; count: ""; accent: false }
                        ListElement { route: "peers"; icon: "\uf108"; label: "Postes"; count: ""; accent: false }
                    }
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 8
                        color: model.route === "home" ? root.surface
                              : navMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.55) : "transparent"
                        border.width: model.route === "home" ? 1 : 0
                        border.color: root.line

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            Text {
                                text: model.icon
                                color: model.route === "home" ? root.primary : root.ink2
                                font.family: iconFont.name
                                font.pixelSize: 16
                                horizontalAlignment: Text.AlignHCenter
                                Layout.preferredWidth: 17
                            }
                            Label {
                                text: qsTr(model.label)
                                color: model.route === "home" ? root.primary : root.ink2
                                font.pixelSize: 12
                                font.bold: model.route === "home"
                                font.family: Theme.fontFamily
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                // Le modèle de messagerie n'expose pas encore
                                // de compteur de non-lus global : ne pas
                                // afficher un badge inventé sur l'accueil.
                                visible: false
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                radius: 9
                                color: root.primary
                                Label {
                                    anchors.centerIn: parent
                                    text: root.peersCount
                                    color: "#FFFFFF"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                            Rectangle {
                                visible: model.route === "transfer" && root.transferItems.length > 0
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                radius: 9
                                color: root.primary
                                Label {
                                    anchors.centerIn: parent
                                    text: root.transferItems.length
                                    color: "#FFFFFF"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                        }
                        MouseArea {
                            id: navMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openRoute(model.route)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 14
                    color: "transparent"
                }

                Repeater {
                    model: ListModel {
                        ListElement { route: "journal"; icon: "\uf03a"; label: "Journal" }
                        ListElement { route: "admin"; icon: "\uf132"; label: "Administration" }
                    }
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 8
                        color: navMouse2.containsMouse ? Qt.rgba(1, 1, 1, 0.55) : "transparent"
                        visible: model.route !== "admin" || root.isAdmin
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            Text {
                                text: model.icon
                                color: root.ink2
                                font.family: iconFont.name
                                font.pixelSize: 16
                                horizontalAlignment: Text.AlignHCenter
                                Layout.preferredWidth: 17
                            }
                            Label {
                                text: qsTr(model.label)
                                color: root.ink2
                                font.pixelSize: 12
                                font.family: Theme.fontFamily
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                visible: model.route === "admin" && root.isAdmin
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                radius: 9
                                color: root.warning
                                Label {
                                    anchors.centerIn: parent
                                    text: "2"
                                    color: "#FFFFFF"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                        }
                        MouseArea {
                            id: navMouse2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openRoute(model.route)
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 10
                    color: root.surface

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 9
                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: root.serverStatusColor
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Label {
                                text: root.serverStatusLabel
                                color: root.ink
                                font.pixelSize: 12
                                font.bold: true
                                font.family: Theme.fontFamily
                            }
                            Label {
                                text: qsTr("Ce poste")
                                color: root.ink3
                                font.pixelSize: 11
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    Layout.topMargin: 6
                    border.width: 1
                    border.color: root.line
                    color: root.surfaceAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.topMargin: 8
                        anchors.bottomMargin: 2
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10
                        Avatar {
                            name: root.username
                            size: 30
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Label {
                                text: root.username || qsTr("Utilisateur")
                                color: root.ink
                                font.pixelSize: 12
                                font.bold: true
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Label {
                                text: qsTr("Session active")
                                color: root.ink3
                                font.pixelSize: 11
                                font.family: Theme.fontFamily
                            }
                        }
                        Text {
                            text: "\u25BE"
                            color: root.ink3
                            font.pixelSize: 12
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: profileMenu.open()
                    }
                }
            }

            Popup {
                id: profileMenu
                x: sidebar.width - width - 10
                y: sidebar.height - height - 70
                width: 220
                padding: 8
                modal: false
                closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
                background: Rectangle {
                    radius: 10
                    color: root.surface
                    border.width: 1
                    border.color: root.line
                }
                contentItem: ColumnLayout {
                    spacing: 2
                    Label {
                        text: root.serverStatusLabel
                        color: root.ink2
                        font.pixelSize: 12
                        Layout.margins: 6
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: root.line }
                    Button {
                        text: qsTr("Paramètres")
                        flat: true
                        onClicked: { profileMenu.close(); root.settingsRequested() }
                    }
                    Button {
                        text: qsTr("À propos")
                        flat: true
                        onClicked: { profileMenu.close(); root.aboutRequested() }
                    }
                    Button {
                        text: qsTr("Se déconnecter")
                        flat: true
                        onClicked: { profileMenu.close(); root.logoutRequested() }
                    }
                }
            }
        }

        // ------------------------------------------------------------------
        // Zone principale
        // ------------------------------------------------------------------
        ColumnLayout {
            id: mainColumn
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                color: root.pageBackground
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    spacing: 8
                    Label {
                        text: qsTr("LocaLink  /  ")
                        color: root.ink3
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }
                    Label {
                        text: qsTr("Vue d’ensemble")
                        color: root.ink
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Theme.fontFamily
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 250
                        Layout.preferredHeight: 32
                        radius: 8
                        color: root.surface
                        border.width: 1
                        border.color: root.line
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 8
                            Text {
                                text: "\uf002"
                                color: root.ink3
                                font.family: iconFont.name
                                font.pixelSize: 14
                            }
                            Label {
                                text: qsTr("Rechercher")
                                color: root.ink3
                                font.pixelSize: 12
                                font.family: Theme.fontFamily
                                Layout.fillWidth: true
                            }
                            Label {
                                text: "Ctrl K"
                                color: root.ink3
                                font.pixelSize: 10
                                font.family: "monospace"
                            }
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 8
                        color: notificationMouse.containsMouse ? root.surface : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "\uf0f3"
                            color: root.ink2
                            font.family: iconFont.name
                            font.pixelSize: 17
                        }
                        Rectangle {
                            visible: false
                            width: 8
                            height: 8
                            radius: 4
                            color: root.danger
                            anchors.top: parent.top
                            anchors.right: parent.right
                        }
                        MouseArea {
                            id: notificationMouse
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: dashboardContent.implicitHeight + 36

                ColumnLayout {
                    id: dashboardContent
                    width: Math.max(620, parent.width - 48)
                    x: Math.max(24, (parent.width - width) / 2)
                    y: 4
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 62
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label {
                                text: root.username.length > 0
                                      ? qsTr("Bonjour, %1").arg(root.username)
                                      : qsTr("Bonjour")
                                color: root.ink
                                font.pixelSize: 26
                                font.bold: true
                                font.family: Theme.fontFamily
                            }
                            RowLayout {
                                spacing: 16
                                Rectangle {
                                    Layout.preferredHeight: 26
                                    implicitWidth: statusLabel.implicitWidth + 20
                                    radius: 13
                                    color: root.successSoft
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7
                                        Rectangle {
                                            Layout.preferredWidth: 7
                                            Layout.preferredHeight: 7
                                            radius: 4
                                            color: root.success
                                        }
                                        Label {
                                            id: statusLabel
                                            text: root.serverStatusLabel
                                            color: root.success
                                            font.pixelSize: 12
                                            font.bold: true
                                            font.family: Theme.fontFamily
                                        }
                                    }
                                }
                                Label {
                                    text: qsTr("%1 poste(s) en ligne").arg(root.peersCount)
                                    color: root.ink2
                                    font.pixelSize: 14
                                    font.family: Theme.fontFamily
                                }
                                Label {
                                    text: qsTr("%1 transfert(s) en cours").arg(root.transferItems.length)
                                    color: root.ink2
                                    font.pixelSize: 14
                                    font.family: Theme.fontFamily
                                }
                            }
                        }
                        Rectangle {
                            Layout.preferredHeight: 34
                            implicitWidth: newTransferLabel.implicitWidth + 26
                            radius: 8
                            color: root.primary
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 7
                                Text {
                                    text: "\uf067"
                                    color: "#FFFFFF"
                                    font.family: iconFont.name
                                    font.pixelSize: 13
                                }
                                Label {
                                    id: newTransferLabel
                                    text: qsTr("Nouveau transfert")
                                    color: "#FFFFFF"
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.fileTransferRequested()
                            }
                        }
                    }

                    // Surface réseau + colonne À traiter.
                    RowLayout {
                        id: networkSurface
                        Layout.fillWidth: true
                        Layout.preferredHeight: 410
                        spacing: 0

                        Rectangle {
                            id: networkMap
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumWidth: 430
                            color: root.surface
                            border.width: 1
                            border.color: root.line
                            radius: 12
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 11
                                color: root.surfaceSoft
                                opacity: Theme.darkMode ? 0.55 : 0.85
                            }

                            // Point grid from the mockup, kept subtle behind the map.
                            Canvas {
                                anchors.fill: parent
                                opacity: Theme.darkMode ? 0.08 : 0.13
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.fillStyle = root.primary
                                    for (let x = 12; x < width; x += 22)
                                        for (let y = 12; y < height; y += 22)
                                            ctx.fillRect(x, y, 1.2, 1.2)
                                }
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.leftMargin: 20
                                anchors.topMargin: 16
                                spacing: 1
                                Label {
                                    text: qsTr("Réseau local")
                                    color: root.ink
                                    font.pixelSize: 15
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }
                                Label {
                                    text: qsTr("Postes détectés autour de ce poste, disposition indicative")
                                    color: root.ink3
                                    font.pixelSize: 12
                                    font.family: Theme.fontFamily
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.rightMargin: 16
                                anchors.topMargin: 14
                                width: 112
                                height: 30
                                radius: 7
                                color: root.surfaceAlt
                                Row {
                                    anchors.fill: parent
                                    spacing: 0
                                    Rectangle {
                                        width: 56
                                        height: parent.height
                                        radius: 7
                                        color: root.surface
                                        Label {
                                            anchors.centerIn: parent
                                            text: qsTr("Carte")
                                            color: root.primary
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                    Label {
                                        width: 56
                                        height: parent.height
                                        text: qsTr("Liste")
                                        color: root.ink3
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.family: Theme.fontFamily
                                    }
                                }
                            }

                            // Decorative ellipses reproduce the indicative topology.
                            Rectangle {
                                id: innerOrbit
                                width: Math.min(networkMap.width * 0.56, 450)
                                height: 160
                                radius: width / 2
                                color: "transparent"
                                border.width: 1
                                border.color: root.ink3
                                opacity: 0.38
                                border {
                                    top.color: root.ink3
                                    bottom.color: root.ink3
                                }
                                anchors.centerIn: mapArea
                                transform: Rotation { angle: -4; origin.x: innerOrbit.width / 2; origin.y: innerOrbit.height / 2 }
                            }

                            Rectangle {
                                id: outerOrbit
                                width: Math.min(networkMap.width * 0.78, 620)
                                height: 245
                                radius: width / 2
                                color: "transparent"
                                border.width: 1
                                border.color: root.ink3
                                opacity: 0.25
                                anchors.centerIn: mapArea
                                transform: Rotation { angle: -4; origin.x: outerOrbit.width / 2; origin.y: outerOrbit.height / 2 }
                            }

                            Item {
                                id: mapArea
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: legend.top
                                anchors.topMargin: 42
                                anchors.bottomMargin: 54

                                Rectangle {
                                    id: localNode
                                    width: 52
                                    height: 52
                                    radius: 26
                                    anchors.centerIn: parent
                                    color: root.primary
                                    border.width: 5
                                    border.color: Theme.darkMode ? "#284D58" : "#DCEEF0"
                                    z: 3
                                    Text {
                                        anchors.centerIn: parent
                                        text: "\uf108"
                                        color: "#FFFFFF"
                                        font.family: iconFont.name
                                        font.pixelSize: 21
                                    }
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.bottom
                                        anchors.topMargin: 8
                                        text: qsTr("Ce poste")
                                        color: root.ink
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                    }
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.bottom
                                        anchors.topMargin: 25
                                        text: root.serverStatusLabel
                                        color: root.ink3
                                        font.pixelSize: 11
                                        font.family: Theme.fontFamily
                                    }
                                }

                                Repeater {
                                    model: (typeof peersModel !== "undefined") ? peersModel : null
                                    delegate: Item {
                                        id: peerNode
                                        width: 44
                                        height: 62
                                        property real angle: [-160, -112, -64, -12, 38, 88, 138, 188][index % 8]
                                        property real radiusX: Math.max(105, mapArea.width * 0.31)
                                        property real radiusY: Math.max(65, mapArea.height * 0.34)
                                        x: mapArea.width / 2 + Math.cos(angle * Math.PI / 180) * radiusX - width / 2
                                        y: mapArea.height / 2 + Math.sin(angle * Math.PI / 180) * radiusY - height / 2
                                        z: 4

                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 34
                                            height: 34
                                            radius: 17
                                            color: peerStatus === "busy" ? "#8A63B6"
                                                  : peerStatus === "away" ? root.warning : root.success
                                            border.width: 3
                                            border.color: root.surface
                                            Text {
                                                anchors.centerIn: parent
                                                text: "\uf108"
                                                color: "#FFFFFF"
                                                font.family: iconFont.name
                                                font.pixelSize: 15
                                            }
                                        }
                                        property string peerStatus: status || "online"
                                        Label {
                                            anchors.top: parent.top
                                            anchors.topMargin: 39
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 95
                                            text: name || address || qsTr("Poste")
                                            color: root.ink2
                                            font.pixelSize: 11
                                            font.bold: true
                                            font.family: Theme.fontFamily
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.usersRequested()
                                        }
                                    }
                                }
                            }

                            Row {
                                id: legend
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 20
                                anchors.bottomMargin: 14
                                spacing: 12
                                Repeater {
                                    model: [
                                        { label: qsTr("En ligne"), color: root.success },
                                        { label: qsTr("Absent"), color: root.warning },
                                        { label: qsTr("En transfert"), color: root.primary },
                                        { label: qsTr("En appel"), color: "#8A63B6" }
                                    ]
                                    delegate: Row {
                                        spacing: 5
                                        Rectangle {
                                            width: 7
                                            height: 7
                                            radius: 4
                                            color: modelData.color
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Label {
                                            text: modelData.label
                                            color: root.ink3
                                            font.pixelSize: 10
                                            font.family: Theme.fontFamily
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: attentionPanel
                            Layout.preferredWidth: 220
                            Layout.fillHeight: true
                            color: root.surface
                            border.width: 1
                            border.color: root.line
                            radius: 12

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: qsTr("À traiter")
                                        color: root.ink
                                        font.pixelSize: 16
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                        Layout.fillWidth: true
                                    }
                                    Rectangle {
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        radius: 11
                                        color: root.warning
                                        Label {
                                            anchors.centerIn: parent
                                            text: "0"
                                            color: "#FFFFFF"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.line }
                                Item { Layout.fillHeight: true }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        text: "\uf05a"
                                        color: root.ink3
                                        font.family: iconFont.name
                                        font.pixelSize: 22
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Label {
                                        text: qsTr("Aucune action requise")
                                        color: root.ink2
                                        font.pixelSize: 12
                                        font.family: Theme.fontFamily
                                        horizontalAlignment: Text.AlignHCenter
                                        Layout.fillWidth: true
                                    }
                                    Label {
                                        text: qsTr("Tout est à jour")
                                        color: root.ink3
                                        font.pixelSize: 11
                                        font.family: Theme.fontFamily
                                        horizontalAlignment: Text.AlignHCenter
                                        Layout.fillWidth: true
                                    }
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }

                    // Transferts et activité restent posés directement sur le fond.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 28

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 300
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: qsTr("Transferts")
                                    color: root.ink
                                    font.pixelSize: 17
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }
                                Rectangle {
                                    visible: root.transferItems.length > 0
                                    Layout.preferredWidth: transferCountLabel.implicitWidth + 14
                                    Layout.preferredHeight: 22
                                    radius: 11
                                    color: root.primarySoft
                                    Label {
                                        id: transferCountLabel
                                        anchors.centerIn: parent
                                        text: qsTr("%1 en cours").arg(root.transferItems.length)
                                        color: root.primary
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Button {
                                    text: qsTr("Tous les transferts")
                                    flat: true
                                    font.pixelSize: 11
                                    onClicked: root.fileTransferRequested()
                                }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.line }
                            Repeater {
                                model: root.transferItems
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 55
                                    color: "transparent"
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 10
                                        Rectangle {
                                            Layout.preferredWidth: 32
                                            Layout.preferredHeight: 32
                                            radius: 8
                                            color: root.primarySoft
                                            Text {
                                                anchors.centerIn: parent
                                                text: "\uf1d8"
                                                color: root.primary
                                                font.family: iconFont.name
                                                font.pixelSize: 14
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Label {
                                                text: modelData.fileName || qsTr("Fichier")
                                                color: root.ink
                                                font.pixelSize: 12
                                                font.bold: true
                                                font.family: Theme.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Label {
                                                text: qsTr("%1 · %2").arg(modelData.peerName || modelData.peerAddress || qsTr("Poste")).arg(
                                                          modelData.direction === "Réception" ? qsTr("Réception") : qsTr("Envoi"))
                                                color: root.ink3
                                                font.pixelSize: 11
                                                font.family: Theme.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.preferredWidth: 100
                                            spacing: 4
                                            Label {
                                                text: qsTr("%1 sur %2").arg(root.readableBytes(modelData.bytesTransferred))
                                                       .arg(root.readableBytes(modelData.totalBytes))
                                                color: root.ink2
                                                font.pixelSize: 10
                                                horizontalAlignment: Text.AlignRight
                                                Layout.fillWidth: true
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 5
                                                radius: 3
                                                color: root.surfaceAlt
                                                Rectangle {
                                                    width: parent.width * Math.max(0, Math.min(100, Number(modelData.percent || 0))) / 100
                                                    height: parent.height
                                                    radius: 3
                                                    color: root.primary
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Label {
                                visible: root.transferItems.length === 0
                                text: qsTr("Aucun transfert en cours")
                                color: root.ink3
                                font.pixelSize: 12
                                font.family: Theme.fontFamily
                                Layout.topMargin: 8
                                Layout.bottomMargin: 12
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 300
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: qsTr("Activité récente")
                                    color: root.ink
                                    font.pixelSize: 17
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }
                                Item { Layout.fillWidth: true }
                                Button {
                                    text: qsTr("Voir le journal")
                                    flat: true
                                    font.pixelSize: 11
                                    onClicked: root.openRoute("journal")
                                }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.line }
                            Repeater {
                                model: (typeof auditLogModel !== "undefined" && auditLogModel)
                                       ? Math.min(auditLogModel.count, 5) : 0
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 42
                                    spacing: 9
                                    Rectangle {
                                        Layout.preferredWidth: 7
                                        Layout.preferredHeight: 7
                                        radius: 4
                                        color: root.eventColor(eventType)
                                    }
                                    Label {
                                        text: root.eventLabel(eventType)
                                        color: root.eventColor(eventType)
                                        font.pixelSize: 10
                                        font.bold: true
                                        Layout.preferredWidth: 72
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Label {
                                            text: description || qsTr("Nouvelle activité")
                                            color: root.ink2
                                            font.pixelSize: 11
                                            font.family: Theme.fontFamily
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: root.timeLabel(timestamp)
                                            color: root.ink3
                                            font.pixelSize: 10
                                            font.family: Theme.fontFamily
                                        }
                                    }
                                }
                            }
                            Label {
                                visible: typeof auditLogModel === "undefined" || !auditLogModel || auditLogModel.count === 0
                                text: qsTr("Aucune activité récente")
                                color: root.ink3
                                font.pixelSize: 12
                                font.family: Theme.fontFamily
                                Layout.topMargin: 8
                                Layout.bottomMargin: 12
                            }
                        }
                    }
                }
            }
        }
    }
}