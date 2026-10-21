import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "transferFormat.js" as Fmt

/*
 * TransferExchange - un echange (fichier envoye ou recu) dans un dossier de
 * correspondance (Ligne claire). Feuille a filet lateral : a gauche pour une
 * reception, a droite pour un envoi (dans le fil a deux colonnes), encre de
 * marque pendant le transfert, rouge en cas d'echec. Un clic deplie le
 * detail (cause de l'echec, taille, transfere, date, emplacement, actions).
 *
 * row : objet fileRow() de FileTransferView (transferKey, fileName,
 *       peerLabel, incoming, state, errorString, percent, bytesTransferred,
 *       totalBytes, filePath, timestamp).
 */
Rectangle {
    id: root

    property var row: ({})
    property bool expanded: false
    // Fil a deux colonnes : la couleur de sens est du cote du fil central.
    property bool laneLayout: true
    // Vue « Tous les echanges » : le correspondant est rappele.
    property bool showPeer: false
    property string timeText: ""
    property string dateText: ""

    signal toggled()
    signal retryRequested()
    signal openLocationRequested()
    signal resendRequested()

    readonly property bool incoming: !!root.row.incoming
    readonly property string st: root.row.state || "in_progress"
    readonly property bool running: root.st === "in_progress"
    readonly property bool failed: root.st === "failed" || root.st === "interrupted"
    // Seul un ENVOI en echec peut etre relance (TransferContext::retryTransfer).
    readonly property bool canRetry: root.st === "failed" && !root.incoming
    readonly property real pct: Math.max(0, Math.min(100, root.row.percent || 0))
    readonly property color edge: root.failed ? Theme.dangerColor
                                : root.running ? Theme.markTransfer
                                : root.incoming ? Theme.lineStrong : Theme.ruleInk
    readonly property bool edgeLeft: !root.laneLayout || root.incoming

    implicitHeight: col.implicitHeight + 20
    color: Theme.surface0
    radius: Theme.radiusSheet
    border.width: 1
    border.color: root.expanded || hover.hovered ? Theme.lineStrong : Theme.line
    Accessible.role: Accessible.Button
    Accessible.name: (root.incoming ? qsTr("Reçu") : qsTr("Envoyé")) + ", " + (root.row.fileName || "")
                     + ", " + stateWord(root.st)
    activeFocusOnTab: true
    Keys.onReturnPressed: root.toggled()
    Keys.onSpacePressed: root.toggled()

    // Ombre portee quand le detail est ouvert.
    Rectangle {
        visible: root.expanded
        z: -1
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: -6
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        radius: 10
        color: Theme.shadowColor
    }
    // Filet de sens (et d'etat).
    Rectangle {
        width: 3
        height: parent.height
        anchors.left: root.edgeLeft ? parent.left : undefined
        anchors.right: root.edgeLeft ? undefined : parent.right
        color: root.edge
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: Theme.radiusSheet + 2
        color: "transparent"
        border.width: 2
        border.color: Theme.focusRing
        visible: root.activeFocus
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.toggled() }

    function stateWord(s) {
        switch (s) {
        case "completed": return qsTr("Terminé")
        case "failed": return qsTr("Échec")
        case "interrupted": return qsTr("Interrompu")
        case "cancelled": return qsTr("Annulé")
        }
        return qsTr("En cours")
    }
    function glyphFor(s) {
        switch (s) {
        case "completed": return "ok"
        case "failed":
        case "interrupted": return "error"
        case "cancelled": return "watch"
        }
        return "transferring"
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 10
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            LineIcon {
                path: root.incoming ? "M12 4.5v15 M18.5 13 12 19.5 5.5 13" : "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                size: 12
                strokeWidth: 2.2
                color: root.incoming ? Theme.ink2 : Theme.ink3
            }
            CapsLabel {
                Layout.fillWidth: true
                font.pixelSize: Theme.fs(10)
                color: root.incoming ? Theme.ink2 : Theme.ink3
                text: (root.incoming ? qsTr("Reçu") : qsTr("Envoyé"))
                      + (root.showPeer ? " · " + (root.incoming ? qsTr("de %1") : qsTr("à %1")).arg(root.row.peerLabel || "") : "")
            }
            Text {
                text: root.timeText
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11.5)
                font.features: ({ "tnum": 1 })
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            Text {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 3
                text: {
                    const n = root.row.fileName || ""
                    const i = n.lastIndexOf(".")
                    return i > 0 ? n.slice(i + 1, i + 5).toUpperCase() : ""
                }
                color: Theme.ink3
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(10)
                font.weight: Theme.weightBold
                font.letterSpacing: 0.8
            }
            Text {
                Layout.fillWidth: true
                text: root.row.fileName || ""
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13.5)
                font.weight: Theme.weightSemibold
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        // Progression
        Rectangle {
            visible: root.running
            Layout.fillWidth: true
            Layout.topMargin: 9
            Layout.preferredHeight: 2
            color: Theme.line
            Rectangle {
                y: -1
                height: 4
                width: parent.width * root.pct / 100
                color: Theme.markTransfer
                Behavior on width { NumberAnimation { duration: 250 } }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 12
            Text {
                text: root.running
                      ? qsTr("%1 sur %2").arg(Fmt.formatBytes(root.row.bytesTransferred || 0)).arg(Fmt.formatBytes(root.row.totalBytes || 0))
                      : Fmt.formatBytes(root.row.totalBytes || 0)
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.features: ({ "tnum": 1 })
            }
            Row {
                visible: !root.running
                spacing: 6
                StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: root.glyphFor(root.st); size: 11 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.stateWord(root.st)
                    color: root.failed ? Theme.dangerInk : root.st === "completed" ? Theme.successInk : Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Theme.weightSemibold
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: root.running
                text: Math.round(root.pct) + " %"
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(16)
                font.weight: Theme.weightBold
                font.features: ({ "tnum": 1 })
            }
            AppButton {
                visible: root.canRetry
                variant: "dangerGhost"
                size: "small"
                text: qsTr("Réessayer")
                onClicked: root.retryRequested()
            }
        }

        // ---- Detail deplie ---------------------------------------------
        ColumnLayout {
            visible: root.expanded
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 8

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line }

            Rectangle {
                visible: root.failed
                Layout.fillWidth: true
                implicitHeight: errCol.implicitHeight + 16
                color: Theme.dangerSoft
                Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
                ColumnLayout {
                    id: errCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 2
                    CapsLabel { text: root.stateWord(root.st); color: Theme.dangerInk; font.pixelSize: Theme.fs(10) }
                    Text {
                        Layout.fillWidth: true
                        text: (root.row.errorString && root.row.errorString.length > 0) ? root.row.errorString
                              : (root.st === "interrupted" ? qsTr("Le transfert a été interrompu.") : qsTr("Le transfert n'a pas abouti."))
                        color: Theme.ink
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        visible: root.failed && root.incoming
                        Layout.fillWidth: true
                        text: qsTr("Seul l'expéditeur peut relancer ce transfert.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11.5)
                        wrapMode: Text.WordWrap
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 5

                component Key: Text { color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5) }
                component Val: Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                    font.features: ({ "tnum": 1 })
                    elide: Text.ElideLeft
                }

                Key { text: qsTr("Taille") }
                Val { text: Fmt.formatBytes(root.row.totalBytes || 0) }
                Key { text: qsTr("Transféré") }
                Val {
                    text: root.st === "completed" ? qsTr("Complet")
                          : qsTr("%1 (%2 %)").arg(Fmt.formatBytes(root.row.bytesTransferred || 0)).arg(Math.round(root.pct))
                }
                Key { text: qsTr("Date") }
                Val { text: root.dateText }
                Key { visible: (root.row.filePath || "").length > 0; text: qsTr("Emplacement") }
                Val {
                    visible: (root.row.filePath || "").length > 0
                    text: (root.row.filePath || "").replace(/^file:\/\/\/?/, "")
                    ToolTip.visible: pathHover.hovered
                    ToolTip.text: text
                    HoverHandler { id: pathHover }
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.bottomMargin: 2
                spacing: 6
                AppButton {
                    visible: root.canRetry
                    variant: "ink"
                    size: "small"
                    iconPath: "M20.5 12a8.5 8.5 0 1 1-2.6-6.1l2.6 2.6 M20.5 3.5v5h-5"
                    text: qsTr("Réessayer")
                    onClicked: root.retryRequested()
                }
                AppButton {
                    visible: root.st === "completed" && (root.row.filePath || "").length > 0
                    variant: "line"
                    size: "small"
                    text: qsTr("Ouvrir l'emplacement")
                    onClicked: root.openLocationRequested()
                }
                AppButton {
                    visible: !root.incoming && !root.running
                    variant: "line"
                    size: "small"
                    iconPath: "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                    text: qsTr("Renvoyer")
                    onClicked: root.resendRequested()
                }
            }
        }
    }
}
