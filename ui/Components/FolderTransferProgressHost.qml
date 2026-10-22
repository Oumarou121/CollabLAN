import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Themes
import "icons.js" as Icons

/*
 * FolderTransferProgressHost - bandeau de synchronisation des dossiers
 * partages, en Ligne claire.
 *
 * Contexte (UX) : lors du partage d'un dossier contenant N fichiers,
 * TransferService::transferCompleted (un signal par fichier) declenchait
 * potentiellement N toasts individuels. FolderSyncService regroupe deja la
 * NOTIFICATION FINALE en une seule ("N fichiers reçus"/"N fichiers
 * envoyés", cf. folderFilesReceived()/folderFilesSent(), anti-rebond
 * ~800ms) -- ce composant ajoute la piece manquante : PENDANT la rafale,
 * une feuille par dossier suit l'avancement (fichiers + octets), puis
 * disparait au profit de la notification finale existante (ToastHost).
 *
 * Feuille : pastille fleche (reception = accent, envoi = encre), surtitre,
 * nom du dossier, "x sur y fichiers · Mo sur Mo", pourcentage serif, lien
 * "Voir le dossier" et filet d'avancement en pied. Tant que la taille
 * totale est inconnue (bytesTotal = 0) : etat "Preparation". Trois feuilles
 * au plus, puis "+ N autres dossiers en cours".
 *
 * Ecoute sharedFolderContext.folderTransferProgress (mise a jour en temps
 * reel) et sharedFolderContext.folderTransferComplete (fin de rafale,
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

    // Zone de page : a droite de la barre laterale, au-dessus de la bande
    // d'appel (fournis par Main.qml).
    property real leftInset: 0
    property real bottomInset: 16
    readonly property int maxShown: 3

    // "Voir le dossier" : ouvre ce dossier dans Dossiers partages.
    signal folderRequested(string folderUuid)

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

    // "312 Mo", "9,0 Mo", "1,2 Go" : une decimale seulement sous 10.
    function formatBytes(bytes) {
        const units = ["o", "Ko", "Mo", "Go"]
        let v = Math.max(0, bytes || 0)
        let i = 0
        while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
        const n = i === 0 || v >= 10 ? v.toFixed(0) : v.toFixed(1)
        return n.replace(".", ",") + " " + units[i]
    }

    readonly property var shownKeys: root.batchOrder.slice(0, root.maxShown)
    readonly property int hiddenCount: Math.max(0, root.batchOrder.length - root.maxShown)

    Column {
        id: stack
        readonly property real areaWidth: root.width - root.leftInset - 40
        x: root.leftInset + 20 + (areaWidth - width) / 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomInset
        width: Math.max(0, Math.min(560, areaWidth))
        spacing: 8
        Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }

        Repeater {
            model: root.shownKeys

            delegate: Item {
                id: sheet

                required property string modelData
                readonly property var entry: root.batches[modelData]
                readonly property bool incoming: !!entry && entry.incoming
                readonly property bool preparing: !!entry && entry.bytesTotal <= 0
                readonly property color tone: sheet.incoming ? Theme.accentColor : Theme.ruleInk
                readonly property color toneInk: sheet.incoming ? Theme.navActiveInk : Theme.ink3

                width: stack.width
                height: card.height
                visible: entry !== undefined

                RectangularShadow {
                    anchors.fill: card
                    offset.y: 10
                    blur: 28
                    spread: -6
                    radius: card.radius
                    color: Theme.shadowStrong
                }

                Rectangle {
                    id: card
                    width: parent.width
                    height: row.implicitHeight + 26
                    radius: Theme.radiusSheet
                    color: Theme.bg
                    border.width: 1
                    border.color: Theme.ruleInk
                    clip: true
                    Accessible.role: Accessible.ProgressBar
                    Accessible.name: sheet.entry
                                     ? (sheet.incoming ? qsTr("Réception du dossier %1") : qsTr("Envoi du dossier %1")).arg(sheet.entry.folderName)
                                       + (sheet.preparing ? qsTr(", préparation") : qsTr(", %1 %").arg(root.percentOf(sheet.entry)))
                                     : ""

                    Rectangle { width: 3; height: parent.height; color: sheet.tone }

                    RowLayout {
                        id: row
                        x: 16
                        y: 12
                        width: parent.width - 30
                        spacing: 14

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 18
                            color: "transparent"
                            border.width: 1
                            border.color: sheet.incoming ? Theme.accentColor : Theme.lineStrong
                            LineIcon {
                                anchors.centerIn: parent
                                path: sheet.incoming ? Icons.arrowDown : Icons.arrowUp
                                size: 16
                                strokeWidth: 1.7
                                color: sheet.incoming ? Theme.navActiveInk : Theme.ink2
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: (sheet.incoming ? qsTr("Réception · dossier partagé") : qsTr("Envoi · dossier partagé")).toUpperCase()
                                color: sheet.toneInk
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Theme.weightBold
                                font.letterSpacing: 1.2
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 1
                                text: sheet.entry ? sheet.entry.folderName : ""
                                elide: Text.ElideRight
                                color: Theme.ink
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(13.5)
                                font.weight: Theme.weightSemibold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: !sheet.entry ? ""
                                      : sheet.preparing
                                        ? (sheet.incoming ? qsTr("%1 fichiers à recevoir · calcul de la taille…")
                                                          : qsTr("%1 fichiers à envoyer · calcul de la taille…")).arg(sheet.entry.filesTotal)
                                        : qsTr("%1 sur %2 fichiers · %3 sur %4")
                                              .arg(sheet.entry.filesCompleted)
                                              .arg(sheet.entry.filesTotal)
                                              .arg(root.formatBytes(sheet.entry.bytesTransferred))
                                              .arg(root.formatBytes(sheet.entry.bytesTotal))
                                elide: Text.ElideRight
                                color: Theme.ink3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12)
                                font.features: { "tnum": 1 }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: false
                            Layout.fillHeight: false
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4
                            Text {
                                visible: sheet.preparing
                                Layout.alignment: Qt.AlignRight
                                Layout.topMargin: 6
                                text: qsTr("Préparation").toUpperCase()
                                color: Theme.ink3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Theme.weightBold
                                font.letterSpacing: 1.2
                            }
                            Row {
                                visible: !sheet.preparing
                                Layout.alignment: Qt.AlignRight
                                spacing: 2
                                Text {
                                    id: pctText
                                    text: sheet.entry ? String(root.percentOf(sheet.entry)) : ""
                                    color: Theme.ink
                                    font.family: Theme.fontFamilySerif
                                    font.pixelSize: Theme.fs(26)
                                    font.features: { "tnum": 1, "lnum": 1 }
                                }
                                Text {
                                    anchors.baseline: pctText.baseline
                                    text: "%"
                                    color: Theme.ink3
                                    font.family: Theme.fontFamilySerif
                                    font.pixelSize: Theme.fs(14)
                                }
                            }
                            TextLink {
                                Layout.alignment: Qt.AlignRight
                                text: qsTr("Voir le dossier")
                                fontSize: Theme.fs(12)
                                onClicked: if (sheet.entry) root.folderRequested(sheet.entry.folderUuid)
                            }
                        }
                    }

                    // Filet d'avancement (indetermine pendant la preparation).
                    Rectangle {
                        id: track
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 3
                        height: 3
                        color: Theme.line
                        clip: true
                        Rectangle {
                            visible: !sheet.preparing
                            height: parent.height
                            width: parent.width * (root.percentOf(sheet.entry) / 100)
                            color: sheet.tone
                            Behavior on width { NumberAnimation { duration: 200 } }
                        }
                        Rectangle {
                            id: wave
                            visible: sheet.preparing
                            height: parent.height
                            width: parent.width * 0.22
                            color: sheet.tone
                            opacity: 0.45
                            NumberAnimation on x {
                                running: sheet.preparing && root.visible
                                from: -wave.width
                                to: track.width
                                duration: 1600
                                loops: Animation.Infinite
                            }
                        }
                    }
                }
            }
        }

        // Au-dela de trois dossiers : simple decompte.
        Rectangle {
            visible: root.hiddenCount > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: moreText.implicitWidth + 22
            height: 22
            radius: 11
            color: Theme.bg
            border.width: 1
            border.color: Theme.line
            Text {
                id: moreText
                anchors.centerIn: parent
                text: root.hiddenCount === 1 ? qsTr("+ 1 autre dossier en cours")
                                             : qsTr("+ %1 autres dossiers en cours").arg(root.hiddenCount)
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
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
