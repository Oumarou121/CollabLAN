import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "../Call/callPeople.js" as People

/*
 * LoginView - ecran de connexion en Ligne claire.
 *
 *   [la une : marque, promesse, fonctions, etat du poste | feuille de connexion]
 *
 * Sous 1100 px, la une disparait et la feuille reste seule, centree.
 * Emet loginSucceeded(username) lorsque l'authentification reussit ; la
 * verification est faite par core::UserManager (userManager.login).
 *
 * Etats geres : connexion (nom memorise -> « Bon retour »), premier demarrage
 * (application.needsInitialAdmin -> createInitialAdmin), serveur inconnu
 * (ServerTrustSheet : code d'appairage puis approvePendingServerCertificate),
 * mode reseau (electionService.roleLabel, promoteToServer / demoteToClient).
 */
Item {
    id: root

    signal loginSucceeded(string username)

    property bool showPassword: false

    // « Se souvenir de moi » : nom memorise + jeton d'auto-login genere par
    // UserManager::rememberThisDevice() (seul son hash est en base).
    property bool rememberMe: false

    // Garde-fou : ne devient true que le temps d'un login() declenche depuis
    // CE formulaire. Cette instance reste vivante apres l'auto-login du
    // demarrage (Main.qml) ; sans ce garde-fou, ses Connections reagiraient
    // aussi a l'auto-login (meme signal C++), regenerant un jeton et
    // re-empilant un second ecran d'accueil.
    property bool manualLoginPending: false

    property string errorText: ""
    // Bascule a chaque nouvelle erreur : declenche la secousse des champs.
    property bool errorPulse: false

    property string rememberedName: ""
    readonly property string firstName: root.rememberedName.split(" ")[0]

    readonly property bool wide: root.width >= 1100
    readonly property bool hasPendingServer: typeof application !== "undefined" && application
                                             && !!application.pendingServerFingerprint && application.pendingServerFingerprint.length > 0
    readonly property bool needsInitialAdmin: typeof application !== "undefined" && application && !!application.needsInitialAdmin
    readonly property bool loginBusy: typeof userManager !== "undefined" && userManager && userManager.busy === true
    readonly property int pendingClients: typeof application !== "undefined" && application && application.pendingClientCount ? application.pendingClientCount : 0

    readonly property string machineName: (typeof settingsModel !== "undefined" && settingsModel && settingsModel.machineName) ? settingsModel.machineName : ""
    readonly property string roleLabel: (typeof electionService !== "undefined" && electionService) ? (electionService.roleLabel || "") : ""
    readonly property string activeServer: {
        const uuid = (typeof electionService !== "undefined" && electionService) ? (electionService.activeServerUuid || "") : ""
        if (!uuid.length) return ""
        const p = People.readPeers(typeof peersModel !== "undefined" ? peersModel : null)
        for (let i = 0; i < p.length; i++) if (p[i].id === uuid) return p[i].machine || ""
        return ""
    }
    readonly property string netLine: root.roleLabel === "SERVER" ? qsTr("Ce poste est le serveur")
                                      : root.roleLabel === "TEMP_SERVER" ? qsTr("Ce poste assure le secours")
                                      : root.activeServer.length ? qsTr("Relié au serveur %1").arg(root.activeServer)
                                      : root.roleLabel === "CLIENT" ? qsTr("Relié au serveur du réseau") : qsTr("Recherche du serveur…")
    readonly property string netGlyph: root.roleLabel === "TEMP_SERVER" ? "away" : root.roleLabel.length ? "online" : "watch"

    function attemptLogin() {
        if (root.loginBusy)
            return
        const username = userField.text.trim()
        const password = passField.text
        if (username.length === 0 || password.length === 0) {
            root.errorText = qsTr("Merci de renseigner un nom d'utilisateur et un mot de passe.")
            root.errorPulse = !root.errorPulse
            return
        }
        root.errorText = ""
        root.manualLoginPending = true
        userManager.login(username, password)
    }

    // Premier lancement du serveur principal : la personne qui installe
    // choisit le nom et le mot de passe du premier administrateur.
    property string setupError: ""
    function submitSetup() {
        const error = application.createInitialAdmin(setupName.text, setupPass.text, setupConfirm.text)
        root.setupError = error
        if (error.length === 0) {
            userField.text = setupName.text.trim()
            passField.text = ""
            Qt.callLater(function() { passField.input.forceActiveFocus() })
        }
    }

    // Pre-remplit le nom memorise et place le curseur au bon endroit.
    Component.onCompleted: {
        const remembered = (typeof settingsModel !== "undefined" && settingsModel) ? (settingsModel.rememberedUsername || "") : ""
        if (remembered.length > 0) {
            userField.text = remembered
            root.rememberedName = remembered
            root.rememberMe = true
            Qt.callLater(function() { passField.input.forceActiveFocus() })
        } else {
            Qt.callLater(function() { (root.needsInitialAdmin ? setupName : userField).input.forceActiveFocus() })
        }
    }

    // ======================================================================
    // Composants
    // ======================================================================
    // Champ de la feuille : libelle, aide a droite, filet (encre au focus,
    // rouge en erreur), oeil pour afficher le mot de passe.
    component LoginField: ColumnLayout {
        id: lf
        property string label: ""
        property string hint: ""
        property bool password: false
        property bool error: false
        property alias text: lfInput.text
        property alias input: lfInput
        property string placeholder: ""
        signal accepted()
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: lf.label; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
            Text { visible: lf.hint.length > 0; text: lf.hint; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 42
            radius: Theme.radiusSheet
            color: Theme.surface0
            border.width: lf.error || lfInput.activeFocus ? 1.5 : 1
            border.color: lf.error ? Theme.dangerColor : lfInput.activeFocus ? Theme.ink : Theme.lineStrong
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                spacing: 4
                TextField {
                    id: lfInput
                    Layout.fillWidth: true
                    echoMode: lf.password && !root.showPassword ? TextInput.Password : TextInput.Normal
                    placeholderText: lf.placeholder
                    placeholderTextColor: Theme.ink3
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                    background: Item {}
                    leftPadding: 0
                    rightPadding: 0
                    selectByMouse: true
                    Accessible.name: lf.label
                    onAccepted: lf.accepted()
                }
                AbstractButton {
                    visible: lf.password
                    implicitWidth: 30
                    implicitHeight: 30
                    focusPolicy: Qt.NoFocus
                    hoverEnabled: true
                    Accessible.name: root.showPassword ? qsTr("Masquer le mot de passe") : qsTr("Afficher le mot de passe")
                    ToolTip.visible: hovered
                    ToolTip.text: Accessible.name
                    ToolTip.delay: 500
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    background: Rectangle { radius: Theme.radiusSheet; color: parent.hovered ? Theme.selectWash : "transparent" }
                    contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.eye; size: 16; strokeWidth: 1.7; color: root.showPassword ? Theme.ink : Theme.ink3 } }
                    onClicked: root.showPassword = !root.showPassword
                }
            }
        }
    }

    // Case a cocher d'encre.
    component InkCheck: AbstractButton {
        id: ic
        property string detail: ""
        checkable: true
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Layout.fillWidth: true
        implicitHeight: icRow.implicitHeight + 4
        Accessible.role: Accessible.CheckBox
        Accessible.name: ic.text
        Accessible.checked: ic.checked
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Item {}
        contentItem: RowLayout {
            id: icRow
            spacing: 10
            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 1
                implicitWidth: 18; implicitHeight: 18; radius: 3
                color: ic.checked ? Theme.ink : "transparent"
                border.width: ic.checked ? 0 : (ic.visualFocus ? 2 : 1.5)
                border.color: ic.visualFocus ? Theme.focusRing : (ic.hovered ? Theme.ink : Theme.lineStrong)
                LineIcon { visible: ic.checked; anchors.centerIn: parent; path: Icons.check; size: 12; strokeWidth: 3; color: Theme.inkOnInk }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: ic.text; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); wrapMode: Text.WordWrap }
                Text { visible: ic.detail.length > 0; Layout.fillWidth: true; text: ic.detail; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap }
            }
        }
    }

    // Avis sous un formulaire (filet rouge, ou ambre pour une information).
    component Notice: Rectangle {
        property string text: ""
        property bool info: false
        Layout.fillWidth: true
        visible: text.length > 0
        implicitHeight: nRow.implicitHeight + 20
        color: Theme.surface0
        border.width: 1
        border.color: Theme.line
        Accessible.role: Accessible.AlertMessage
        Accessible.name: text
        Rectangle { width: 3; height: parent.height; color: parent.info ? Theme.warningColor : Theme.dangerColor }
        RowLayout {
            id: nRow
            x: 14; y: 10
            width: parent.width - 26
            spacing: 10
            LineIcon { Layout.alignment: Qt.AlignTop; Layout.topMargin: 1; path: Icons.alertTriangle; size: 16; strokeWidth: 1.8; color: parent.parent.info ? Theme.warningInk : Theme.dangerInk }
            Text { Layout.fillWidth: true; text: parent.parent.text; textFormat: Text.StyledText; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); wrapMode: Text.WordWrap }
        }
    }

    // Choix Papier / Nuit.
    component ThemeSeg: Rectangle {
        implicitWidth: segRow.implicitWidth + 2
        implicitHeight: 32
        radius: Theme.radiusSheet
        color: "transparent"
        border.width: 1
        border.color: Theme.lineStrong
        Row {
            id: segRow
            x: 1; y: 1
            Repeater {
                model: [{ mode: "light", label: qsTr("Papier") }, { mode: "dark", label: qsTr("Nuit") }]
                delegate: AbstractButton {
                    id: sb
                    required property var modelData
                    required property int index
                    readonly property bool on: (sb.modelData.mode === "dark") === Theme.darkMode
                    width: sbText.implicitWidth + 22
                    height: 30
                    hoverEnabled: true
                    Accessible.name: sb.modelData.label
                    Accessible.checked: sb.on
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    background: Rectangle {
                        color: sb.on ? Theme.ink : "transparent"
                        Rectangle { visible: sb.index > 0; width: 1; height: parent.height; color: Theme.lineStrong }
                    }
                    contentItem: Text { id: sbText; text: sb.modelData.label; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: sb.on ? Theme.inkOnInk : Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightSemibold }
                    onClicked: Theme.setMode(sb.modelData.mode)
                }
            }
        }
    }

    // Carte de role (fenetre « Mode reseau »).
    component RoleCard: AbstractButton {
        id: rc
        property string detail: ""
        property string iconPath: ""
        property bool current: false
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        implicitHeight: rcCol.implicitHeight + 26
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: rc.text + (rc.current ? ", " + qsTr("rôle actuel") : "")
        HoverHandler { cursorShape: rc.current ? Qt.ArrowCursor : Qt.PointingHandCursor }
        background: Rectangle {
            radius: Theme.radiusSheet
            color: rc.current ? Theme.surface0 : rc.hovered ? Theme.selectWash : "transparent"
            border.width: rc.current || rc.visualFocus ? 2 : 1
            border.color: rc.visualFocus ? Theme.focusRing : rc.current ? Theme.ink : (rc.hovered ? Theme.ink : Theme.lineStrong)
        }
        contentItem: Item {
            ColumnLayout {
                id: rcCol
                x: 14; y: 13
                width: parent.width - 28
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    LineIcon { path: rc.iconPath; size: 16; strokeWidth: 1.7; color: Theme.ink }
                    Text { Layout.fillWidth: true; text: rc.text; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold }
                    Rectangle {
                        visible: rc.current
                        implicitWidth: nowText.implicitWidth + 10; implicitHeight: 16; radius: 2
                        color: Theme.ink
                        Text { id: nowText; anchors.centerIn: parent; text: qsTr("ACTUEL"); color: Theme.inkOnInk; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9.5); font.weight: Theme.weightBold; font.letterSpacing: 1 }
                    }
                }
                Text { Layout.fillWidth: true; text: rc.detail; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); lineHeight: 1.12; wrapMode: Text.WordWrap }
            }
        }
    }

    // ======================================================================
    // Page
    // ======================================================================
    Rectangle { anchors.fill: parent; color: Theme.bg }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- La une ----------------------------------------------------------
        Item {
            id: une
            visible: root.wide
            Layout.fillHeight: true
            Layout.preferredWidth: Math.round(root.width * 0.51)
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.ruleInk }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: root.width > 1400 ? 64 : 48
                anchors.rightMargin: root.width > 1400 ? 64 : 48
                anchors.topMargin: 52
                anchors.bottomMargin: 36
                spacing: 0

                RowLayout {
                    spacing: 12
                    BrandMark { size: 42 }
                    Text { text: "LocaLink"; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(24); font.weight: Theme.weightBold }
                }
                Item { Layout.fillHeight: true; Layout.minimumHeight: 20 }
                CapsLabel { text: root.machineName.length ? qsTr("Réseau local · %1").arg(root.machineName) : qsTr("Réseau local") }
                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: font.pixelSize * 8.6
                    Layout.topMargin: 12
                    textFormat: Text.StyledText
                    wrapMode: Text.WordWrap
                    text: qsTr("La collaboration de votre équipe, <b>sur votre réseau local.</b>")
                    color: Theme.ink
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: root.height < 760 ? Theme.fs(38) : Theme.fs(46)
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(font.pixelSize * 1.08)
                    Accessible.role: Accessible.Heading
                }
                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 470
                    Layout.topMargin: 16
                    wrapMode: Text.WordWrap
                    text: qsTr("Aucune dépendance à Internet : messages, fichiers et appels restent entre les postes de votre réseau.")
                    color: Theme.ink2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(15)
                    lineHeight: 1.2
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    Layout.topMargin: 26
                    spacing: 0
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 2; color: Theme.ruleInk }
                    Repeater {
                        model: [
                            { icon: Icons.link, label: qsTr("Les postes du réseau se trouvent tout seuls") },
                            { icon: Icons.messageCircle, label: qsTr("Discussions à deux ou en groupe") },
                            { icon: Icons.exchange, label: qsTr("Fichiers, dossiers et dossiers partagés") },
                            { icon: Icons.phoneLine, label: qsTr("Appels vocaux de poste à poste") }
                        ]
                        delegate: Item {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: root.height < 760 ? 46 : 52
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                            RowLayout {
                                anchors.fill: parent
                                spacing: 12
                                Text { Layout.preferredWidth: 26; text: String(index + 1).padStart(2, "0"); color: Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightBold }
                                Rectangle {
                                    implicitWidth: 30; implicitHeight: 30; radius: 15
                                    color: "transparent"; border.width: 1; border.color: Theme.lineStrong
                                    LineIcon { anchors.centerIn: parent; path: modelData.icon; size: 14; strokeWidth: 1.7; color: Theme.ink2 }
                                }
                                Text { Layout.fillWidth: true; text: modelData.label; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(14); elide: Text.ElideRight }
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true; Layout.minimumHeight: 20 }
                Flow {
                    Layout.fillWidth: true
                    spacing: 22
                    Row {
                        spacing: 7
                        StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: root.netGlyph; size: 10 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.netLine; color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
                    }
                    Row {
                        spacing: 7
                        LineIcon { anchors.verticalCenter: parent.verticalCenter; path: Icons.lock; size: 14; strokeWidth: 1.7; color: Theme.ink3 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Connexions chiffrées entre les postes autorisés"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5) }
                    }
                }
            }
        }

        // ---- Feuille de connexion ---------------------------------------------
        Flickable {
            id: sideScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: Math.max(height, sheetCol.implicitHeight + 120)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: sheetCol
                width: Math.min(420, sideScroll.width - 64)
                x: (sideScroll.width - width) / 2
                y: Math.max(76, (sideScroll.contentHeight - implicitHeight) / 2)
                spacing: 0

                // Marque quand la une est repliee.
                RowLayout {
                    visible: !root.wide
                    Layout.bottomMargin: 22
                    spacing: 10
                    BrandMark { size: 32 }
                    Text { text: "LocaLink"; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(20); font.weight: Theme.weightBold }
                }

                // ======== Premier demarrage ========
                ColumnLayout {
                    visible: root.needsInitialAdmin
                    Layout.fillWidth: true
                    spacing: 0
                    CapsLabel { text: qsTr("Premier démarrage") }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        text: qsTr("Créer le compte <b>administrateur</b>")
                        color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(34); lineHeight: 1.05
                        Accessible.role: Accessible.Heading
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        wrapMode: Text.WordWrap
                        text: qsTr("Aucun compte n'existe encore sur ce serveur. Choisissez l'identifiant et le mot de passe du premier administrateur du réseau.")
                        color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(14); lineHeight: 1.15
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 22; Layout.preferredHeight: 2; color: Theme.ruleInk }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 18
                        spacing: 14
                        LoginField { id: setupName; label: qsTr("Nom d'utilisateur"); onAccepted: setupPass.input.forceActiveFocus() }
                        LoginField { id: setupPass; label: qsTr("Mot de passe"); hint: qsTr("8 caractères au moins"); password: true; error: root.setupError.length > 0; onAccepted: setupConfirm.input.forceActiveFocus() }
                        LoginField { id: setupConfirm; label: qsTr("Confirmer le mot de passe"); password: true; error: root.setupError.length > 0; onAccepted: root.submitSetup() }
                        Notice { text: root.setupError }
                        AppButton { Layout.fillWidth: true; variant: "ink"; size: "large"; iconPath: Icons.shield; text: qsTr("Créer le compte administrateur"); onClicked: root.submitSetup() }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 18; Layout.preferredHeight: 1; color: Theme.line }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        wrapMode: Text.WordWrap
                        text: qsTr("Ce compte pourra ensuite autoriser les postes du réseau et créer les comptes des autres personnes.")
                        color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5)
                    }
                }

                // ======== Connexion ========
                ColumnLayout {
                    visible: !root.needsInitialAdmin
                    Layout.fillWidth: true
                    spacing: 0
                    CapsLabel { text: qsTr("Connexion") }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        text: root.rememberedName.length ? qsTr("Bon retour, <b>%1.</b>").arg(root.firstName.replace(/&/g, "&amp;").replace(/</g, "&lt;")) : qsTr("Bonjour.")
                        color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(34); lineHeight: 1.05
                        Accessible.role: Accessible.Heading
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        wrapMode: Text.WordWrap
                        text: root.rememberedName.length ? qsTr("Saisissez votre mot de passe pour ouvrir votre session sur ce poste.")
                                                        : qsTr("Connectez-vous avec votre compte LocaLink.")
                        color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(14); lineHeight: 1.15
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 22; Layout.preferredHeight: 2; color: Theme.ruleInk }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 18
                        spacing: 14
                        LoginField {
                            id: userField
                            label: qsTr("Nom d'utilisateur")
                            placeholder: qsTr("Votre nom d'utilisateur")
                            error: root.errorText.length > 0
                            onAccepted: passField.input.forceActiveFocus()
                        }
                        LoginField {
                            id: passField
                            label: qsTr("Mot de passe")
                            placeholder: qsTr("Votre mot de passe")
                            password: true
                            error: root.errorText.length > 0
                            onAccepted: root.attemptLogin()
                        }
                        InkCheck {
                            text: qsTr("Se souvenir de moi sur ce poste")
                            detail: qsTr("La session s'ouvre toute seule au prochain démarrage.")
                            checked: root.rememberMe
                            onToggled: root.rememberMe = checked
                        }
                        Notice { text: root.errorText }
                        AppButton {
                            Layout.fillWidth: true
                            variant: "ink"
                            size: "large"
                            text: root.loginBusy ? qsTr("Connexion…") : qsTr("Se connecter")
                            loading: root.loginBusy
                            enabled: !root.loginBusy
                            onClicked: root.attemptLogin()
                        }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 18; Layout.preferredHeight: 1; color: Theme.line }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        text: qsTr("Mot de passe oublié ? <b>Un administrateur</b> peut le réinitialiser depuis Administration › Comptes.")
                        color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5)
                    }
                }

                // Etat du poste quand la une est repliee.
                Rectangle {
                    visible: !root.wide
                    Layout.topMargin: 20
                    implicitWidth: pillRow.implicitWidth + 24
                    implicitHeight: 28
                    radius: 14
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.lineStrong
                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 7
                        StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: root.netGlyph; size: 10 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.netLine; color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightSemibold }
                    }
                }
            }
        }
    }

    // ---- Barre d'outils ------------------------------------------------------------
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 18
        anchors.rightMargin: 24
        spacing: 8
        z: 10
        // Accessible sans session : faire confiance au certificat d'un serveur
        // est une decision locale de connexion, pas une action d'administration.
        AppButton {
            visible: root.hasPendingServer
            variant: "soft"
            size: "small"
            iconPath: Icons.lock
            text: qsTr("Serveur à approuver")
            tooltip: qsTr("Vérifier le certificat du serveur détecté")
            onClicked: root.sheet = "server"
        }
        AppButton {
            variant: "ghost"
            size: "small"
            iconPath: Icons.server
            text: qsTr("Mode réseau")
            tooltip: qsTr("Rôle de ce poste sur le réseau local")
            onClicked: root.sheet = "network"
        }
        ThemeSeg {}
    }

    // ======================================================================
    // Fenetres
    // ======================================================================
    property string sheet: ""                  // "" | server | network | promote | demote

    Connections {
        target: (typeof application !== "undefined") ? application : null
        ignoreUnknownSignals: true
        function onPendingServerChanged() {
            if (application.pendingServerFingerprint.length > 0
                    && application.pendingServerFingerprint !== root.dismissedServer)
                root.sheet = "server"
        }
    }

    // Serveur inconnu : code d'appairage a comparer avec celui de l'administrateur.
    ServerTrustSheet {
        open: root.sheet === "server"
        onCloseRequested: { root.dismissedServer = application.pendingServerFingerprint; root.sheet = "" }
        onApproved: root.sheet = ""
    }
    // Serveur ecarte : pas de nouvelle ouverture automatique a chaque tentative de
    // connexion (le bouton de la barre du bas reste disponible).
    property string dismissedServer: ""

    SheetModal {
        open: root.sheet === "network"
        kicker: qsTr("Mode réseau")
        title: qsTr("Rôle de ce poste")
        sheetWidth: 540
        onCloseRequested: root.sheet = ""

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Un seul poste est serveur sur le réseau local ; les autres s'y relient. Si le serveur ne répond plus, un poste prend le relais en secours.")
                color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); lineHeight: 1.12
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                RoleCard {
                    text: qsTr("Serveur")
                    iconPath: Icons.server
                    detail: qsTr("Accepte les connexions des autres postes et garde le registre du réseau.")
                    current: root.roleLabel === "SERVER"
                    onClicked: if (!current) root.sheet = "promote"
                }
                RoleCard {
                    text: qsTr("Client")
                    iconPath: Icons.monitor
                    detail: qsTr("Se relie au serveur détecté sur le réseau.")
                    current: root.roleLabel === "CLIENT"
                    onClicked: if (!current) root.sheet = "demote"
                }
            }
            Notice { info: true; text: root.roleLabel === "TEMP_SERVER" ? qsTr("Ce poste assure le <b>secours</b> en attendant le retour du serveur officiel.") : "" }
            Notice {
                info: true
                text: root.pendingClients > 0
                      ? (root.pendingClients > 1 ? qsTr("<b>%1 postes attendent</b> une autorisation. Connectez-vous avec un compte administrateur pour les examiner.").arg(root.pendingClients)
                                                 : qsTr("<b>1 poste attend</b> une autorisation. Connectez-vous avec un compte administrateur pour l'examiner."))
                      : ""
            }
        }
        footer: [ AppButton { variant: "ink"; text: qsTr("Fermer"); onClicked: root.sheet = "" } ]
    }

    SheetModal {
        open: root.sheet === "promote" || root.sheet === "demote"
        kicker: qsTr("Mode réseau")
        title: root.sheet === "promote" ? qsTr("Faire de ce poste <b>le serveur</b> ?") : qsTr("Repasser ce poste <b>en client</b> ?")
        boldTitle: false
        sheetWidth: 500
        onCloseRequested: root.sheet = "network"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            Text {
                visible: root.sheet === "promote"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Les autres postes du réseau se connecteront à cette machine.")
                color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
            }
            Notice { info: true; text: root.sheet === "promote" ? qsTr("Un seul poste devrait être serveur sur le réseau local.") : "" }
            Rectangle {
                visible: root.sheet === "demote"
                Layout.fillWidth: true
                implicitHeight: dRow.implicitHeight + 24
                color: Theme.dangerSoft
                Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
                RowLayout {
                    id: dRow
                    x: 14; y: 12
                    width: parent.width - 28
                    spacing: 12
                    LineIcon { Layout.alignment: Qt.AlignTop; path: Icons.alertTriangle; size: 18; strokeWidth: 1.8; color: Theme.dangerInk }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { Layout.fillWidth: true; text: qsTr("Ce poste cessera d'accepter les connexions."); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); wrapMode: Text.WordWrap }
                        Text { Layout.fillWidth: true; text: qsTr("Il se reliera au serveur détecté sur le réseau."); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WordWrap }
                    }
                }
            }
        }
        footer: [
            AppButton { variant: "ghost"; text: qsTr("Retour"); onClicked: root.sheet = "network" },
            AppButton {
                variant: root.sheet === "promote" ? "ink" : "danger"
                iconPath: root.sheet === "promote" ? Icons.server : ""
                text: root.sheet === "promote" ? qsTr("Passer en serveur") : qsTr("Passer en client")
                onClicked: {
                    if (root.sheet === "promote") application.promoteToServer()
                    else application.demoteToClient()
                    root.sheet = ""
                }
            }
        ]
    }

    // ---- Secousse des champs a chaque erreur ---------------------------------------------
    SequentialAnimation {
        id: shake
        property real base: 0
        NumberAnimation { target: sheetCol; property: "x"; to: shake.base - 8; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: sheetCol; property: "x"; to: shake.base + 8; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: sheetCol; property: "x"; to: shake.base - 4; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: sheetCol; property: "x"; to: shake.base; duration: 55; easing.type: Easing.InQuad }
        onFinished: sheetCol.x = Qt.binding(function() { return (sideScroll.width - sheetCol.width) / 2 })
    }
    onErrorPulseChanged: { shake.base = (sideScroll.width - sheetCol.width) / 2; shake.start() }

    // Resultat de l'authentification reelle emis par UserManager.
    Connections {
        target: (typeof userManager !== "undefined") ? userManager : null
        ignoreUnknownSignals: true

        function onLoginSucceeded(username) {
            // Ignore l'auto-login silencieux de Main.qml (voir manualLoginPending).
            if (!root.manualLoginPending)
                return
            root.manualLoginPending = false
            root.errorText = ""
            passField.text = ""

            if (typeof settingsModel !== "undefined" && settingsModel) {
                if (root.rememberMe) {
                    // Nouveau jeton d'auto-login : la base ne recoit que son hash.
                    const token = userManager.rememberThisDevice()
                    settingsModel.rememberedUsername = username
                    settingsModel.rememberedSessionToken = token
                } else {
                    // Case decochee : invalide un jeton laisse par une session precedente.
                    if (settingsModel.rememberedSessionToken.length > 0)
                        userManager.forgetRememberedToken(settingsModel.rememberedSessionToken)
                    settingsModel.rememberedUsername = ""
                    settingsModel.rememberedSessionToken = ""
                }
                settingsModel.save()
            }
            root.loginSucceeded(username)
        }

        function onLoginFailed(reason) {
            root.manualLoginPending = false
            root.errorText = reason
            root.errorPulse = !root.errorPulse
        }
    }
}
