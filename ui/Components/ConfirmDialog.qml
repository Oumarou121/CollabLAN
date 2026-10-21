import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * ConfirmDialog - confirmation standard des actions sensibles ou
 * irreversibles (revoquer une machine, supprimer un compte, retirer un
 * acces...).
 *
 *   ConfirmDialog {
 *       id: revokeConfirm
 *       title: qsTr("Révoquer PC-COMPTA-01 ?")
 *       message: qsTr("Ce poste ne pourra plus échanger avec le réseau.")
 *       confirmText: qsTr("Révoquer")
 *       destructive: true
 *       onConfirmed: authorizedMachineModel.revokeMachine(id, ...)
 *   }
 *
 * Le bouton par defaut au clavier est "Annuler" : une validation par
 * Entree ne declenche jamais l'action destructrice par megarde.
 */
AppDialog {
    id: root

    property string message: ""
    property string detail: ""
    property string confirmText: qsTr("Confirmer")
    property string cancelText: qsTr("Annuler")
    property bool destructive: false

    signal confirmed()

    dialogWidth: 440
    headerIcon: root.destructive ? "" : ""
    headerTone: root.destructive ? "danger" : "accent"

    onOpened: cancelButton.forceActiveFocus()

    ColumnLayout {
        width: parent ? parent.width : 0
        spacing: 14

        Text {
            Layout.fillWidth: true
            text: root.message
            color: Theme.ink2
            font.pixelSize: Theme.fs(14)
            font.family: Theme.fontFamily
            wrapMode: Text.WordWrap
        }

        Rectangle {
            visible: root.detail.length > 0
            Layout.fillWidth: true
            implicitHeight: detailText.implicitHeight + 16
            radius: Theme.radiusControl
            color: Theme.surface1
            border.width: 1
            border.color: Theme.line

            Text {
                id: detailText
                anchors.fill: parent
                anchors.margins: 8
                text: root.detail
                color: Theme.ink2
                font.pixelSize: Theme.fs(12)
                font.family: Theme.fontFamily
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            Item { Layout.fillWidth: true }

            AppButton {
                id: cancelButton
                text: root.cancelText
                variant: "secondary"
                onClicked: root.close()
            }
            AppButton {
                text: root.confirmText
                variant: root.destructive ? "danger" : "primary"
                onClicked: {
                    root.close()
                    root.confirmed()
                }
            }
        }
    }
}
