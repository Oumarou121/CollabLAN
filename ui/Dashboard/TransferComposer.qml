import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "transferFormat.js" as Fmt

/*
 * TransferComposer - volet « Nouveau transfert » de Ligne claire, en trois
 * etapes numerotees : 1 Fichiers, 2 Destinataires, 3 Envoi ; puis le suivi
 * de l'envoi. Meme API que l'ancien NewTransferPanel (remplacement direct).
 */
Rectangle {
    id: root

    property var recipients: []            // [{ name, label, address, port, machineId, status }]
    property var offlineRecipients: []
    property var selectedFilePaths: []
    property string selectedFolderPath: ""
    property var selectedRecipients: []
    property string mode: "form"           // "form" | "sending"
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
        for (let i = 0; i < root.selectedRecipients.length; ++i)
            if (root.selectedRecipients[i].machineId === machineId)
                return true
        return false
    }

    readonly property real batchTotal: root.batchItems.reduce(function(a, b) { return a + (b.totalBytes || 0) }, 0)
    readonly property real batchDone: root.batchItems.reduce(function(a, b) { return a + (b.bytesTransferred || 0) }, 0)
    readonly property int batchActive: root.batchItems.filter(function(b) { return b.state === "in_progress" }).length
    readonly property int batchFailed: root.batchItems.filter(function(b) { return b.state === "failed" || b.state === "interrupted" }).length
    readonly property bool batchStarted: root.batchItems.length > 0
    readonly property bool batchFinished: root.batchStarted && root.batchActive === 0

    function presenceWord(s) {
        s = (s || "").toLowerCase()
        if (s === "away") return qsTr("Absent")
        if (s === "busy") return qsTr("Occupé")
        if (s === "offline") return qsTr("Hors ligne")
        return qsTr("En ligne")
    }
    function presenceKind(s) {
        s = (s || "").toLowerCase()
        return s === "away" || s === "busy" || s === "offline" ? s : "online"
    }

    color: Theme.bg

    // Filet d'encre a gauche + ombre : le volet flotte au-dessus de la page.
    Rectangle { width: 1; height: parent.height; color: Theme.ruleInk; z: 2 }
    Rectangle {
        x: -28
        width: 28
        height: parent.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.shadowStrong }
        }
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    // Etape numerotee : chiffre serif (vert une fois l'etape remplie), titre, resume.
    component StepHeader: RowLayout {
        id: sh
        property string number: "1"
        property string title: ""
        property string meta: ""
        property bool done: false
        spacing: 12
        Text {
            Layout.preferredWidth: 18
            text: sh.number
            color: sh.done ? Theme.successInk : Theme.ink3
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fs(22)
            font.weight: Theme.weightBold
        }
        Text {
            Layout.fillWidth: true
            text: sh.title
            color: Theme.ink
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fs(16)
            font.weight: Theme.weightBold
        }
        CapsLabel { visible: sh.meta.length > 0; text: sh.meta }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 1
        spacing: 0

        // ---- En-tete ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 14
            Layout.topMargin: 18
            Layout.bottomMargin: 14
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                CapsLabel { text: qsTr("Nouveau transfert") }
                Text {
                    text: root.mode === "sending" ? qsTr("Envoi en cours") : qsTr("Envoyer des fichiers")
                    color: Theme.ink
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: Theme.fs(24)
                    font.weight: Theme.weightBold
                }
                Text {
                    Layout.fillWidth: true
                    text: root.mode === "sending"
                          ? qsTr("Vous pouvez fermer ce volet : les transferts continuent.")
                          : qsTr("Chaque destinataire retrouvera l'envoi dans son dossier.")
                    color: Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                    wrapMode: Text.WordWrap
                }
            }
            AbstractButton {
                id: closeBtn
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                hoverEnabled: true
                Accessible.name: qsTr("Fermer")
                onClicked: root.closeRequested()
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                background: Rectangle { radius: 17; color: closeBtn.hovered ? Theme.selectWash : "transparent"; border.width: closeBtn.visualFocus ? 2 : 0; border.color: Theme.focusRing }
                contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.close; size: 17; strokeWidth: 1.8; color: Theme.ink2 } }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line }

        // ---- Erreur ---------------------------------------------------------
        Rectangle {
            visible: root.errorText.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 12
            implicitHeight: errRow.implicitHeight + 16
            color: Theme.dangerSoft
            Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
            RowLayout {
                id: errRow
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                Text {
                    Layout.fillWidth: true
                    text: root.errorText
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                    wrapMode: Text.WordWrap
                }
                TextLink { text: qsTr("OK"); arrow: false; onClicked: root.errorDismissed() }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight + 20
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: body
                x: 24
                width: parent.width - 48
                spacing: 0

                // ================= FORMULAIRE =================
                // -- 1 Fichiers ---------------------------------------------
                ColumnLayout {
                    visible: root.mode === "form"
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 8
                    StepHeader {
                        Layout.fillWidth: true
                        number: "1"
                        title: qsTr("Fichiers")
                        done: root.hasSelection
                        meta: root.hasFolder ? qsTr("1 dossier")
                              : root.fileCount > 0 ? (root.fileCount > 1 ? qsTr("%1 fichiers").arg(root.fileCount) : qsTr("1 fichier")) : ""
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        spacing: 0
                        Repeater {
                            model: root.hasFolder ? [root.selectedFolderPath] : root.selectedFilePaths.slice(0, 6)
                            delegate: RowLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                spacing: 10
                                Text {
                                    Layout.preferredWidth: 34
                                    text: {
                                        if (root.hasFolder) return qsTr("DOS.")
                                        const n = Fmt.fileNameFromPath(modelData)
                                        const i = n.lastIndexOf(".")
                                        return i > 0 ? n.slice(i + 1, i + 5).toUpperCase() : ""
                                    }
                                    color: Theme.ink3
                                    font.family: Theme.fontFamilySerif
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Theme.weightBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: Fmt.fileNameFromPath(modelData) + (root.hasFolder ? " — " + qsTr("sous-dossiers inclus") : "")
                                    color: Theme.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(13)
                                    elide: Text.ElideMiddle
                                }
                            }
                        }
                        Text {
                            visible: !root.hasFolder && root.selectedFilePaths.length > 6
                            text: qsTr("+ %1 autre(s) fichier(s)").arg(root.selectedFilePaths.length - 6)
                            color: Theme.ink3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                        }
                        Text {
                            visible: !root.hasSelection
                            Layout.fillWidth: true
                            text: qsTr("Aucun fichier choisi. Vous pouvez aussi glisser des fichiers sur la page.")
                            color: Theme.ink3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12.5)
                            wrapMode: Text.WordWrap
                        }
                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            spacing: 8
                            AppButton { variant: "line"; size: "small"; iconPath: Icons.plus; text: root.hasSelection ? qsTr("Changer de fichiers") : qsTr("Choisir des fichiers"); onClicked: root.browseFilesRequested() }
                            AppButton { variant: "line"; size: "small"; iconPath: Icons.folder; text: qsTr("Un dossier"); onClicked: root.browseFolderRequested() }
                            TextLink { visible: root.hasSelection; text: qsTr("Retirer"); arrow: false; onClicked: root.clearSelectionRequested() }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 10; Layout.preferredHeight: 1; color: Theme.line }
                }

                // -- 2 Destinataires -----------------------------------------
                ColumnLayout {
                    visible: root.mode === "form"
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        StepHeader {
                            Layout.fillWidth: true
                            number: "2"
                            title: qsTr("Destinataires")
                            done: root.selectedRecipients.length > 0
                            meta: root.selectedRecipients.length > 1 ? qsTr("%1 choisis").arg(root.selectedRecipients.length)
                                  : root.selectedRecipients.length === 1 ? qsTr("1 choisi") : ""
                        }
                        TextLink { text: qsTr("Actualiser"); arrow: false; fontSize: Theme.fs(12); onClicked: root.refreshRecipientsRequested() }
                    }
                    Text {
                        visible: root.recipients.length === 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        text: qsTr("Aucun poste disponible sur le réseau pour le moment.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                        wrapMode: Text.WordWrap
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        spacing: 0
                        Repeater {
                            model: root.recipients
                            delegate: AbstractButton {
                                id: rb
                                required property var modelData
                                required property int index
                                readonly property bool picked: root.isSelected(modelData.machineId)
                                Layout.fillWidth: true
                                implicitHeight: 48
                                hoverEnabled: true
                                focusPolicy: Qt.TabFocus
                                Accessible.role: Accessible.CheckBox
                                Accessible.checked: rb.picked
                                Accessible.name: modelData.name
                                onClicked: root.recipientToggled(modelData)
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                background: Rectangle {
                                    color: rb.hovered ? Theme.selectWash : "transparent"
                                    border.width: rb.visualFocus ? 2 : 0
                                    border.color: Theme.focusRing
                                    Rectangle { visible: rb.index > 0; width: parent.width; height: 1; color: Theme.line }
                                }
                                contentItem: RowLayout {
                                    spacing: 10
                                    Rectangle {
                                        Layout.leftMargin: 6
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        radius: 2
                                        color: rb.picked ? Theme.ink : "transparent"
                                        border.width: rb.picked ? 0 : 1.5
                                        border.color: Theme.lineStrong
                                        LineIcon { visible: rb.picked; anchors.centerIn: parent; path: Icons.check; size: 12; strokeWidth: 2.6; color: Theme.inkOnInk }
                                    }
                                    StateGlyph { kind: root.presenceKind(modelData.status); size: 12 }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text { Layout.fillWidth: true; text: modelData.name; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold; elide: Text.ElideRight }
                                        Text { Layout.fillWidth: true; text: modelData.address; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
                                    }
                                    Text { Layout.rightMargin: 6; text: root.presenceWord(modelData.status); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
                                }
                            }
                        }
                        CapsLabel {
                            visible: root.offlineRecipients.length > 0
                            Layout.topMargin: 12
                            Layout.bottomMargin: 4
                            text: qsTr("Hors ligne · indisponibles")
                        }
                        Repeater {
                            model: root.offlineRecipients
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                spacing: 10
                                opacity: 0.55
                                Rectangle { Layout.leftMargin: 6; Layout.preferredWidth: 16; Layout.preferredHeight: 16; radius: 2; color: "transparent"; border.width: 1.5; border.color: Theme.line }
                                StateGlyph { kind: "offline"; size: 12 }
                                Text { Layout.fillWidth: true; text: modelData.name; color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); elide: Text.ElideRight }
                                Text { Layout.rightMargin: 6; text: qsTr("Hors ligne"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 10; Layout.preferredHeight: 1; color: Theme.line }
                }

                // -- 3 Envoi ---------------------------------------------------
                ColumnLayout {
                    visible: root.mode === "form"
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 6
                    StepHeader { Layout.fillWidth: true; number: "3"; title: qsTr("Envoi") }
                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        textFormat: Text.StyledText
                        text: {
                            if (!root.canSend)
                                return qsTr("Choisissez au moins un fichier et un destinataire.")
                            const what = root.hasFolder
                                       ? qsTr("Le dossier <b>« %1 »</b>").arg(Fmt.fileNameFromPath(root.selectedFolderPath))
                                       : (root.fileCount === 1 ? qsTr("<b>1 fichier</b>") : qsTr("<b>%1 fichiers</b>").arg(root.fileCount))
                            const n = root.selectedRecipients.length
                            const verb = !root.hasFolder && root.fileCount > 1 ? qsTr("seront envoyés") : qsTr("sera envoyé")
                            return what + " " + verb + " " + qsTr("à <b>%1</b>.").arg(n === 1 ? root.selectedRecipients[0].name : qsTr("%1 postes").arg(n))
                        }
                        color: root.canSend ? Theme.ink2 : Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(14)
                        wrapMode: Text.WordWrap
                    }
                }

                // ================= SUIVI =================
                ColumnLayout {
                    visible: root.mode === "sending"
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 0
                    StepHeader {
                        Layout.fillWidth: true
                        number: "3"
                        title: !root.batchStarted ? qsTr("Connexion aux postes…")
                               : root.batchFinished ? (root.batchFailed > 0 ? qsTr("Envoi terminé, avec des échecs") : qsTr("Envoi terminé"))
                               : qsTr("Envoi en cours")
                        done: root.batchFinished && root.batchFailed === 0
                        meta: root.batchStarted ? qsTr("%1 sur %2").arg(Fmt.formatBytes(root.batchDone)).arg(Fmt.formatBytes(root.batchTotal)) : ""
                    }
                    Repeater {
                        model: root.batchItems
                        delegate: ColumnLayout {
                            required property var modelData
                            required property int index
                            readonly property real pct: Math.max(0, Math.min(100, modelData.percent || 0))
                            readonly property bool bad: modelData.state === "failed" || modelData.state === "interrupted"
                            Layout.fillWidth: true
                            Layout.leftMargin: 30
                            Layout.topMargin: 10
                            spacing: 4
                            Rectangle { visible: index > 0; Layout.fillWidth: true; Layout.preferredHeight: 1; Layout.bottomMargin: 6; color: Theme.line }
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.peerUserName || modelData.peerName || modelData.peerAddress || ""
                                    color: Theme.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(13)
                                    font.weight: Theme.weightSemibold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: Math.round(parent.parent.pct) + " %"
                                    color: parent.parent.bad ? Theme.dangerInk : Theme.ink
                                    font.family: Theme.fontFamilySerif
                                    font.pixelSize: Theme.fs(16)
                                    font.weight: Theme.weightBold
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 2
                                color: Theme.line
                                Rectangle {
                                    y: -1
                                    height: 4
                                    width: parent.width * parent.parent.pct / 100
                                    color: parent.parent.bad ? Theme.dangerColor : modelData.state === "completed" ? Theme.successColor : Theme.markTransfer
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.fileName + " · " + (modelData.statusText || "")
                                color: Theme.ink3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12)
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }
            }
        }

        // ---- Pied ---------------------------------------------------------
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            spacing: 8
            Text {
                Layout.fillWidth: true
                visible: root.mode === "sending" && root.batchStarted
                text: qsTr("%1 sur %2 terminé(s)").arg(root.batchItems.length - root.batchActive).arg(root.batchItems.length)
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
            }
            Item { Layout.fillWidth: true; visible: !(root.mode === "sending" && root.batchStarted) }
            AppButton { visible: root.mode === "form"; variant: "line"; text: qsTr("Annuler"); onClicked: root.closeRequested() }
            AppButton {
                visible: root.mode === "form"
                variant: "ink"
                iconPath: "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                text: root.selectedRecipients.length > 1 ? qsTr("Envoyer à %1 postes").arg(root.selectedRecipients.length) : qsTr("Envoyer")
                enabled: root.canSend
                onClicked: root.sendRequested()
            }
            AppButton { visible: root.mode === "sending"; variant: "line"; text: qsTr("Fermer"); onClicked: root.closeRequested() }
            AppButton { visible: root.mode === "sending"; variant: "ink"; text: qsTr("Nouvel envoi"); onClicked: root.newTransferRequested() }
        }
    }
}
