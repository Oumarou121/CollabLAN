import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Admin"
import "../Components/icons.js" as Icons

/*
 * PasswordSheet - fenetre « Changer votre mot de passe ». Toutes les regles
 * sont verifiees par UserManager::changeOwnPassword, qui renvoie le message
 * a afficher (ou "" en cas de succes) ; le message est place sous le champ
 * qu'il concerne.
 */
SheetModal {
    id: root

    property bool done: false
    property string error: ""
    signal changed()

    readonly property string errorField: {
        const e = root.error.toLowerCase()
        if (!e.length) return ""
        if (e.indexOf("actuel") >= 0) return "current"
        if (e.indexOf("correspondent") >= 0) return "confirm"
        if (e.indexOf("au moins") >= 0 || e.indexOf("différent") >= 0) return "new"
        return "form"
    }
    readonly property bool filled: currentField.text.length > 0 && newField.text.length > 0 && confirmField.text.length > 0

    function reset() {
        currentField.text = ""; newField.text = ""; confirmField.text = ""
        root.error = ""; root.done = false
    }
    function submit() {
        if (!root.filled || typeof userManager === "undefined" || !userManager) return
        const msg = userManager.changeOwnPassword(currentField.text, newField.text, confirmField.text)
        if (msg === "") {
            root.done = true
            currentField.text = ""; newField.text = ""; confirmField.text = ""
            root.changed()
        } else {
            root.error = msg
        }
    }
    onOpenChanged: if (open) { root.reset(); currentField.field.forceActiveFocus() }

    kicker: qsTr("Votre compte")
    title: root.done ? qsTr("Mot de passe modifié") : qsTr("Changer votre mot de passe")
    sheetWidth: 480

    ColumnLayout {
        visible: !root.done
        Layout.fillWidth: true
        spacing: 12
        SheetField {
            id: currentField
            label: qsTr("Mot de passe actuel")
            password: true
            error: root.errorField === "current" ? root.error : ""
            onTextChanged: if (text.length) root.error = ""
            onAccepted: newField.field.forceActiveFocus()
        }
        SheetField {
            id: newField
            label: qsTr("Nouveau mot de passe")
            password: true
            error: root.errorField === "new" ? root.error : ""
            onTextChanged: if (text.length) root.error = ""
            onAccepted: confirmField.field.forceActiveFocus()
        }
        SheetField {
            id: confirmField
            label: qsTr("Confirmer le nouveau mot de passe")
            password: true
            error: root.errorField === "confirm" ? root.error : ""
            hint: root.errorField === "form" ? "" : qsTr("4 caractères au moins, différent de l'actuel.")
            onTextChanged: if (text.length) root.error = ""
            onAccepted: root.submit()
        }
        Text {
            visible: root.errorField === "form"
            Layout.fillWidth: true
            text: root.error
            wrapMode: Text.WordWrap
            color: Theme.dangerInk; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightSemibold
        }
    }

    Rectangle {
        visible: root.done
        Layout.fillWidth: true
        implicitHeight: okRow.implicitHeight + 22
        color: Theme.surface0
        border.width: 1
        border.color: Theme.line
        Rectangle { width: 2; height: parent.height; color: Theme.successColor }
        RowLayout {
            id: okRow
            x: 14; y: 11
            width: parent.width - 28
            spacing: 10
            LineIcon { Layout.alignment: Qt.AlignTop; path: Icons.checkCircle; size: 16; strokeWidth: 1.8; color: Theme.successInk }
            Text {
                Layout.fillWidth: true
                text: qsTr("Le nouveau mot de passe vous sera demandé à la prochaine connexion, sur tous les postes.")
                wrapMode: Text.WordWrap
                color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
            }
        }
    }

    footer: [
        AppButton { visible: !root.done; variant: "ghost"; text: qsTr("Annuler"); onClicked: root.closeRequested() },
        AppButton { visible: !root.done; variant: "ink"; iconPath: Icons.key; enabled: root.filled; text: qsTr("Changer le mot de passe"); onClicked: root.submit() },
        AppButton { visible: root.done; variant: "ink"; text: qsTr("Fermer"); onClicked: root.closeRequested() }
    ]
}
