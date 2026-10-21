import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * TransferList - Container minimal pour transferts
 * Pas de carte blanche, juste header + lignes à plat
 */
ColumnLayout {
    id: root
    spacing: 0

    property var transfers: []
    property bool loading: false
    // false quand la liste est placee dans une Card qui porte deja le titre.
    property bool showHeader: true

    // Deduction actif/historique à partir de state (repli sur status) -
    // meme logique que TransferRow.effectiveState, pour que le regroupement
    // et le rendu de chaque ligne restent cohérents (priorité 2 du brief).
    function isTransferActive(t) {
        const s = t.state && t.state.length > 0 ? t.state : ({
            "En cours": "in_progress", "Terminé": "completed", "Échoué": "failed",
            "Annulé": "cancelled", "Interrompu": "interrupted"
        }[t.status] || "in_progress")
        return s === "in_progress"
    }
    readonly property var activeTransfers: root.transfers.filter(isTransferActive)
    readonly property var historyTransfers: root.transfers.filter(t => !isTransferActive(t))

    signal detailsRequested(var transfer)
    signal openLocationRequested(var transfer)
    signal retryRequested(var transfer)
    signal newTransferRequested()
    // Lien "Tous les transferts" de l'en-tete.
    signal allTransfersRequested()

    // Header - height 30px
    Item {
        visible: root.showHeader
        Layout.fillWidth: true
        Layout.preferredHeight: 30

        RowLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: qsTr("Transferts")
                color: Theme.dashboardInk
                font.pixelSize: Theme.fs(15)
                font.bold: true
                font.family: Theme.fontFamily
            }

            // Résumé contextuel (priorité 11 du brief) : nombre de récents
            // + nombre en cours, plutôt qu'un seul compteur trompeur.
            Label {
                text: {
                    if (root.transfers.length === 0) return ""
                    const parts = []
                    if (root.historyTransfers.length > 0)
                        parts.push(root.historyTransfers.length + " récent" + (root.historyTransfers.length > 1 ? "s" : ""))
                    if (root.activeTransfers.length > 0)
                        parts.push(root.activeTransfers.length + " en cours")
                    return parts.join(" \u00B7 ")
                }
                color: Theme.dashboardInkTertiary
                font.pixelSize: Theme.fs(12)
                font.family: Theme.fontFamily
            }

            Item { Layout.fillWidth: true }

            Button {
                id: allTransfersButton
                text: qsTr("Tous les transferts →")
                flat: true
                font.pixelSize: Theme.fs(12)
                font.family: Theme.fontFamily
                background: Rectangle { color: "transparent" }
                contentItem: Label {
                    text: allTransfersButton.text
                    color: allTransfersButton.hovered ? Theme.dashboardPrimaryHover
                                                      : Theme.dashboardPrimary
                    font.pixelSize: Theme.fs(12)
                    font.weight: Theme.weightSemibold
                    font.underline: allTransfersButton.hovered
                    font.family: Theme.fontFamily
                }
                // Le bouton etait inerte : il ouvre maintenant l'ecran
                // Transferts (signal traite par l'ecran hote).
                onClicked: root.allTransfersRequested()
            }
        }
    }

    SkeletonRows {
        visible: root.loading
        variant: "transfer"
        Layout.fillWidth: true
    }

    EmptyState {
        visible: !root.loading && root.transfers.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        iconName: "transfer"
        title: qsTr("Aucun transfert en cours")
        description: qsTr("Les fichiers envoyés et reçus apparaîtront ici.")
        actionText: qsTr("Envoyer un fichier")
        onActionClicked: root.newTransferRequested()
    }

    // Lignes à plat
    ScrollView {
        visible: !root.loading && root.transfers.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 4

            // Transferts actifs - mis en avant (priorité 2 du brief) :
            // le dashboard doit raconter ce qui se passe maintenant, pas
            // seulement afficher un historique.
            Label {
                visible: root.activeTransfers.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: qsTr("Transferts actifs")
                color: Theme.dashboardInkTertiary
                font.pixelSize: Theme.fs(11)
                font.bold: true
                font.family: Theme.fontFamily
            }

            Repeater {
                model: root.activeTransfers
                delegate: TransferRow {
                    Layout.fillWidth: true
                    fileName: modelData.fileName || ""
                    peerName: modelData.peerName || ""
                    address: modelData.address || ""
                    progress: modelData.progress || 0
                    transferred: modelData.transferred || 0
                    total: modelData.total || 0
                    status: modelData.status || "En cours"
                    transferState: modelData.state || ""
                    timestamp: modelData.timestamp || ""
                    isIncoming: modelData.isIncoming || false

                    onDetailsRequested: root.detailsRequested(modelData)
                    onOpenLocationRequested: root.openLocationRequested(modelData)
                    onRetryRequested: root.retryRequested(modelData)
                }
            }

            Label {
                visible: root.activeTransfers.length > 0 && root.historyTransfers.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 10
                text: qsTr("Historique récent")
                color: Theme.dashboardInkTertiary
                font.pixelSize: Theme.fs(11)
                font.bold: true
                font.family: Theme.fontFamily
            }

            Repeater {
                model: root.historyTransfers
                delegate: TransferRow {
                    Layout.fillWidth: true
                    fileName: modelData.fileName || ""
                    peerName: modelData.peerName || ""
                    address: modelData.address || ""
                    progress: modelData.progress || 0
                    transferred: modelData.transferred || 0
                    total: modelData.total || 0
                    status: modelData.status || "En cours"
                    transferState: modelData.state || ""
                    timestamp: modelData.timestamp || ""
                    isIncoming: modelData.isIncoming || false

                    onDetailsRequested: root.detailsRequested(modelData)
                    onOpenLocationRequested: root.openLocationRequested(modelData)
                    onRetryRequested: root.retryRequested(modelData)
                }
            }
        }
    }
}
