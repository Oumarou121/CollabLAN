import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * SettingsView - ecran « Parametres » en Ligne claire :
 *
 *   [surtitre · « Réglages de X sur POSTE. » · portee ...   3 valeurs]
 *   [Apparence | Ce poste | Notifications et sons | Compte | Réseau   ]
 *   [groupes de reglages (libelle | reglage)          | apercu/fiche ]
 *
 * Chaque groupe dit a qui il s'applique. Un reglage choisi est enregistre
 * tout de suite (plus de barre « Enregistrer ») ; les champs saisis (nom du
 * poste, priorite de secours, ports) ont leur Enregistrer / Annuler sur la
 * ligne. `category` garde les cles historiques (appearance | machine |
 * notifications | account | network) : l'Administration ouvre "network".
 */
Item {
    id: root
    objectName: "settingsView"

    signal backRequested()
    signal logoutRequested(var beforeLogout)
    signal historyRequested()
    signal serverTrustRequested()

    property string category: "appearance"
    readonly property var categories: [
        { key: "appearance", label: qsTr("Apparence") },
        { key: "machine", label: qsTr("Ce poste") },
        { key: "notifications", label: qsTr("Notifications et sons") },
        { key: "account", label: qsTr("Compte") },
        { key: "network", label: qsTr("Réseau") }
    ]
    readonly property string cat: {
        for (let i = 0; i < root.categories.length; i++) if (root.categories[i].key === root.category) return root.category
        return "appearance"
    }
    readonly property string breadcrumbLeaf: {
        for (let i = 0; i < root.categories.length; i++) if (root.categories[i].key === root.cat) return root.categories[i].label
        return ""
    }
    onCategoryChanged: pageScroll.contentY = 0

    readonly property var settings: (typeof settingsModel !== "undefined") ? settingsModel : null
    readonly property var election: (typeof electionService !== "undefined") ? electionService : null
    readonly property var audio: (typeof audioService !== "undefined") ? audioService : null
    readonly property var app: (typeof application !== "undefined") ? application : null
    readonly property bool isAdmin: (typeof userManager !== "undefined" && userManager) ? userManager.currentUserIsAdmin : false
    readonly property string userName: (typeof userManager !== "undefined" && userManager && userManager.currentUsername) ? userManager.currentUsername : ""
    readonly property string hereName: root.settings && root.settings.machineName ? root.settings.machineName : ""
    readonly property string roleLabel: root.election ? (root.election.roleLabel || "") : ""
    readonly property string roleKind: root.roleLabel === "SERVER" ? "server" : root.roleLabel === "TEMP_SERVER" ? "backup" : "client"

    // ---- Avis --------------------------------------------------------------------
    property string restartNote: ""          // ports enregistres, en attente du redemarrage
    property string notice: ""
    function showNotice(text) { root.notice = text; noticeTimer.restart() }
    Timer { id: noticeTimer; interval: 7000; onTriggered: root.notice = "" }

    property string roleConfirm: ""          // promote | demote
    function applyRole() {
        const a = root.roleConfirm
        root.roleConfirm = ""
        if (!root.app) return
        const ok = a === "promote" ? root.app.promoteToServer() : root.app.demoteToClient()
        if (!ok) root.showNotice(a === "promote" ? qsTr("Ce poste n'a pas pu devenir serveur.") : qsTr("Ce poste n'a pas pu redevenir client."))
    }

    // ---- Mise en page -------------------------------------------------------------
    readonly property real pageW: width - 2 * Theme.pagePadding
    readonly property bool heroWide: pageW > 980
    readonly property bool hasFiche: root.cat === "appearance" || root.cat === "machine"
    readonly property bool ficheDocked: pageW > 980
    readonly property real ficheW: pageW > 1240 ? 340 : 290

    component SectionTab: AbstractButton {
        id: st
        property bool current: false
        property bool dot: false
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        padding: 0
        implicitHeight: 46
        implicitWidth: stRow.implicitWidth
        Accessible.role: Accessible.PageTab
        Accessible.name: st.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Item {
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 3; color: st.current ? Theme.ruleInk : "transparent" }
            Rectangle { anchors.fill: parent; anchors.margins: -3; color: "transparent"; radius: Theme.radiusSheet; border.width: st.visualFocus ? 2 : 0; border.color: Theme.focusRing }
        }
        contentItem: Item {
            Row {
                id: stRow
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.verticalCenter: parent.verticalCenter; text: st.text; color: st.current || st.hovered ? Theme.ink : Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(19); font.weight: st.current ? Theme.weightBold : Theme.weightRegular }
                Rectangle { visible: st.dot; anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 3.5; color: Theme.warningColor }
            }
        }
    }

    component Notice: Rectangle {
        id: nt
        property string text: ""
        property string iconPath: Icons.alertTriangle
        property color tone: Theme.dangerColor
        property color toneInk: Theme.dangerInk
        signal dismissed()
        Layout.fillWidth: true
        implicitHeight: ntRow.implicitHeight + 20
        color: Theme.surface0
        border.width: 1
        border.color: Theme.line
        Rectangle { width: 3; height: parent.height; color: nt.tone }
        RowLayout {
            id: ntRow
            anchors.verticalCenter: parent.verticalCenter
            x: 16
            width: parent.width - 26
            spacing: 12
            LineIcon { path: nt.iconPath; size: 16; strokeWidth: 1.8; color: nt.toneInk }
            Text { Layout.fillWidth: true; textFormat: Text.StyledText; text: nt.text; wrapMode: Text.WordWrap; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
            TextLink { text: qsTr("Compris"); arrow: false; onClicked: nt.dismissed() }
        }
    }

    // ======================================================================
    // Page
    // ======================================================================
    Rectangle { anchors.fill: parent; color: Theme.bg }

    Flickable {
        id: pageScroll
        objectName: "pageFlick"
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.y + pageColumn.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: pageColumn
            x: Theme.pagePadding
            y: Theme.compact ? 16 : 20
            width: pageScroll.width - 2 * Theme.pagePadding
            spacing: 20

            // ---- En-tete ------------------------------------------------------
            GridLayout {
                Layout.fillWidth: true
                columns: root.heroWide ? 2 : 1
                columnSpacing: 24
                rowSpacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: 6
                    CapsLabel {
                        Layout.fillWidth: true
                        text: new Date().toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy") + (root.hereName.length ? " · " + root.hereName : "")
                    }
                    Text {
                        Layout.fillWidth: true
                        textFormat: Text.StyledText
                        text: {
                            const first = root.userName.split(" ")[0]
                            const esc = function(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;") }
                            return root.hereName.length ? qsTr("Réglages de <b>%1</b> sur <b>%2</b>.").arg(esc(first)).arg(esc(root.hereName))
                                                        : qsTr("Réglages de <b>%1</b> sur ce poste.").arg(esc(first))
                        }
                        color: Theme.ink
                        font.family: Theme.fontFamilySerif
                        font.pixelSize: root.height < 720 ? Theme.fs(30) : Theme.fontSizeGreeting
                        elide: Text.ElideRight
                        Accessible.role: Accessible.Heading
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 600
                        Layout.topMargin: 2
                        wrapMode: Text.WordWrap
                        text: qsTr("Chaque groupe dit à qui il s'applique : à vous sur ce poste, à ce poste, ou à tout le réseau. Un réglage choisi est enregistré tout de suite.")
                        color: Theme.ink2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(14.5)
                    }
                }

                // Trois valeurs courtes (menent a la categorie)
                Row {
                    visible: root.heroWide
                    Layout.alignment: Qt.AlignRight | Qt.AlignBottom
                    Repeater {
                        model: [
                            { key: "appearance", label: qsTr("Apparence"),
                              value: Theme.mode === "dark" ? qsTr("Nuit") : Theme.mode === "system" ? qsTr("Système") : qsTr("Papier"),
                              ctx: Theme.accentPalettes[Theme.accentName].label.toLowerCase() + " · " + qsTr("texte %1 %").arg(Math.round(Theme.fontScale * 100)) },
                            { key: "notifications", label: qsTr("Alertes"),
                              value: root.settings && root.settings.enableNotifications ? qsTr("Activées") : qsTr("Coupées"),
                              ctx: root.audio && root.audio.soundEnabled ? qsTr("sons à %1 %").arg(Math.round(root.audio.volume * 100)) : qsTr("sons coupés") },
                            { key: "network", label: qsTr("Rôle"),
                              value: root.roleKind === "server" ? qsTr("Serveur") : root.roleKind === "backup" ? qsTr("Secours") : qsTr("Client"),
                              ctx: root.roleKind === "server" ? qsTr("officiel · génération %1").arg(root.election ? root.election.epoch : 0)
                                   : root.roleKind === "backup" ? qsTr("en attendant le serveur") : qsTr("relié au serveur") }
                        ]
                        delegate: Item {
                            id: fig
                            required property var modelData
                            required property int index
                            readonly property bool on: root.cat === fig.modelData.key
                            width: sf.width + (index === 0 ? 0 : 16) + (index === 2 ? 0 : 16)
                            height: sf.implicitHeight + 6
                            Rectangle { visible: fig.index > 0; width: 1; height: sf.implicitHeight; color: Theme.line }
                            SerifFigure {
                                id: sf
                                x: fig.index === 0 ? 0 : 16
                                width: Math.max(implicitWidth, 100)
                                label: fig.modelData.label
                                value: fig.modelData.value
                                context: fig.modelData.ctx
                                valueSize: root.pageW > 1240 ? Theme.fs(26) : Theme.fs(22)
                                onClicked: root.category = fig.modelData.key
                            }
                            Rectangle { visible: fig.on; x: sf.x; y: sf.implicitHeight + 4; width: sf.width; height: 2; color: Theme.ruleInk }
                        }
                    }
                }
            }

            // ---- Categories -------------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: -4
                spacing: 0
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 2; color: Theme.ruleInk }
                Flickable {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    implicitHeight: tabRow.implicitHeight
                    contentWidth: tabRow.implicitWidth
                    interactive: contentWidth > width
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: tabRow
                        spacing: 26
                        Repeater {
                            model: root.categories
                            delegate: SectionTab {
                                required property var modelData
                                text: modelData.label
                                current: root.cat === modelData.key
                                dot: modelData.key === "network" && root.restartNote.length > 0
                                onClicked: root.category = modelData.key
                            }
                        }
                    }
                }
                Notice {
                    visible: root.restartNote.length > 0
                    Layout.topMargin: 14
                    text: root.restartNote
                    iconPath: Icons.restart
                    tone: Theme.warningColor
                    toneInk: Theme.warningInk
                    onDismissed: root.restartNote = ""
                }
                Notice {
                    visible: root.notice.length > 0
                    Layout.topMargin: 14
                    text: root.notice
                    onDismissed: root.notice = ""
                }
                Rectangle { Layout.fillWidth: true; Layout.topMargin: root.restartNote.length || root.notice.length ? 14 : 0; Layout.preferredHeight: 1; color: Theme.line }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: -20
                columns: root.hasFiche && root.ficheDocked ? 2 : 1
                columnSpacing: 0
                rowSpacing: 0

                // -- Reglages de la categorie ---------------------------------------
                Item {
                    Layout.fillWidth: true
                    Layout.maximumWidth: root.hasFiche ? Number.POSITIVE_INFINITY : 1000
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: formLoader.implicitHeight + 28
                    Loader {
                        id: formLoader
                        x: 0; y: 4
                        width: parent.width - (root.hasFiche && root.ficheDocked ? 28 : 0)
                        sourceComponent: root.cat === "machine" ? machineComp
                                       : root.cat === "notifications" ? soundComp
                                       : root.cat === "account" ? accountComp
                                       : root.cat === "network" ? networkComp
                                       : appearanceComp
                    }
                }

                // -- Fiche (apercu ou « Vu par les autres ») ----------------------------
                Item {
                    visible: root.hasFiche
                    Layout.preferredWidth: root.ficheDocked ? root.ficheW : -1
                    Layout.fillWidth: !root.ficheDocked
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: ficheLoader.implicitHeight + 36
                    Rectangle {
                        width: root.ficheDocked ? 1 : parent.width
                        height: root.ficheDocked ? parent.height : 1
                        color: Theme.line
                    }
                    Loader {
                        id: ficheLoader
                        x: root.ficheDocked ? 24 : 0
                        y: 18
                        width: parent.width - x
                        sourceComponent: root.cat === "machine" ? machineFicheComp : previewComp
                    }
                }
            }
        }
    }

    // ---- Categories (une seule construite a la fois) -----------------------------
    Component { id: appearanceComp; AppearanceSettings {} }
    Component { id: machineComp; MachineSettings {} }
    Component { id: soundComp; SoundSettings {} }
    Component {
        id: accountComp
        AccountSettings {
            passwordChanged: passwordSheet.done
            onPasswordRequested: passwordSheet.open = true
            onLogoutRequested: function(beforeLogout) { root.logoutRequested(beforeLogout) }
        }
    }
    Component {
        id: networkComp
        NetworkSettings {
            onPromoteRequested: root.roleConfirm = "promote"
            onDemoteRequested: root.roleConfirm = "demote"
            onHistoryRequested: root.historyRequested()
            onServerTrustRequested: root.serverTrustRequested()
            onPortsSaved: function(messaging, discovery) {
                root.restartNote = qsTr("Ports enregistrés : messagerie <b>%1</b>, découverte <b>%2</b>. LocaLink les utilisera à son prochain démarrage ; d'ici là, rien ne change.").arg(messaging).arg(discovery)
            }
        }
    }
    Component { id: previewComp; AppearancePreview {} }
    Component {
        id: machineFicheComp
        MachineFiche {
            readonly property var form: formLoader.item
            shownName: form && form.draftName !== undefined ? form.draftName.trim() : root.hereName
            editing: !!form && !!form.editingName
            isServer: root.roleKind !== "client"
            userName: root.userName
        }
    }

    // ---- Fenetres -------------------------------------------------------------------
    PasswordSheet {
        id: passwordSheet
        onCloseRequested: passwordSheet.open = false
    }

    SheetModal {
        id: roleSheet
        open: root.roleConfirm.length > 0
        boldTitle: false
        sheetWidth: 480
        kicker: qsTr("Rôle de ce poste")
        title: root.roleConfirm === "promote"
               ? (root.hereName.length ? qsTr("Faire de <b>%1</b> le serveur ?").arg(root.hereName) : qsTr("Faire de ce poste le <b>serveur</b> ?"))
               : qsTr("Redevenir <b>client</b> ?")
        onCloseRequested: root.roleConfirm = ""

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                visible: root.roleConfirm === "promote"
                Layout.fillWidth: true
                text: qsTr("Ce poste acceptera les connexions des autres postes et relaiera leurs échanges.")
                wrapMode: Text.WordWrap
                color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: warnRow.implicitHeight + 24
                color: Theme.dangerSoft
                Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
                RowLayout {
                    id: warnRow
                    x: 14; y: 12
                    width: parent.width - 28
                    spacing: 12
                    LineIcon { Layout.alignment: Qt.AlignTop; path: Icons.alertTriangle; size: 18; strokeWidth: 1.8; color: Theme.dangerInk }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.StyledText
                            text: root.roleConfirm === "promote" ? qsTr("Un seul poste doit avoir ce rôle sur le réseau.")
                                                                 : qsTr("Ce poste cessera d'accepter les connexions.")
                            wrapMode: Text.WordWrap
                            color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.roleConfirm === "promote" ? qsTr("Vérifiez qu'aucun autre poste ne le garde : redonnez-lui le rôle client si besoin.")
                                                                 : qsTr("Assurez-vous qu'un autre poste a été désigné serveur : sinon, plus aucun poste ne pourra échanger.")
                            wrapMode: Text.WordWrap
                            color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5)
                        }
                    }
                }
            }
        }

        footer: [
            AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.roleConfirm = "" },
            AppButton {
                variant: root.roleConfirm === "demote" ? "danger" : "ink"
                iconPath: root.roleConfirm === "promote" ? Icons.server : ""
                text: root.roleConfirm === "promote" ? qsTr("Devenir serveur") : qsTr("Redevenir client")
                onClicked: root.applyRole()
            }
        ]
    }
}
