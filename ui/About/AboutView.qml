import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "../Call/callPeople.js" as People

/*
 * AboutView - ecran « À propos » en Ligne claire : une page de colophon.
 *
 *   [marque · version · phrase « sans Internet » ........ Version | Ce poste]
 *   [Ce que fait LocaLink (6 entrees) / Sur ce poste     | editeur, licence,]
 *   [                                                     | fabrique avec    ]
 *
 * « Sur ce poste » ne montre que ce que l'application sait reellement :
 * settingsModel (nom, ports), electionService (role, generation, serveur
 * actif), userManager (compte), Qt.platform.os. Le texte de la licence est
 * celui du fichier LICENSE.
 */
Item {
    id: root
    objectName: "aboutView"

    signal backRequested()
    signal navigationRequested(string route)

    readonly property string appVersion: "1.0.0"
    readonly property string companyName: "NEXIS"
    readonly property string companyFullName: "Next Intelligent Systems"
    readonly property int copyrightYear: 2026

    readonly property var settings: (typeof settingsModel !== "undefined") ? settingsModel : null
    readonly property var election: (typeof electionService !== "undefined") ? electionService : null
    readonly property var users: (typeof userManager !== "undefined") ? userManager : null
    readonly property var peersSource: (typeof peersModel !== "undefined") ? peersModel : null

    readonly property string machineName: root.settings && root.settings.machineName ? root.settings.machineName : ""
    readonly property bool isAdmin: root.users ? !!root.users.currentUserIsAdmin : false
    readonly property string userName: root.users && root.users.currentUsername ? root.users.currentUsername : ""
    readonly property string roleLabel: root.election ? (root.election.roleLabel || "") : ""
    readonly property string roleKind: root.roleLabel === "SERVER" ? "server" : root.roleLabel === "TEMP_SERVER" ? "backup" : "client"
    readonly property string roleWord: root.roleKind === "server" ? qsTr("Serveur officiel") : root.roleKind === "backup" ? qsTr("Serveur de secours") : qsTr("Client")
    // Relu quand la liste des postes change (le nom du serveur actif en depend).
    property int peersRevision: 0
    Connections {
        target: root.peersSource
        ignoreUnknownSignals: true
        function onCountChanged() { root.peersRevision++ }
        function onModelReset() { root.peersRevision++ }
        function onRowsInserted() { root.peersRevision++ }
    }
    readonly property string activeServer: {
        root.peersRevision
        const uuid = root.election ? (root.election.activeServerUuid || "") : ""
        if (!uuid.length) return ""
        const p = People.readPeers(root.peersSource)
        for (let i = 0; i < p.length; i++) if (p[i].id === uuid) return p[i].machine || uuid
        return uuid
    }
    readonly property string roleContext: root.roleKind === "client"
                                          ? (root.activeServer.length ? qsTr("relié à %1").arg(root.activeServer) : qsTr("relié au serveur du réseau"))
                                          : (root.election ? qsTr("génération %1").arg(root.election.epoch || 0) : "")
    readonly property string systemName: {
        switch (Qt.platform.os) {
        case "windows": return "Windows"
        case "osx": case "macos": return "macOS"
        case "linux": return "Linux"
        }
        return Qt.platform.os
    }

    readonly property var features: [
        { icon: Icons.link, title: qsTr("Découverte automatique"), desc: qsTr("Les postes qui lancent LocaLink sur le même réseau local se trouvent tout seuls, sans configuration."), route: "peers", target: qsTr("Postes") },
        { icon: Icons.messageCircle, title: qsTr("Discussions"), desc: qsTr("Conversations à deux ou en groupe, en temps réel ; l'historique reste sur les postes."), route: "chat", target: qsTr("Discussions") },
        { icon: Icons.phoneLine, title: qsTr("Appels"), desc: qsTr("Appels vocaux de poste à poste, chiffrés, sans serveur extérieur."), route: "call", target: qsTr("Appels") },
        { icon: Icons.exchange, title: qsTr("Transferts"), desc: qsTr("Fichiers et dossiers envoyés directement d'un poste à l'autre, rangés par correspondant."), route: "transfer", target: qsTr("Transferts") },
        { icon: Icons.folder, title: qsTr("Dossiers partagés"), desc: qsTr("Un dossier tenu à jour sur plusieurs postes, avec des droits par personne."), route: "folder", target: qsTr("Dossiers partagés") },
        { icon: Icons.shield, title: qsTr("Sécurité"), desc: qsTr("Seuls les postes autorisés rejoignent le réseau ; les échanges sont chiffrés (TLS) et tracés dans le journal d'audit."), route: root.isAdmin ? "admin" : "", target: qsTr("Administration") }
    ]
    readonly property var stack: [
        ["C++23", qsTr("langage")], ["Qt 6 · QML", qsTr("interface")], ["SQLite", qsTr("données locales")],
        ["TCP · UDP · WebSocket", qsTr("réseau local")], ["WebRTC", qsTr("appels")], ["OpenSSL", qsTr("chiffrement TLS")]
    ]

    // Texte du fichier LICENSE (la licence se cite dans sa langue d'origine).
    readonly property string licenseText: "MIT License\n\nCopyright (c) 2026 LocaLink\n\n"
        + "Permission is hereby granted, free of charge, to any person obtaining a copy\n"
        + "of this software and associated documentation files (the \"Software\"), to deal\n"
        + "in the Software without restriction, including without limitation the rights\n"
        + "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n"
        + "copies of the Software, and to permit persons to whom the Software is\n"
        + "furnished to do so, subject to the following conditions:\n\n"
        + "The above copyright notice and this permission notice shall be included in all\n"
        + "copies or substantial portions of the Software.\n\n"
        + "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n"
        + "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n"
        + "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n"
        + "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n"
        + "LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n"
        + "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\n"
        + "SOFTWARE."

    // ---- Copier ---------------------------------------------------------------
    property bool copied: false
    property bool licenseOpen: false
    TextEdit { id: clipboardHelper; visible: false }
    function copyText(t) { clipboardHelper.text = t; clipboardHelper.selectAll(); clipboardHelper.copy() }
    function copyInfo() {
        const lines = [
            "LocaLink " + root.appVersion,
            qsTr("Poste : %1").arg(root.machineName || "—"),
            qsTr("Rôle sur le réseau : %1").arg(root.roleWord + (root.roleContext.length ? " (" + root.roleContext + ")" : "")),
            qsTr("Compte : %1").arg(root.userName.length ? root.userName + " · " + (root.isAdmin ? qsTr("administrateur") : qsTr("utilisateur")) : "—"),
            qsTr("Ports : messagerie %1, découverte %2").arg(root.settings ? root.settings.messagingPort : "—").arg(root.settings ? root.settings.discoveryPort : "—"),
            qsTr("Système : %1").arg(root.systemName)
        ]
        root.copyText(lines.join("\n"))
        root.copied = true
        copiedTimer.restart()
    }
    Timer { id: copiedTimer; interval: 8000; onTriggered: root.copied = false }

    // ======================================================================
    // Composants
    // ======================================================================
    readonly property real pageW: width - 2 * Theme.pagePadding
    readonly property bool heroWide: pageW > 1180
    readonly property bool colophonDocked: pageW > 980
    readonly property bool twoCols: mainCol.width > 700

    component Fact: Item {
        property string key: ""
        property string value: ""
        property bool mono: false
        property string glyph: ""
        Layout.fillWidth: true
        implicitHeight: 38
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        RowLayout {
            anchors.fill: parent
            spacing: 16
            Text { text: parent.parent.key; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
            Item { Layout.fillWidth: true }
            StateGlyph { visible: parent.parent.glyph.length > 0; kind: parent.parent.glyph; size: 10 }
            Text {
                Layout.maximumWidth: parent.width * 0.62
                text: parent.parent.value
                elide: Text.ElideMiddle
                color: Theme.ink
                font.family: parent.parent.mono ? "Cascadia Mono" : Theme.fontFamily
                font.pixelSize: parent.parent.mono ? Theme.fs(12) : Theme.fs(13)
                font.weight: parent.parent.glyph.length > 0 ? Theme.weightSemibold : Theme.weightRegular
                font.features: ({ "tnum": 1 })
            }
        }
    }

    component ColophonSection: ColumnLayout {
        property string title: ""
        property bool first: false
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: 6
        Rectangle { visible: !parent.first && root.colophonDocked; Layout.fillWidth: true; Layout.preferredHeight: 1; Layout.bottomMargin: 10; color: Theme.line }
        CapsLabel { Layout.bottomMargin: 2; text: parent.title }
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
        contentHeight: pageColumn.y + pageColumn.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: pageColumn
            x: Theme.pagePadding
            y: Theme.compact ? 16 : 20
            width: pageScroll.width - 2 * Theme.pagePadding
            spacing: 20

            // ---- En-tete --------------------------------------------------
            GridLayout {
                Layout.fillWidth: true
                columns: root.heroWide ? 2 : 1
                columnSpacing: 32
                rowSpacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: 8
                    CapsLabel { Layout.fillWidth: true; text: qsTr("LocaLink · version %1").arg(root.appVersion) }
                    RowLayout {
                        spacing: 14
                        BrandMark { size: 56 }
                        Text {
                            text: "LocaLink"
                            color: Theme.ink
                            font.family: Theme.fontFamilySerif
                            font.pixelSize: Theme.fs(46)
                            font.weight: Theme.weightBold
                            Accessible.role: Accessible.Heading
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 620
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        text: qsTr("Pour travailler en équipe sur le réseau local : discuter, s'appeler, s'envoyer des fichiers et partager des dossiers, <b>sans Internet</b>.")
                        color: Theme.ink2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(14.5)
                        lineHeight: 1.15
                    }
                }

                Item {
                    Layout.alignment: root.heroWide ? (Qt.AlignRight | Qt.AlignBottom) : Qt.AlignLeft
                    Layout.fillWidth: !root.heroWide
                    implicitWidth: figRow.implicitWidth
                    implicitHeight: figRow.implicitHeight + (root.heroWide ? 0 : 12)
                    Rectangle { visible: !root.heroWide; width: parent.width; height: 1; color: Theme.line }
                    Row {
                        id: figRow
                        y: root.heroWide ? 0 : 12
                        width: root.heroWide ? implicitWidth : parent.width
                        Repeater {
                            model: [
                                { label: qsTr("Version"), value: root.appVersion, ctx: qsTr("première version"), small: false },
                                { label: qsTr("Ce poste"), value: root.roleWord, ctx: root.roleContext, small: true }
                            ]
                            delegate: Item {
                                id: fig
                                required property var modelData
                                required property int index
                                width: root.heroWide ? sf.width + (index === 0 ? 22 : 22) : figRow.width / 2
                                height: sf.implicitHeight
                                Rectangle { visible: fig.index > 0; width: 1; height: parent.height; color: Theme.line }
                                SerifFigure {
                                    id: sf
                                    x: fig.index === 0 ? 0 : (root.heroWide ? 22 : 18)
                                    width: Math.max(implicitWidth, 110)
                                    focusPolicy: Qt.NoFocus
                                    hoverEnabled: false
                                    label: fig.modelData.label
                                    value: fig.modelData.value
                                    context: fig.modelData.ctx
                                    valueSize: fig.modelData.small ? Theme.fs(30) : (root.heroWide && root.height >= 720 ? Theme.fontSizeFigure : Theme.fs(32))
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: -4; Layout.preferredHeight: 2; color: Theme.ruleInk }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: -20
                columns: root.colophonDocked ? 2 : 1
                columnSpacing: 0
                rowSpacing: 0

                // -- Fonctions et ce poste -------------------------------------
                ColumnLayout {
                    id: mainCol
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 18
                    Layout.rightMargin: root.colophonDocked ? 28 : 0
                    spacing: 0

                    CapsLabel { Layout.bottomMargin: 10; text: qsTr("Ce que fait LocaLink") }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        columns: root.twoCols ? 2 : 1
                        columnSpacing: 0
                        rowSpacing: 0
                        Repeater {
                            model: root.features
                            delegate: Item {
                                id: ft
                                required property var modelData
                                required property int index
                                readonly property bool rightCol: root.twoCols && ft.index % 2 === 1
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.fillHeight: true
                                implicitHeight: ftRow.implicitHeight + 28
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                                Rectangle { visible: root.twoCols && !ft.rightCol; anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }
                                RowLayout {
                                    id: ftRow
                                    x: ft.rightCol ? 16 : 0
                                    y: 14
                                    width: parent.width - x - 16
                                    spacing: 12
                                    Text {
                                        Layout.alignment: Qt.AlignTop
                                        Layout.preferredWidth: 22
                                        text: String(ft.index + 1).padStart(2, "0")
                                        color: Theme.ink3
                                        font.family: Theme.fontFamilySerif
                                        font.pixelSize: Theme.fs(13)
                                        font.weight: Theme.weightBold
                                    }
                                    Rectangle {
                                        Layout.alignment: Qt.AlignTop
                                        implicitWidth: 34; implicitHeight: 34; radius: 17
                                        color: "transparent"; border.width: 1; border.color: Theme.lineStrong
                                        LineIcon { anchors.centerIn: parent; path: ft.modelData.icon; size: 16; strokeWidth: 1.7; color: Theme.ink2 }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 3
                                        Text { Layout.fillWidth: true; text: ft.modelData.title; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold; wrapMode: Text.WordWrap }
                                        Text { Layout.fillWidth: true; text: ft.modelData.desc; color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); lineHeight: 1.15; wrapMode: Text.WordWrap }
                                        TextLink {
                                            visible: ft.modelData.route.length > 0
                                            Layout.topMargin: 4
                                            text: qsTr("Ouvrir %1").arg(ft.modelData.target)
                                            fontSize: Theme.fs(12)
                                            onClicked: root.navigationRequested(ft.modelData.route)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Sur ce poste
                    CapsLabel { Layout.topMargin: 26; Layout.bottomMargin: 10; text: qsTr("Sur ce poste") }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: root.twoCols ? 2 : 1
                        columnSpacing: 28
                        rowSpacing: 0
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            spacing: 0
                            Fact { key: qsTr("Nom du poste"); value: root.machineName.length ? root.machineName : "—"; mono: true }
                            Fact { key: qsTr("Rôle sur le réseau"); value: root.roleWord; glyph: root.roleKind === "backup" ? "away" : "online" }
                            Fact { key: qsTr("Compte"); value: root.userName.length ? root.userName + " · " + (root.isAdmin ? qsTr("administrateur") : qsTr("utilisateur")) : "—" }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            spacing: 0
                            Fact { key: qsTr("Port de messagerie"); value: root.settings ? String(root.settings.messagingPort) : "—"; mono: true }
                            Fact { key: qsTr("Port de découverte"); value: root.settings ? String(root.settings.discoveryPort) : "—"; mono: true }
                            Fact { key: qsTr("Système"); value: root.systemName }
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 14
                        spacing: 12
                        AppButton { variant: "line"; size: "small"; iconPath: Icons.copy; text: qsTr("Copier ces informations"); onClicked: root.copyInfo() }
                        Row {
                            height: 30
                            spacing: 6
                            StateGlyph { visible: root.copied; anchors.verticalCenter: parent.verticalCenter; kind: "ok"; size: 11 }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.copied ? qsTr("Copié : collez-les dans un message à votre administrateur.")
                                                  : qsTr("Utile pour demander de l'aide : version, poste, rôle et ports.")
                                color: root.copied ? Theme.successInk : Theme.ink3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12.5)
                                font.weight: root.copied ? Theme.weightSemibold : Theme.weightRegular
                            }
                        }
                    }
                }

                // -- Colophon ----------------------------------------------------
                Item {
                    Layout.preferredWidth: root.colophonDocked ? (root.pageW > 1240 ? 320 : 290) : -1
                    Layout.fillWidth: !root.colophonDocked
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: colophon.implicitHeight + 34
                    Rectangle { visible: root.colophonDocked; width: 1; height: Math.max(parent.height, mainCol.height + 18); color: Theme.line }
                    Rectangle { visible: !root.colophonDocked; width: parent.width; height: 1; y: 16; color: Theme.line }

                    GridLayout {
                        id: colophon
                        x: root.colophonDocked ? 24 : 0
                        y: root.colophonDocked ? 18 : 32
                        width: parent.width - x
                        columns: root.colophonDocked ? 1 : 2
                        columnSpacing: 28
                        rowSpacing: 18

                        ColophonSection {
                            first: true
                            title: qsTr("Éditeur")
                            Text { text: root.companyName; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(20); font.weight: Theme.weightBold }
                            Text { text: root.companyFullName; color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
                            Text { Layout.topMargin: 4; text: qsTr("© %1 %2. Tous droits réservés.").arg(root.copyrightYear).arg(root.companyName); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5) }
                        }
                        ColophonSection {
                            title: qsTr("Licence")
                            Text { Layout.fillWidth: true; text: qsTr("Distribué sous licence MIT : libre d'utiliser, de modifier et de redistribuer, avec la mention de copyright."); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); lineHeight: 1.15; wrapMode: Text.WordWrap }
                            TextLink { Layout.topMargin: 4; text: qsTr("Lire la licence"); arrow: false; fontSize: Theme.fs(12.5); onClicked: root.licenseOpen = true }
                        }
                        ColophonSection {
                            title: qsTr("Fabriqué avec")
                            Repeater {
                                model: root.stack
                                delegate: Item {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    Rectangle { visible: index < root.stack.length - 1; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
                                    Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; text: modelData[1]; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
                                }
                            }
                            Text { Layout.fillWidth: true; Layout.topMargin: 6; text: qsTr("Polices Inter et PT Serif (SIL Open Font License), intégrées à l'application."); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); lineHeight: 1.15; wrapMode: Text.WordWrap }
                        }
                        ColophonSection {
                            title: qsTr("Réseau local")
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: offRow.implicitHeight + 24
                                radius: Theme.radiusSheet
                                color: Theme.surface0
                                border.width: 1
                                border.color: Theme.line
                                RowLayout {
                                    id: offRow
                                    x: 14; y: 12
                                    width: parent.width - 28
                                    spacing: 10
                                    LineIcon { Layout.alignment: Qt.AlignTop; path: Icons.server; size: 18; strokeWidth: 1.6; color: Theme.ink2 }
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.StyledText
                                        text: qsTr("<b>Rien ne sort du réseau local.</b> Messages, fichiers et appels passent de poste à poste ou par le serveur du réseau ; aucun service en ligne n'est utilisé.")
                                        color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); lineHeight: 1.15; wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Licence ---------------------------------------------------------------
    SheetModal {
        id: licenseSheet
        open: root.licenseOpen
        kicker: qsTr("Licence")
        title: qsTr("Licence MIT")
        sheetWidth: 600
        onCloseRequested: root.licenseOpen = false

        TextEdit {
            Layout.fillWidth: true
            readOnly: true
            selectByMouse: true
            text: root.licenseText
            wrapMode: Text.WordWrap
            color: Theme.ink2
            selectionColor: Theme.selectWash
            selectedTextColor: Theme.ink
            font.family: "Cascadia Mono"
            font.pixelSize: Theme.fs(12)
        }

        footer: [
            Text { Layout.fillWidth: true; text: qsTr("Texte d'origine, en anglais."); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) },
            AppButton { variant: "line"; text: qsTr("Copier"); onClicked: root.copyText(root.licenseText) },
            AppButton { variant: "ink"; text: qsTr("Fermer"); onClicked: root.licenseOpen = false }
        ]
    }
}
