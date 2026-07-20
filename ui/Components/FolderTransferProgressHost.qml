import QtQuick
import QtQuick.Layouts
import Themes

/*
 * FolderTransferProgressHost - barre(s) de progression globale(s) pour le
 * partage de dossiers.
 *
 * Contexte (UX) : lors du partage d'un dossier contenant N fichiers,
 * TransferService::transferCompleted (un signal par fichier) declenchait
 * potentiellement N toasts individuels. FolderSyncService regroupe deja la
 * NOTIFICATION FINALE en une seule ("N fichiers reçus"/"N fichiers
 * envoyés", cf. folderFilesReceived()/folderFilesSent(), anti-rebond
 * ~800ms) -- ce composant ajoute la piece manquante : PENDANT la rafale,
 * au lieu de rien afficher fichier par fichier, une seule barre de
 * progression globale suit l'avancement (fichiers + octets), puis
 * disparait au profit de la notification finale existante (ToastHost).
 *
 * Ecoute sharedFolderContext.folderTransferProgress (mise a jour en temps
 * reel) et sharedFolderContext.folderTransferBatchFinished (fin de rafale,
 * cf. core::sync::FolderSyncService) -- expose globalement en contexte QML
 * sous le nom "sharedFolderContext" (voir app/main.cpp).
 *
 * A placer une seule fois, comme ToastHost, en dernier enfant de la fenetre
 * racine (Main.qml). Ne modifie ni ne remplace la logique de partage de
 * dossier existante : purement une lecture des signaux deja emis.
 */
Item {
    id: root

    // Sous ToastHost (z: 1000) : la notification finale doit rester au
    // premier plan si les deux se chevauchent brievement.
    z: 999
    anchors.fill: parent

    // Rafales actives, indexees par cle "<folderUuid>|in" ou "<folderUuid>|out"
    // (reception et envoi sont suivis independamment, cf. FolderSyncService).
    property var batches: ({})
    // Ordre d'apparition des cles, pour un affichage stable (pas de saut de
    // position quand une progression se met a jour).
    property var batchOrder: []

    function keyFor(folderUuid, incoming) {
        return folderUuid + "|" + (incoming ? "in" : "out")
    }

    function upsertBatch(folderUuid, folderName, incoming, filesCompleted, filesTotal,
                          bytesTransferred, bytesTotal) {
        const key = keyFor(folderUuid, incoming)
        const updated = Object.assign({}, root.batches)
        updated[key] = {
            folderUuid: folderUuid,
            folderName: folderName,
            incoming: incoming,
            filesCompleted: filesCompleted,
            filesTotal: filesTotal,
            bytesTransferred: bytesTransferred,
            bytesTotal: bytesTotal
        }
        root.batches = updated
        if (root.batchOrder.indexOf(key) === -1) {
            root.batchOrder = root.batchOrder.concat([key])
        }
    }

    function finishBatch(folderUuid, incoming) {
        const key = keyFor(folderUuid, incoming)
        if (!(key in root.batches)) return
        const updated = Object.assign({}, root.batches)
        delete updated[key]
        root.batches = updated
        root.batchOrder = root.batchOrder.filter(function (k) { return k !== key })
    }

    function percentOf(entry) {
        if (!entry || entry.bytesTotal <= 0) return 0
        return Math.min(100, Math.round((entry.bytesTransferred / entry.bytesTotal) * 100))
    }

    function formatBytes(bytes) {
        if (bytes < 1024) return bytes + " o"
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " Ko"
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " Mo"
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " Go"
    }

    Column {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Theme.spacingLarge
        spacing: Theme.spacingSmall
        width: Math.min(420, root.width - Theme.spacingLarge * 2)

        Repeater {
            model: root.batchOrder

            delegate: Rectangle {
                id: card

                property var entry: root.batches[modelData]

                width: parent ? parent.width : 0
                height: contentColumn.implicitHeight + Theme.spacingMedium * 2
                radius: Theme.radiusMedium
                color: Theme.surface
                border.color: Theme.border
                border.width: 1
                visible: entry !== undefined

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 3
                    radius: parent.radius
                    color: Theme.shadow
                    z: -1
                }

                Column {
                    id: contentColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.spacingMedium
                    spacing: Theme.spacingXs

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingSmall

                        Text {
                            text: card.entry ? (card.entry.incoming ? "\u2193" : "\u2191") : ""
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeHeading
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            Layout.fillWidth: true
                            text: card.entry
                                  ? (card.entry.incoming
                                     ? qsTr("Réception \u2022 %1").arg(card.entry.folderName)
                                     : qsTr("Envoi \u2022 %1").arg(card.entry.folderName))
                                  : ""
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: card.entry ? root.percentOf(card.entry) + "%" : ""
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Theme.surfaceAlt

                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            color: Theme.primary
                            width: parent.width * (root.percentOf(card.entry) / 100)

                            Behavior on width { NumberAnimation { duration: 200 } }
                        }
                    }

                    Text {
                        text: card.entry
                              ? qsTr("%1 / %2 fichiers \u2022 %3 / %4")
                                    .arg(card.entry.filesCompleted)
                                    .arg(card.entry.filesTotal)
                                    .arg(root.formatBytes(card.entry.bytesTransferred))
                                    .arg(root.formatBytes(card.entry.bytesTotal))
                              : ""
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeCaption
                    }
                }
            }
        }
    }

    Connections {
        target: sharedFolderContext
        function onFolderTransferProgress(folderUuid, folderName, incoming, filesCompleted,
                                           filesTotal, bytesTransferred, bytesTotal) {
            root.upsertBatch(folderUuid, folderName, incoming, filesCompleted, filesTotal,
                              bytesTransferred, bytesTotal)
        }
        function onFolderTransferComplete(folderUuid, folderName, incoming, fileCount) {
            root.finishBatch(folderUuid, incoming)
        }
    }
}
