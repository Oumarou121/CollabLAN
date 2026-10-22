import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * AccountSettings - Parametres > Compte (Ligne claire).
 *
 *   - Votre compte : identite et role ; « Changer le mot de passe… »
 *     ouvre la fenetre de l'ecran hote (passwordRequested).
 *   - Sur ce poste : connexion automatique (jeton « Se souvenir de moi »
 *     de settingsModel, jamais en base) ; « Oublier ce poste » l'invalide
 *     (UserManager::forgetRememberedToken) comme le fait la connexion quand
 *     la case est decochee. Se deconnecter seul garde ce jeton : on serait
 *     reconnecte au demarrage suivant, d'ou « Se déconnecter et oublier ce
 *     poste ».
 */
ColumnLayout {
    id: root
    spacing: 0

    property bool passwordChanged: false     // affiche « Mot de passe modifié » sur la ligne
    signal passwordRequested()
    signal logoutRequested()

    readonly property var settings: (typeof settingsModel !== "undefined") ? settingsModel : null
    readonly property var users: (typeof userManager !== "undefined") ? userManager : null
    readonly property bool isAdmin: !!root.users && root.users.currentUserIsAdmin
    readonly property string userName: root.users && root.users.currentUsername ? root.users.currentUsername : ""
    readonly property bool hasSession: !!root.settings && root.settings.rememberedSessionToken.length > 0
    property bool confirmForget: false

    function initials(n) {
        return String(n).split(/[\s-]+/).filter(function(w) { return w.length > 0 }).map(function(w) { return w[0] }).join("").slice(0, 2).toUpperCase()
    }
    function forgetDevice() {
        if (!root.settings) return
        if (root.users && root.settings.rememberedSessionToken.length > 0)
            root.users.forgetRememberedToken(root.settings.rememberedSessionToken)
        root.settings.rememberedUsername = ""
        root.settings.rememberedSessionToken = ""
        root.settings.save()
        root.confirmForget = false
    }

    // ---- Votre compte --------------------------------------------------------------
    SettingGroup {
        first: true
        title: qsTr("Votre compte")
        scopeIcon: Icons.users
        scopeText: qsTr("Votre compte, <b>sur tous les postes</b>")

        SettingRow {
            label: qsTr("Compte")
            help: qsTr("Le même compte sur tous les postes du réseau.")
            RowLayout {
                Layout.alignment: Qt.AlignLeft
                spacing: 14
                Rectangle {
                    implicitWidth: 44; implicitHeight: 44; radius: 22
                    color: root.isAdmin ? Theme.ink : "transparent"
                    border.width: root.isAdmin ? 0 : 1
                    border.color: Theme.lineStrong
                    Text {
                        anchors.centerIn: parent
                        text: root.initials(root.userName)
                        color: root.isAdmin ? Theme.inkOnInk : Theme.ink
                        font.family: Theme.fontFamilySerif
                        font.pixelSize: Theme.fs(15)
                        font.weight: Theme.weightBold
                    }
                    Rectangle {
                        visible: root.isAdmin
                        x: parent.width - width + 3; y: parent.height - height + 3
                        width: 19; height: 19; radius: 9.5
                        color: Theme.bg
                        border.width: 1
                        border.color: Theme.line
                        LineIcon { anchors.centerIn: parent; path: Icons.shield; size: 12; strokeWidth: 2; color: Theme.ink }
                    }
                }
                ColumnLayout {
                    spacing: 2
                    Text { text: root.userName; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(18); font.weight: Theme.weightBold }
                    Row {
                        spacing: 6
                        LineIcon { visible: root.isAdmin; anchors.verticalCenter: parent.verticalCenter; path: Icons.shield; size: 13; strokeWidth: 1.8; color: Theme.ink3 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.isAdmin ? qsTr("Administrateur") : qsTr("Utilisateur"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5) }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.isAdmin ? qsTr("Administrateur : vous autorisez les machines, gérez les comptes et lisez le journal d'audit.")
                                   : qsTr("Utilisateur : vous échangez, partagez et appelez. Un administrateur gère les comptes.")
                wrapMode: Text.WordWrap
                color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12)
            }
        }
        SettingRow {
            label: qsTr("Mot de passe")
            help: qsTr("4 caractères au moins, différent de l'actuel. En cas d'oubli, un administrateur peut le réinitialiser.")
            Flow {
                Layout.fillWidth: true
                spacing: 16
                Text {
                    height: 30
                    verticalAlignment: Text.AlignVCenter
                    text: "••••••••"
                    color: Theme.ink2
                    font.pixelSize: Theme.fs(18)
                    font.letterSpacing: 3
                }
                AppButton { variant: "line"; size: "small"; iconPath: Icons.key; text: qsTr("Changer le mot de passe…"); onClicked: root.passwordRequested() }
                SavedNote { visible: root.passwordChanged; height: 30; text: qsTr("Mot de passe modifié") }
            }
        }
    }

    // ---- Sur ce poste --------------------------------------------------------------
    SettingGroup {
        title: qsTr("Sur ce poste")
        scopeIcon: Icons.monitor
        scopeText: qsTr("<b>Ce poste</b> · immédiat")

        SettingRow {
            label: qsTr("Connexion automatique")
            help: qsTr("Retenue sur ce poste seulement, jamais sur le réseau.")
            Row {
                Layout.alignment: Qt.AlignLeft
                spacing: 7
                StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: root.hasSession ? "ok" : "offline"; size: 12 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: !root.hasSession ? qsTr("Désactivée")
                          : root.confirmForget ? qsTr("Activée")
                          : qsTr("Activée : LocaLink vous connecte au démarrage, sans mot de passe.")
                    color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                }
            }
            Text {
                visible: !root.hasSession
                Layout.fillWidth: true
                text: qsTr("Cochez « Se souvenir de moi » à votre prochaine connexion pour l'activer.")
                wrapMode: Text.WordWrap
                color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12)
            }
            AppButton {
                visible: root.hasSession && !root.confirmForget
                Layout.alignment: Qt.AlignLeft
                variant: "line"; size: "small"; text: qsTr("Oublier ce poste…")
                onClicked: root.confirmForget = true
            }
            // Confirmation dans la ligne
            Rectangle {
                visible: root.hasSession && root.confirmForget
                Layout.fillWidth: true
                Layout.maximumWidth: 620
                implicitHeight: forgetFlow.implicitHeight + 20
                color: Theme.dangerSoft
                Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
                Flow {
                    id: forgetFlow
                    x: 12; y: 10
                    width: parent.width - 24
                    spacing: 10
                    Text {
                        width: Math.min(implicitWidth, forgetFlow.width - 230 > 200 ? forgetFlow.width - 230 : forgetFlow.width)
                        height: Math.max(implicitHeight, 30)
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        text: qsTr("Au prochain démarrage, LocaLink vous demandera votre mot de passe sur ce poste.")
                        color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5)
                    }
                    AppButton { variant: "ghost"; size: "small"; text: qsTr("Annuler"); onClicked: root.confirmForget = false }
                    AppButton { variant: "danger"; size: "small"; text: qsTr("Oublier ce poste"); onClicked: root.forgetDevice() }
                }
            }
        }
        SettingRow {
            label: qsTr("Session")
            help: root.hasSession ? qsTr("La connexion automatique reste active après une déconnexion : vous serez reconnecté au prochain démarrage.")
                                  : qsTr("Vous revenez à l'écran de connexion.")
            Flow {
                Layout.fillWidth: true
                spacing: 8
                AppButton { variant: "line"; size: "small"; iconPath: Icons.logout; text: qsTr("Se déconnecter"); onClicked: root.logoutRequested() }
                AppButton {
                    visible: root.hasSession
                    variant: "ghost"; size: "small"; text: qsTr("Se déconnecter et oublier ce poste")
                    onClicked: { root.forgetDevice(); root.logoutRequested() }
                }
            }
        }
    }
}
