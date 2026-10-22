import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Admin"
import "../Components/icons.js" as Icons

/*
 * ServerTrustSheet - « Serveur détecté » : ce poste ne connait pas encore le
 * serveur qui se presente. Affiche le code d'appairage (le meme que celui que
 * l'administrateur voit pour ce poste dans Administration > Machines), et
 * l'empreinte complete sur demande. Utilisee par l'ecran de connexion et par
 * l'application deja connectee (un serveur inconnu peut se presenter a tout
 * moment : serveur de secours, retour du serveur officiel...).
 */
SheetModal {
    id: root

    signal approved()

    readonly property var app: (typeof application !== "undefined") ? application : null
    readonly property bool pending: !!root.app && !!root.app.pendingServerFingerprint
                                    && root.app.pendingServerFingerprint.length > 0
    property bool showFingerprint: false
    property string trustError: ""
    onOpenChanged: if (open) { root.trustError = ""; root.showFingerprint = false }

    kicker: qsTr("Serveur détecté")
    title: qsTr("Relier ce poste au <b>serveur</b> ?")
    boldTitle: false
    sheetWidth: 520

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Ce poste ne connaît pas encore ce serveur. Demandez à la personne qui l'administre d'ouvrir Administration › Machines : si elle voit le même code pour ce poste, approuvez-le ici pendant qu'elle l'autorise de son côté.")
            color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); lineHeight: 1.12
        }
        CapsLabel { text: qsTr("Code d'appairage") }
        PairingCode { code: root.pending ? root.app.pendingServerPairingCode : "" }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Theme.radiusSheet
            color: Theme.surface0
            border.width: 1
            border.color: Theme.line
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                Text { text: qsTr("Adresse"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.pending ? root.app.pendingServerAddress + ":" + root.app.pendingServerPort : ""
                    color: Theme.ink; font.family: "Cascadia Mono"; font.pixelSize: Theme.fs(12)
                }
            }
        }
        TextLink {
            arrow: false
            text: root.showFingerprint ? qsTr("Masquer l'empreinte complète") : qsTr("Comparer l'empreinte complète")
            onClicked: root.showFingerprint = !root.showFingerprint
        }
        FingerprintGrid {
            visible: root.showFingerprint
            Layout.fillWidth: true
            fingerprint: root.pending ? root.app.pendingServerFingerprint : ""
        }
        Text {
            visible: root.trustError.length > 0
            Layout.fillWidth: true
            text: root.trustError
            wrapMode: Text.WordWrap
            color: Theme.dangerInk; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold
        }
    }

    footer: [
        AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.closeRequested() },
        AppButton {
            variant: "ink"
            iconPath: Icons.check
            enabled: root.pending
            text: qsTr("Les codes sont identiques")
            // La fenetre reste ouverte en cas d'echec pour que l'erreur soit lisible.
            onClicked: {
                if (root.app && root.app.approvePendingServerCertificate()) {
                    root.trustError = ""
                    root.approved()
                } else {
                    root.trustError = qsTr("Impossible d'approuver ce serveur. Relancez la connexion puis réessayez.")
                }
            }
        }
    ]
}
