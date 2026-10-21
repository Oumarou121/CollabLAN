import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "transferFormat.js" as Fmt

/*
 * NewTransferPanel - volet lateral "Nouveau transfert".
 *
 * Modes :
 *   "form"    : Fichier -> Destinataires -> Resume -> Envoyer
 *   "sending" : suivi de l'envoi lance (progression globale + une ligne par
 *               fichier/destinataire), la liste restant visible derriere.
 *
 * AUCUNE logique metier : l'etat (fichiers, dossier, destinataires) et les
 * actions (dialogues, envoi) appartiennent a FileTransferView ; le panneau
 * expose des proprietes et des signaux.
 */
Rectangle {
    id: root

    property var recipients: []            // [{ name, label, address, port, machineId }]
    // Postes autorises mais hors ligne (maquette : opacity ~.55, non selectionnables).
    property var offlineRecipients: []
    property var selectedFilePaths: []
    property string selectedFolderPath: ""
    property var selectedRecipients: []
    property string mode: "form"
    property var batchItems: []
    property string errorText: ""

    signal closeRequested()
    signal browseFilesRequested()
    signal browseFolderRequested()
    signal clearSelectionRequested()
    signal recipientToggled(var recipient)
    signal refreshRecipientsRequested()
    signal sendRequested()
    signal newTransferRequested()
    signal errorDismissed()

    readonly property bool hasFolder: root.selectedFolderPath.length > 0
    readonly property int fileCount: root.hasFolder ? 1 : root.selectedFilePaths.length
    readonly property bool hasSelection: root.fileCount > 0
    readonly property bool canSend: root.hasSelection && root.selectedRecipients.length > 0

    function isSelected(machineId) {
        for (let i = 0; i < root.selectedRecipients.length; ++i) {
            if (root.selectedRecipients[i].machineId === machineId)
                return true
        }
        return false
    }

    readonly property real batchTotal: {
        let n = 0
        for (let i = 0; i < root.batchItems.length; ++i) n += (root.batchItems[i].totalBytes || 0)
        return n
    }
    readonly property real batchDone: {
        let n = 0
        for (let i = 0; i < root.batchItems.length; ++i) n += (root.batchItems[i].bytesTransferred || 0)
        return n
    }
    readonly property int batchActive: {
        let n = 0
        for (let i = 0; i < root.batchItems.length; ++i) if (root.batchItems[i].state === "in_progress") n++
        return n
    }
    readonly property int batchFailed: {
        let n = 0
        for (let i = 0; i < root.batchItems.length; ++i) if (root.batchItems[i].state === "failed") n++
        return n
    }
    readonly property bool batchStarted: root.batchItems.length > 0
    readonly property bool batchFinished: root.batchStarted && root.batchActive === 0
    readonly property int batchPercent: root.batchTotal > 0
                                        ? Math.min(100, Math.floor(root.batchDone * 100 / root.batchTotal))
                                        : (root.batchFinished ? 100 : 0)

    color: Theme.surfaceLevel4

    // Filet gauche + ombre : le volet est un element flottant, l'un des
    // rares endroits ou une ombre plus marquee est admise (priorité 23).
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: 1
        color: Theme.hairlineStrong
    }
    Rectangle {
        x: -28
        width: 28
        height: parent.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(Theme.elevationShadow.r, Theme.elevationShadow.g, Theme.elevationShadow.b, 0) }
            GradientStop { position: 1.0; color: Theme.elevationShadow }
        }
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- En-tete ----
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            Layout.leftMargin: 20
            Layout.rightMargin: 12
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    text: root.mode === "sending" ? qsTr("Envoi en cours") : qsTr("Nouveau transfert")
                    color: Theme.dashboardInk
                    font.pixelSize: Theme.fs(17)
                    font.weight: Font.Bold
                    font.family: Theme.fontFamily
                }
                Label {
                    Layout.fillWidth: true
                    text: root.mode === "sending"
                          ? qsTr("Vous pouvez fermer ce volet : les transferts continuent.")
                          : qsTr("Envoyez des fichiers vers un ou plusieurs postes.")
                    color: Theme.dashboardInkTertiary
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                }
            }

            DashboardButton {
                variant: "ghost"
                iconOnly: true
                controlHeight: 32
                iconPath: Icons.close
                tooltip: qsTr("Fermer")
                onClicked: root.closeRequested()
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }

        // ---- Corps ----
        Flickable {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: bodyColumn.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: bodyColumn
                x: 20
                y: 20
                width: body.width - 40
                spacing: 20

                InlineAlert {
                    visible: root.errorText.length > 0
                    Layout.fillWidth: true
                    text: root.errorText
                    onCloseRequested: root.errorDismissed()
                }

                // ================= FORMULAIRE =================
                ColumnLayout {
                    visible: root.mode === "form"
                    Layout.fillWidth: true
                    spacing: 20

                    // ---- Fichier ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Fichier")
                                color: Theme.dashboardInk
                                font.pixelSize: Theme.fs(13)
                                font.weight: Font.DemiBold
                                font.family: Theme.fontFamily
                            }
                            DashboardButton {
                                visible: root.hasSelection
                                variant: "ghost"
                                controlHeight: 26
                                text: qsTr("Retirer")
                                onClicked: root.clearSelectionRequested()
                            }
                        }

                        // Aucun fichier : zone d'action.
                        Rectangle {
                            visible: !root.hasSelection
                            Layout.fillWidth: true
                            implicitHeight: emptyZone.implicitHeight + 32
                            radius: Theme.radiusLarge
                            color: Theme.dashboardPrimarySoft
                            border.width: 1
                            border.color: Theme.dashboardPrimaryMuted

                            ColumnLayout {
                                id: emptyZone
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Rectangle {
                                        Layout.preferredWidth: 38
                                        Layout.preferredHeight: 38
                                        radius: 11
                                        color: Theme.dashboardPrimarySoft

                                        LineIcon {
                                            anchors.centerIn: parent
                                            size: 20
                                            strokeWidth: 1.75
                                            color: Theme.dashboardPrimary
                                            path: Icons.upload
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Label {
                                            text: qsTr("Aucun fichier sélectionné")
                                            color: Theme.dashboardInk
                                            font.pixelSize: Theme.fs(13)
                                            font.weight: Font.DemiBold
                                            font.family: Theme.fontFamily
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: qsTr("Glissez-déposez des fichiers sur la page, ou choisissez-les.")
                                            color: Theme.dashboardInkTertiary
                                            font.pixelSize: Theme.fs(12)
                                            font.family: Theme.fontFamily
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    DashboardButton {
                                        variant: "secondary"
                                        controlHeight: 32
                                        iconPath: Icons.file
                                        text: qsTr("Choisir des fichiers")
                                        onClicked: root.browseFilesRequested()
                                    }
                                    DashboardButton {
                                        variant: "secondary"
                                        controlHeight: 32
                                        iconPath: Icons.folder
                                        text: qsTr("Un dossier")
                                        onClicked: root.browseFolderRequested()
                                    }
                                }
                            }
                        }

                        // Selection.
                        Rectangle {
                            visible: root.hasSelection
                            Layout.fillWidth: true
                            implicitHeight: selectedColumn.implicitHeight + 8
                            radius: Theme.radiusMedium
                            color: Theme.surfaceLevel2
                            border.width: 1
                            border.color: Theme.hairline

                            ColumnLayout {
                                id: selectedColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 4
                                spacing: 0

                                Repeater {
                                    model: root.hasFolder ? [root.selectedFolderPath]
                                                          : root.selectedFilePaths.slice(0, 4)

                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 44
                                        Layout.leftMargin: 8
                                        Layout.rightMargin: 8
                                        spacing: 10

                                        FileTypeIcon {
                                            fileName: Fmt.fileNameFromPath(modelData)
                                            isFolder: root.hasFolder
                                            size: 28
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Label {
                                                Layout.fillWidth: true
                                                text: Fmt.fileNameFromPath(modelData)
                                                color: Theme.dashboardInk
                                                font.pixelSize: Theme.fs(13)
                                                font.weight: Font.DemiBold
                                                font.family: Theme.fontFamily
                                                elide: Text.ElideMiddle
                                            }
                                            Label {
                                                visible: root.hasFolder
                                                text: qsTr("Dossier complet, sous-dossiers inclus")
                                                color: Theme.dashboardInkTertiary
                                                font.pixelSize: Theme.fs(11)
                                                font.family: Theme.fontFamily
                                            }
                                        }
                                    }
                                }

                                Label {
                                    visible: !root.hasFolder && root.selectedFilePaths.length > 4
                                    Layout.leftMargin: 12
                                    Layout.bottomMargin: 8
                                    text: qsTr("+ %1 autre(s) fichier(s)").arg(root.selectedFilePaths.length - 4)
                                    color: Theme.dashboardInkTertiary
                                    font.pixelSize: Theme.fs(12)
                                    font.family: Theme.fontFamily
                                }
                            }
                        }

                        RowLayout {
                            visible: root.hasSelection
                            spacing: 8
                            DashboardButton {
                                variant: "ghost"
                                controlHeight: 28
                                iconPath: Icons.file
                                text: qsTr("Changer de fichiers")
                                onClicked: root.browseFilesRequested()
                            }
                            DashboardButton {
                                variant: "ghost"
                                controlHeight: 28
                                iconPath: Icons.folder
                                text: qsTr("Choisir un dossier")
                                onClicked: root.browseFolderRequested()
                            }
                        }
                    }

                    // ---- Destinataires ----
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: root.selectedRecipients.length > 0
                                      ? qsTr("Destinataires (%1)").arg(root.selectedRecipients.length)
                                      : qsTr("Destinataires")
                                color: Theme.dashboardInk
                                font.pixelSize: Theme.fs(13)
                                font.weight: Font.DemiBold
                                font.family: Theme.fontFamily
                            }
                            DashboardButton {
                                variant: "ghost"
                                iconOnly: true
                                controlHeight: 26
                                iconPath: Icons.refresh
                                tooltip: qsTr("Actualiser la liste des postes")
                                onClicked: root.refreshRecipientsRequested()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.recipients.length > 0
                                                    ? Math.min(recipientList.contentHeight, 220) + 8
                                                    : 72
                            radius: Theme.radiusMedium
                            color: Theme.surfaceLevel2
                            border.width: 1
                            border.color: Theme.hairline
                            clip: true

                            Label {
                                visible: root.recipients.length === 0
                                anchors.fill: parent
                                anchors.margins: 16
                                text: qsTr("Aucun poste disponible sur le réseau pour le moment.")
                                color: Theme.dashboardInkTertiary
                                font.pixelSize: Theme.fs(12)
                                font.family: Theme.fontFamily
                                wrapMode: Text.WordWrap
                                verticalAlignment: Text.AlignVCenter
                            }

                            ListView {
                                id: recipientList
                                visible: root.recipients.length > 0
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true
                                model: root.recipients
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                delegate: Item {
                                    id: recipientRow
                                    width: ListView.view.width
                                    height: 44

                                    readonly property bool checked: root.isSelected(modelData.machineId)
                                    readonly property bool hovered: recipientHover.hovered
                                    readonly property string presenceText: {
                                        const s = (modelData.status || "").toLowerCase()
                                        if (s === "away") return qsTr("Absent")
                                        if (s === "busy") return qsTr("Occupé")
                                        return qsTr("En ligne")
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.radiusSmall
                                        color: recipientRow.checked ? Theme.dashboardPrimarySoft
                                               : (recipientRow.hovered ? Theme.selectWash : "transparent")
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Rectangle {
                                            Layout.preferredWidth: 18
                                            Layout.preferredHeight: 18
                                            radius: 5
                                            color: recipientRow.checked ? Theme.dashboardPrimary : Theme.dashboardSurface
                                            border.width: 1.5
                                            border.color: recipientRow.checked ? Theme.dashboardPrimary : Theme.dashboardLineStrong

                                            LineIcon {
                                                visible: recipientRow.checked
                                                anchors.centerIn: parent
                                                size: 12
                                                strokeWidth: 3
                                                color: Theme.darkMode ? Theme.dashboardBackground : Theme.dashboardPrimaryText
                                                path: Icons.check
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: 28
                                            Layout.preferredHeight: 28
                                            radius: 14
                                            color: recipientRow.checked ? Theme.dashboardSurface : Theme.dashboardPrimarySoft
                                            LineIcon {
                                                anchors.centerIn: parent
                                                size: 14
                                                strokeWidth: 2
                                                color: Theme.dashboardPrimary
                                                path: Icons.monitor
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                color: Theme.dashboardInk
                                                font.pixelSize: Theme.fs(13)
                                                font.weight: Font.DemiBold
                                                font.family: Theme.fontFamily
                                                elide: Text.ElideRight
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.address
                                                color: Theme.dashboardInkTertiary
                                                font.pixelSize: Theme.fs(11)
                                                font.family: Theme.fontFamily
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Label {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: "\u25CF " + recipientRow.presenceText
                                            color: Theme.dashboardSuccessText
                                            font.pixelSize: Theme.fs(11)
                                            font.family: Theme.fontFamily
                                        }
                                    }

                                    HoverHandler { id: recipientHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: root.recipientToggled(modelData) }
                                }
                            }
                        }

                        // Postes autorises mais hors ligne (maquette .peer[disabled] : opacity ~.55,
                        // non selectionnable).
                        ColumnLayout {
                            visible: root.offlineRecipients.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            spacing: 4

                            Label {
                                text: qsTr("Hors ligne (%1)").arg(root.offlineRecipients.length)
                                color: Theme.dashboardInkTertiary
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.DemiBold
                                font.family: Theme.fontFamily
                            }

                            Repeater {
                                model: root.offlineRecipients

                                delegate: Item {
                                    width: parent ? parent.width : 0
                                    height: 40
                                    opacity: 0.55

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Rectangle {
                                            Layout.preferredWidth: 18
                                            Layout.preferredHeight: 18
                                            radius: 5
                                            color: Theme.dashboardSurface
                                            border.width: 1.5
                                            border.color: Theme.dashboardLineStrong
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 28
                                            Layout.preferredHeight: 28
                                            radius: 14
                                            color: Theme.dashboardSurfaceAlt
                                            LineIcon {
                                                anchors.centerIn: parent
                                                size: 14
                                                strokeWidth: 2
                                                color: Theme.dashboardInkTertiary
                                                path: Icons.monitor
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                color: Theme.dashboardInk
                                                font.pixelSize: Theme.fs(13)
                                                font.weight: Font.DemiBold
                                                font.family: Theme.fontFamily
                                                elide: Text.ElideRight
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.address
                                                color: Theme.dashboardInkTertiary
                                                font.pixelSize: Theme.fs(11)
                                                font.family: Theme.fontFamily
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Label {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: qsTr("Hors ligne")
                                            color: Theme.dashboardInkTertiary
                                            font.pixelSize: Theme.fs(11)
                                            font.family: Theme.fontFamily
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Resume avant envoi ----
                    Rectangle {
                        visible: root.canSend
                        Layout.fillWidth: true
                        implicitHeight: summaryRow.implicitHeight + 24
                        radius: Theme.radiusMedium
                        color: Theme.dashboardPrimarySoft

                        RowLayout {
                            id: summaryRow
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            LineIcon {
                                size: 18
                                strokeWidth: 2
                                color: Theme.dashboardPrimary
                                path: Icons.send
                            }
                            Label {
                                Layout.fillWidth: true
                                text: {
                                    const what = root.hasFolder
                                               ? qsTr("Le dossier « %1 »").arg(Fmt.fileNameFromPath(root.selectedFolderPath))
                                               : (root.fileCount === 1 ? qsTr("1 fichier") : qsTr("%1 fichiers").arg(root.fileCount))
                                    const n = root.selectedRecipients.length
                                    return qsTr("%1 sera envoyé à %2.").arg(what)
                                           .arg(n === 1 ? root.selectedRecipients[0].name : qsTr("%1 postes").arg(n))
                                }
                                color: Theme.dashboardPrimary
                                font.pixelSize: Theme.fs(13)
                                font.weight: Font.DemiBold
                                font.family: Theme.fontFamily
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // ================= SUIVI =================
                ColumnLayout {
                    visible: root.mode === "sending"
                    Layout.fillWidth: true
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: !root.batchStarted ? qsTr("Connexion aux postes…")
                                      : (root.batchFinished
                                         ? (root.batchFailed > 0 ? qsTr("Envoi terminé, avec des échecs") : qsTr("Envoi terminé"))
                                         : qsTr("Envoi en cours"))
                                color: Theme.dashboardInk
                                font.pixelSize: Theme.fs(14)
                                font.weight: Font.Bold
                                font.family: Theme.fontFamily
                            }
                            Label {
                                visible: root.batchStarted
                                text: root.batchPercent + " %"
                                color: root.batchFailed > 0 && root.batchFinished ? Theme.dashboardErrorText : Theme.dashboardPrimary
                                font.pixelSize: Theme.fs(14)
                                font.weight: Font.Bold
                                font.family: Theme.fontFamily
                            }
                        }

                        Rectangle {
                            visible: root.batchStarted
                            Layout.fillWidth: true
                            Layout.preferredHeight: 8
                            radius: 4
                            color: Theme.dashboardLine

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * root.batchPercent / 100
                                radius: 4
                                color: root.batchFailed > 0 && root.batchFinished ? Theme.dashboardError : Theme.dashboardPrimary
                                Behavior on width { NumberAnimation { duration: 180 } }
                            }
                        }

                        SkeletonLine {
                            visible: !root.batchStarted
                            Layout.fillWidth: true
                            Layout.preferredHeight: 8
                            radius: 4
                        }

                        Label {
                            visible: root.batchStarted
                            text: qsTr("%1 sur %2").arg(Fmt.formatBytes(root.batchDone)).arg(Fmt.formatBytes(root.batchTotal))
                            color: Theme.dashboardInkTertiary
                            font.pixelSize: Theme.fs(12)
                            font.family: Theme.fontFamily
                        }
                    }

                    Rectangle {
                        visible: root.batchStarted
                        Layout.fillWidth: true
                        implicitHeight: batchColumn.implicitHeight
                        radius: Theme.radiusMedium
                        color: Theme.surfaceLevel2
                        border.width: 1
                        border.color: Theme.hairline
                        clip: true

                        ColumnLayout {
                            id: batchColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 0

                            Repeater {
                                model: root.batchItems

                                delegate: Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 56

                                    Rectangle {
                                        visible: index > 0
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 1
                                        color: Theme.hairline
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        FileTypeIcon {
                                            fileName: modelData.fileName
                                            size: 28
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            Label {
                                                Layout.fillWidth: true
                                                text: modelData.fileName
                                                color: Theme.dashboardInk
                                                font.pixelSize: Theme.fs(13)
                                                font.weight: Font.DemiBold
                                                font.family: Theme.fontFamily
                                                elide: Text.ElideMiddle
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Rectangle {
                                                    visible: modelData.state === "in_progress"
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 4
                                                    radius: 2
                                                    color: Theme.dashboardLine
                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.top: parent.top
                                                        anchors.bottom: parent.bottom
                                                        width: parent.width * Math.max(0, Math.min(100, modelData.percent || 0)) / 100
                                                        radius: 2
                                                        color: Theme.dashboardPrimary
                                                    }
                                                }
                                                Label {
                                                    Layout.fillWidth: modelData.state !== "in_progress"
                                                    text: modelData.state === "in_progress"
                                                          ? (modelData.percent || 0) + " %"
                                                          : qsTr("vers %1").arg(modelData.peerUserName || modelData.peerName || modelData.peerAddress || "")
                                                    color: Theme.dashboardInkTertiary
                                                    font.pixelSize: Theme.fs(11)
                                                    font.family: Theme.fontFamily
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }

                                        TransferStatusBadge {
                                            transferState: modelData.state || "in_progress"
                                            text: modelData.statusText || ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Pied ----
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            spacing: 8

            Item { Layout.fillWidth: true }

            DashboardButton {
                visible: root.mode === "form"
                variant: "secondary"
                text: qsTr("Annuler")
                onClicked: root.closeRequested()
            }
            DashboardButton {
                visible: root.mode === "form"
                variant: "primary"
                iconPath: Icons.send
                text: qsTr("Envoyer")
                enabled: root.canSend
                onClicked: root.sendRequested()
            }
            DashboardButton {
                visible: root.mode === "sending"
                variant: "secondary"
                text: qsTr("Nouvel envoi")
                onClicked: root.newTransferRequested()
            }
            DashboardButton {
                visible: root.mode === "sending"
                variant: "primary"
                text: qsTr("Fermer")
                onClicked: root.closeRequested()
            }
        }
    }
}
