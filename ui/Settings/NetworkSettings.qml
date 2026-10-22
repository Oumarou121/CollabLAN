import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "../Call/callPeople.js" as People

/*
 * NetworkSettings - Parametres > Reseau (Ligne claire).
 *
 *   - Role de ce poste (electionService.roleLabel) : serveur officiel, de
 *     secours ou client ; « Faire de ce poste le serveur… » et « Redevenir
 *     client… » (fenetres de l'ecran hote) reserves aux administrateurs.
 *   - Secours (administrateurs) : priorite (application.setElectionPriorityWeight,
 *     enregistree en base) appliquee sur la ligne ; delai de detection en
 *     lecture seule (heartbeatTimeoutMs n'est pas enregistre).
 *   - Ports (administrateurs) : settingsModel.messagingPort / discoveryPort,
 *     lus au demarrage (main.cpp) ; l'ecran hote affiche l'avis de
 *     redemarrage (portsSaved).
 */
ColumnLayout {
    id: root
    spacing: 0

    signal promoteRequested()
    signal demoteRequested()
    signal historyRequested()
    signal portsSaved(int messaging, int discovery)

    readonly property var settings: (typeof settingsModel !== "undefined") ? settingsModel : null
    readonly property var election: (typeof electionService !== "undefined") ? electionService : null
    readonly property var app: (typeof application !== "undefined") ? application : null
    readonly property bool isAdmin: (typeof userManager !== "undefined" && userManager) ? userManager.currentUserIsAdmin : false
    readonly property string hereName: root.settings && root.settings.machineName ? root.settings.machineName : qsTr("ce poste")

    readonly property string roleLabel: root.election ? (root.election.roleLabel || "") : ""
    readonly property string roleKind: root.roleLabel === "SERVER" ? "server" : root.roleLabel === "TEMP_SERVER" ? "backup" : "client"
    readonly property int epoch: root.election && root.election.epoch !== undefined ? root.election.epoch : 0
    readonly property string activeServer: {
        const uuid = root.election ? (root.election.activeServerUuid || "") : ""
        if (root.roleKind !== "client") return root.hereName
        if (!uuid.length) return qsTr("inconnu")
        const peers = People.readPeers((typeof peersModel !== "undefined") ? peersModel : null)
        for (let i = 0; i < peers.length; i++) if (peers[i].id === uuid && peers[i].machine) return peers[i].machine
        return uuid
    }

    // ---- Priorite de secours ---------------------------------------------------------
    readonly property int savedPrio: root.election ? root.election.priorityWeight : 100
    property int draftPrio: root.savedPrio
    onSavedPrioChanged: root.draftPrio = root.savedPrio
    readonly property bool editingPrio: root.draftPrio !== root.savedPrio
    property string prioState: ""           // saved | failed
    function setPrio(v) { root.draftPrio = Math.max(1, Math.min(1000, v)); root.prioState = ""; prioInput.text = String(root.draftPrio) }
    function applyPrio() {
        const ok = root.app && root.app.setElectionPriorityWeight ? root.app.setElectionPriorityWeight(root.draftPrio) : false
        root.prioState = ok ? "saved" : "failed"
        if (!ok) root.draftPrio = root.savedPrio
        prioInput.text = String(root.draftPrio)
        stateTimer.restart()
    }

    // ---- Ports ------------------------------------------------------------------------
    readonly property int savedMsg: root.settings ? root.settings.messagingPort : 12345
    readonly property int savedDisc: root.settings ? root.settings.discoveryPort : 45454
    property string msgText: String(root.savedMsg)
    property string discText: String(root.savedDisc)
    readonly property bool editingPorts: root.msgText !== String(root.savedMsg) || root.discText !== String(root.savedDisc)
    function portOk(t) { const n = Number(t); return /^\d+$/.test(t) && n >= 1024 && n <= 65535 }
    readonly property bool portsValid: root.portOk(root.msgText) && root.portOk(root.discText) && root.msgText !== root.discText
    property bool portsSavedFlag: false
    function savePorts() {
        if (!root.settings || !root.portsValid) return
        root.settings.messagingPort = Number(root.msgText)
        root.settings.discoveryPort = Number(root.discText)
        root.settings.save()
        root.portsSavedFlag = true
        stateTimer.restart()
        root.portsSaved(root.settings.messagingPort, root.settings.discoveryPort)
    }
    function cancelPorts() {
        root.msgText = String(root.savedMsg); root.discText = String(root.savedDisc)
        msgField.text = root.msgText; discField.text = root.discText
    }
    Timer { id: stateTimer; interval: 6000; onTriggered: { root.prioState = ""; root.portsSavedFlag = false } }

    component Fact: RowLayout {
        property string key: ""
        property string value: ""
        property bool mono: false
        spacing: 22
        Text { Layout.preferredWidth: 96; text: parent.key; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
        Text { text: parent.value; color: Theme.ink; font.family: parent.mono ? "Cascadia Mono" : Theme.fontFamily; font.pixelSize: parent.mono ? Theme.fs(12) : Theme.fs(13); font.features: ({ "tnum": 1 }) }
    }
    component Locked: RowLayout {
        property string text: ""
        Layout.fillWidth: true
        spacing: 8
        LineIcon { Layout.alignment: Qt.AlignTop; Layout.topMargin: 1; path: Icons.lock; size: 14; strokeWidth: 1.8; color: Theme.ink3 }
        Text { Layout.fillWidth: true; text: parent.text; wrapMode: Text.WordWrap; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5) }
    }
    component StepButton: AbstractButton {
        id: sb
        property string iconPath: ""
        implicitWidth: 34
        implicitHeight: 36
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        autoRepeat: true
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle { color: sb.hovered ? Theme.hover : "transparent"; border.width: sb.visualFocus ? 2 : 0; border.color: Theme.focusRing }
        contentItem: Item { LineIcon { anchors.centerIn: parent; path: sb.iconPath; size: 14; strokeWidth: 1.8; color: sb.hovered ? Theme.ink : Theme.ink2 } }
    }

    // ---- Role ------------------------------------------------------------------------
    SettingGroup {
        first: true
        title: qsTr("Rôle de ce poste")
        scopeIcon: Icons.share
        scopeText: qsTr("Vu par <b>tout le réseau</b>")

        SettingRow {
            label: qsTr("Rôle")
            help: qsTr("Le serveur relaie les échanges entre les postes. Un seul poste doit avoir ce rôle, les autres restent clients.")
            Text {
                Layout.alignment: Qt.AlignLeft
                textFormat: Text.StyledText
                text: root.roleKind === "server" ? qsTr("Serveur <b>officiel</b>")
                      : root.roleKind === "backup" ? qsTr("Serveur <b>de secours</b>")
                      : qsTr("Poste <b>client</b>")
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(26)
            }
            Row {
                Layout.alignment: Qt.AlignLeft
                spacing: 7
                StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: root.roleKind === "backup" ? "away" : "online"; size: 12 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.roleKind === "server" ? qsTr("Les autres postes passent par lui.")
                          : root.roleKind === "backup" ? qsTr("Il relaie les échanges en attendant le retour du serveur officiel.")
                          : qsTr("Il passe par le serveur %1 pour échanger.").arg(root.activeServer)
                    color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                }
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignLeft
                Layout.topMargin: 2
                spacing: 6
                Fact { key: qsTr("Serveur actif"); value: root.activeServer; mono: true }
                Fact { key: qsTr("Génération"); value: String(root.epoch) }
            }
            Flow {
                visible: root.isAdmin
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8
                AppButton { visible: root.roleKind !== "server"; variant: "line"; size: "small"; iconPath: Icons.server; text: qsTr("Faire de ce poste le serveur…"); onClicked: root.promoteRequested() }
                AppButton { visible: root.roleKind !== "client"; variant: "dangerGhost"; size: "small"; text: qsTr("Redevenir client…"); onClicked: root.demoteRequested() }
                TextLink { height: 30; text: qsTr("Historique des bascules"); onClicked: root.historyRequested() }
            }
            Locked { visible: !root.isAdmin; text: qsTr("Seul un administrateur peut changer le rôle de ce poste.") }
        }
    }

    // ---- Reglages avances (utilisateur) -------------------------------------------------
    SettingGroup {
        visible: !root.isAdmin
        title: qsTr("Réglages avancés")
        scopeIcon: Icons.monitor
        scopeText: qsTr("<b>Ce poste</b>")
        SettingRow {
            label: qsTr("Secours et ports")
            Locked { text: qsTr("La priorité de secours et les ports réseau sont réservés aux administrateurs.") }
        }
    }

    // ---- Secours -----------------------------------------------------------------------
    SettingGroup {
        visible: root.isAdmin
        title: qsTr("Secours")
        scopeIcon: Icons.monitor
        scopeText: qsTr("<b>Ce poste</b> · immédiat")

        SettingRow {
            label: qsTr("Priorité de secours")
            help: qsTr("Si le serveur ne répond plus, le poste dont la valeur est la plus basse prend le relais.")
            edited: root.editingPrio
            Flow {
                Layout.fillWidth: true
                spacing: 14
                Rectangle {
                    implicitWidth: stepRow.implicitWidth + 2
                    implicitHeight: 36
                    radius: Theme.radiusSheet
                    color: Theme.surface0
                    border.width: prioInput.activeFocus ? 1.5 : 1
                    border.color: prioInput.activeFocus ? Theme.ink : Theme.lineStrong
                    Row {
                        id: stepRow
                        x: 1; y: 0
                        height: parent.height
                        StepButton { iconPath: Icons.chevronLeft; Accessible.name: qsTr("Diminuer"); onClicked: root.setPrio(root.draftPrio - 10) }
                        Rectangle { width: 1; height: parent.height; color: Theme.line }
                        TextInput {
                            id: prioInput
                            width: 64
                            height: parent.height
                            text: String(root.draftPrio)
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            validator: IntValidator { bottom: 1; top: 1000 }
                            color: Theme.ink
                            font.family: Theme.fontFamilySerif
                            font.pixelSize: Theme.fs(16)
                            font.weight: Theme.weightBold
                            selectByMouse: true
                            Accessible.name: qsTr("Priorité de secours")
                            onTextEdited: { const n = parseInt(text, 10); if (!isNaN(n)) { root.draftPrio = n; root.prioState = "" } }
                            onAccepted: if (root.editingPrio) root.applyPrio()
                            Keys.onEscapePressed: root.setPrio(root.savedPrio)
                        }
                        Rectangle { width: 1; height: parent.height; color: Theme.line }
                        StepButton { iconPath: Icons.chevronRight; Accessible.name: qsTr("Augmenter"); onClicked: root.setPrio(root.draftPrio + 10) }
                    }
                }
                AppButton { visible: root.editingPrio; variant: "ink"; size: "small"; iconPath: Icons.check; text: qsTr("Appliquer"); onClicked: root.applyPrio() }
                AppButton { visible: root.editingPrio; variant: "ghost"; size: "small"; text: qsTr("Annuler"); onClicked: root.setPrio(root.savedPrio) }
                SavedNote { visible: !root.editingPrio && root.prioState === "saved"; height: 36 }
                Text {
                    visible: root.prioState === "failed"
                    height: 36
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("La priorité n'a pas pu être enregistrée.")
                    color: Theme.dangerInk; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightSemibold
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignLeft
                Layout.preferredWidth: 200
                Layout.maximumWidth: 200
                Text { Layout.fillWidth: true; text: qsTr("1 · en premier"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11) }
                Text { text: qsTr("1000 · en dernier"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11) }
            }
        }
        SettingRow {
            label: qsTr("Délai de détection")
            help: qsTr("Temps sans nouvelles du serveur avant qu'un poste prenne le relais.")
            Text {
                Layout.alignment: Qt.AlignLeft
                text: qsTr("%1 s").arg(root.election ? Math.round(root.election.heartbeatTimeoutMs / 1000) : 15)
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(16)
                font.weight: Theme.weightBold
            }
            Text { Layout.alignment: Qt.AlignLeft; text: qsTr("Valeur fixée par l'application."); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
        }
    }

    // ---- Ports ----------------------------------------------------------------------------
    SettingGroup {
        visible: root.isAdmin
        title: qsTr("Ports")
        scopeIcon: Icons.restart
        scopeText: qsTr("Ce poste · <b>au prochain démarrage</b>")

        SettingRow {
            label: qsTr("Ports réseau")
            help: qsTr("À changer seulement si un autre logiciel occupe déjà l'un de ces ports.")
            edited: root.editingPorts
            GridLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: 420
                columns: width > 300 ? 2 : 1
                columnSpacing: 20
                rowSpacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1     // deux colonnes egales
                    spacing: 5
                    Row {
                        spacing: 6
                        Text { text: qsTr("Messagerie"); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
                        Text { text: "TCP"; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
                    }
                    FieldBox {
                        id: msgField
                        text: root.msgText
                        error: !root.portOk(root.msgText)
                        accessibleName: qsTr("Port de messagerie")
                        field.validator: IntValidator { bottom: 0; top: 65535 }
                        onEdited: { root.msgText = msgField.text; root.portsSavedFlag = false }
                        onAccepted: if (root.editingPorts) root.savePorts()
                        onEscaped: root.cancelPorts()
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1     // deux colonnes egales
                    spacing: 5
                    Row {
                        spacing: 6
                        Text { text: qsTr("Découverte"); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
                        Text { text: qsTr("UDP · le même sur tous les postes"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
                    }
                    FieldBox {
                        id: discField
                        text: root.discText
                        error: !root.portOk(root.discText)
                        accessibleName: qsTr("Port de découverte")
                        field.validator: IntValidator { bottom: 0; top: 65535 }
                        onEdited: { root.discText = discField.text; root.portsSavedFlag = false }
                        onAccepted: if (root.editingPorts) root.savePorts()
                        onEscaped: root.cancelPorts()
                    }
                }
            }
            Text {
                visible: root.editingPorts && !root.portsValid
                Layout.fillWidth: true
                text: root.msgText === root.discText ? qsTr("Les deux ports doivent être différents.") : qsTr("Un port va de 1024 à 65535.")
                color: Theme.dangerInk; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightSemibold
            }
            Flow {
                visible: root.editingPorts
                Layout.fillWidth: true
                spacing: 8
                AppButton { variant: "ink"; size: "small"; iconPath: Icons.check; enabled: root.portsValid; text: qsTr("Enregistrer"); onClicked: root.savePorts() }
                AppButton { variant: "ghost"; size: "small"; text: qsTr("Annuler"); onClicked: root.cancelPorts() }
                Text { height: 30; verticalAlignment: Text.AlignVCenter; text: qsTr("Pris en compte au prochain démarrage de LocaLink."); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
            }
            SavedNote { visible: !root.editingPorts && root.portsSavedFlag; text: qsTr("Enregistré · utilisé au prochain démarrage") }
            Text {
                visible: !root.editingPorts && !root.portsSavedFlag
                Layout.alignment: Qt.AlignLeft
                text: qsTr("Entre 1024 et 65535.")
                color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12)
            }
        }
    }
}
