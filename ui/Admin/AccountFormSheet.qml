import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * AccountFormSheet - fenetres de compte en Ligne claire :
 *   mode "new"   : nom, mot de passe (deux fois), role explique ;
 *                  userManagementModel.createUser(nom, mot de passe, admin)
 *   mode "reset" : nouveau mot de passe (deux fois) pour `userName` ;
 *                  userManagementModel.resetPassword(id, mot de passe)
 * Le minimum de 4 caracteres est celui d'UserManager (kMinPasswordLength).
 */
SheetModal {
    id: root

    property string mode: "new"
    property var userId: -1
    property string userName: ""
    property bool isSelf: false
    property bool makeAdmin: false
    property string errorText: ""
    readonly property int minLength: 4

    signal done(string message)

    kicker: root.mode === "new" ? qsTr("Nouveau compte") : qsTr("Mot de passe")
    title: root.mode === "new" ? qsTr("Créer un compte") : qsTr("Nouveau mot de passe pour <b>%1</b>").arg(root.userName.replace(/&/g, "&amp;").replace(/</g, "&lt;"))
    boldTitle: root.mode === "new"
    sheetWidth: 500
    onCloseRequested: root.open = false
    onOpenChanged: {
        if (!open) return
        nameField.text = ""; passField.text = ""; confirmField.text = ""
        root.makeAdmin = false
        root.errorText = ""
        Qt.callLater(function() { (root.mode === "new" ? nameField : passField).field.forceActiveFocus() })
    }

    readonly property bool mismatch: confirmField.text.length > 0 && confirmField.text !== passField.text
    readonly property bool valid: passField.text.length >= root.minLength && passField.text === confirmField.text
                                  && (root.mode !== "new" || nameField.text.trim().length > 0)

    function submit() {
        if (!root.valid || typeof userManagementModel === "undefined" || !userManagementModel) return
        if (root.mode === "new") {
            const name = nameField.text.trim()
            if (userManagementModel.createUser(name, passField.text, root.makeAdmin)) {
                root.open = false
                root.done(qsTr("Compte « %1 » créé.").arg(name))
            } else {
                root.errorText = qsTr("Le compte n'a pas été créé. Vérifiez que ce nom n'est pas déjà utilisé.")
            }
        } else {
            if (userManagementModel.resetPassword(root.userId, passField.text)) {
                root.open = false
                root.done(qsTr("Mot de passe de %1 réinitialisé.").arg(root.userName))
            } else {
                root.errorText = qsTr("Le mot de passe n'a pas été modifié. Réessayez.")
            }
        }
    }

    component RoleCard: AbstractButton {
        id: rc
        property string detail: ""
        property string iconPath: ""
        property bool current: false
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: rcCol.implicitHeight + 22
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.role: Accessible.RadioButton
        Accessible.checked: rc.current
        Accessible.name: rc.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            radius: Theme.radiusSheet
            color: rc.current ? Theme.surface0 : rc.hovered ? Theme.selectWash : "transparent"
            border.width: rc.current || rc.visualFocus ? 2 : 1
            border.color: rc.visualFocus ? Theme.focusRing : rc.current ? Theme.ink : Theme.lineStrong
        }
        contentItem: Item {
            ColumnLayout {
                id: rcCol
                x: 12; y: 11
                width: parent.width - 24
                spacing: 3
                Row {
                    spacing: 7
                    LineIcon { visible: rc.iconPath.length > 0; anchors.verticalCenter: parent.verticalCenter; path: rc.iconPath; size: 14; strokeWidth: 1.8; color: Theme.ink }
                    Text { text: rc.text; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold }
                }
                Text { Layout.fillWidth: true; text: rc.detail; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12

        Text {
            visible: root.mode === "reset"
            Layout.fillWidth: true
            text: qsTr("L'ancien mot de passe ne peut pas être affiché.")
                  + (root.isSelf ? "" : " " + qsTr("%1 devra utiliser le nouveau à sa prochaine connexion.").arg(root.userName))
            color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); wrapMode: Text.WordWrap
        }
        SheetField {
            id: nameField
            visible: root.mode === "new"
            label: qsTr("Nom d'utilisateur")
            placeholderText: qsTr("Prénom Nom")
            onAccepted: passField.field.forceActiveFocus()
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            SheetField {
                id: passField
                Layout.preferredWidth: 1
                label: root.mode === "new" ? qsTr("Mot de passe") : qsTr("Nouveau mot de passe")
                password: true
                onAccepted: confirmField.field.forceActiveFocus()
            }
            SheetField {
                id: confirmField
                Layout.preferredWidth: 1
                label: qsTr("Confirmer")
                password: true
                error: root.mismatch ? qsTr("Les deux mots de passe ne correspondent pas.") : ""
                onAccepted: root.submit()
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.topMargin: -4
            text: root.mode === "new"
                  ? qsTr("%1 caractères au moins. Communiquez-le à la personne : elle pourra le changer ensuite.").arg(root.minLength)
                  : qsTr("%1 caractères au moins.").arg(root.minLength)
            color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
        }
        Text { visible: root.mode === "new"; text: qsTr("Rôle"); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
        RowLayout {
            visible: root.mode === "new"
            Layout.fillWidth: true
            spacing: 8
            RoleCard { text: qsTr("Utilisateur"); detail: qsTr("Échange, partage et appelle."); current: !root.makeAdmin; onClicked: root.makeAdmin = false }
            RoleCard { text: qsTr("Administrateur"); iconPath: Icons.shield; detail: qsTr("Autorise les machines, gère les comptes, lit le journal."); current: root.makeAdmin; onClicked: root.makeAdmin = true }
        }
        Text {
            visible: root.errorText.length > 0
            Layout.fillWidth: true
            text: root.errorText
            color: Theme.dangerInk; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold; wrapMode: Text.WordWrap
        }
    }

    footer: [
        AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.open = false },
        AppButton {
            variant: "ink"
            iconPath: root.mode === "new" ? Icons.userPlus : Icons.lock
            text: root.mode === "new" ? qsTr("Créer le compte") : qsTr("Réinitialiser")
            enabled: root.valid
            onClicked: root.submit()
        }
    ]
}
