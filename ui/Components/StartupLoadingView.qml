import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Call/callPeople.js" as People

/*
 * StartupLoadingView - page de chargement en Ligne claire, affichee pendant
 * la preparation de la session (reprise automatique) avant la connexion ou
 * l'application (au moins 3 s, voir Main.qml).
 *
 *   marque · « Reseau local · poste » · filet d'encre qui avance
 *   « Reprise de la session de X… » · Session / Reseau / Postes
 *
 * Main.qml pose sessionRestored et startupChecked sur cette instance ; elles
 * sont lues par leur nom pour ne pas redeclarer ces proprietes ici. Le reste
 * vient des objets de contexte (settingsModel, electionService, peersModel).
 */
Item {
    id: root
    objectName: "startupLoadingView"

    readonly property var settings: (typeof settingsModel !== "undefined") ? settingsModel : null
    readonly property var election: (typeof electionService !== "undefined") ? electionService : null
    readonly property var peersSource: (typeof peersModel !== "undefined") ? peersModel : null

    readonly property string machineName: root.settings && root.settings.machineName ? root.settings.machineName : ""
    readonly property string remembered: root.settings && root.settings.rememberedUsername ? root.settings.rememberedUsername : ""
    readonly property bool checked: root["startupChecked"] === true
    readonly property bool restored: root["sessionRestored"] === true
    readonly property string roleLabel: root.election ? (root.election.roleLabel || "") : ""
    readonly property int peerCount: root.peersSource && root.peersSource.count !== undefined ? root.peersSource.count : 0
    readonly property string activeServer: {
        root.peerCount
        const uuid = root.election ? (root.election.activeServerUuid || "") : ""
        if (!uuid.length) return ""
        const p = People.readPeers(root.peersSource)
        for (let i = 0; i < p.length; i++) if (p[i].id === uuid) return p[i].machine || ""
        return ""
    }

    // La decouverte des postes prend quelques instants : on ne dit « aucun
    // autre poste » qu'apres ce delai.
    property bool peersSettled: false
    Timer { interval: 2000; running: true; onTriggered: root.peersSettled = true }

    // Arret de l'animation (captures figees).
    property bool animate: true

    function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    readonly property var rows: [
        { key: qsTr("Session"),
          glyph: root.restored ? "ok" : (root.remembered.length && !root.checked ? "transferring" : "offline"),
          value: root.restored ? qsTr("reprise · %1").arg(root.remembered)
                 : root.remembered.length && !root.checked ? qsTr("reprise en cours…") : qsTr("connexion à suivre"),
          wait: root.remembered.length > 0 && !root.checked },
        { key: qsTr("Réseau"),
          glyph: root.roleLabel.length ? (root.roleLabel === "TEMP_SERVER" ? "away" : "ok") : "transferring",
          value: root.roleLabel === "SERVER" ? qsTr("ce poste est le serveur")
                 : root.roleLabel === "TEMP_SERVER" ? qsTr("ce poste assure le secours")
                 : root.roleLabel === "CLIENT" ? (root.activeServer.length ? qsTr("relié à %1").arg(root.activeServer) : qsTr("relié au serveur"))
                 : qsTr("recherche du serveur…"),
          wait: root.roleLabel.length === 0 },
        { key: qsTr("Postes"),
          glyph: root.peerCount > 0 ? "ok" : (root.peersSettled ? "offline" : "transferring"),
          value: root.peerCount > 1 ? qsTr("%1 postes détectés").arg(root.peerCount)
                 : root.peerCount === 1 ? qsTr("1 poste détecté")
                 : root.peersSettled ? qsTr("aucun autre poste pour l'instant") : qsTr("recherche des postes…"),
          wait: root.peerCount === 0 && !root.peersSettled }
    ]

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(560, root.width - 48)
        spacing: 0

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14
            BrandMark { size: 52 }
            Text {
                text: "LocaLink"
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(40)
                font.weight: Theme.weightBold
            }
        }
        CapsLabel {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 12
            text: root.machineName.length ? qsTr("Réseau local · %1").arg(root.machineName) : qsTr("Réseau local")
        }

        // Filet d'encre qui avance (progression indeterminee).
        Rectangle {
            id: track
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 340
            Layout.topMargin: 28
            Layout.preferredHeight: 2
            color: Theme.line
            clip: true
            Accessible.role: Accessible.ProgressBar
            Accessible.name: qsTr("Préparation de la session")
            Rectangle {
                id: runner
                objectName: "loadingRunner"
                width: track.width * 0.34
                height: 2
                color: Theme.ruleInk
                x: -width
                NumberAnimation on x {
                    id: runAnim
                    from: -runner.width
                    to: track.width
                    duration: 1400
                    loops: Animation.Infinite
                    easing.type: Easing.InOutCubic
                    running: root.visible && root.animate
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 18
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            text: root.remembered.length ? qsTr("Reprise de la session de <b>%1</b>…").arg(root.esc(root.remembered))
                                         : qsTr("Préparation de votre session…")
            color: Theme.ink
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fs(22)
            Accessible.role: Accessible.StaticText
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: false
            Layout.preferredWidth: 340
            Layout.topMargin: 24
            spacing: 0
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line }
            Repeater {
                model: root.rows
                delegate: Item {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 38
                    Accessible.role: Accessible.StaticText
                    Accessible.name: modelData.key + " : " + modelData.value
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                    RowLayout {
                        anchors.fill: parent
                        spacing: 10
                        Item {
                            implicitWidth: 12; implicitHeight: 12
                            StateGlyph { anchors.centerIn: parent; visible: !modelData.wait; kind: modelData.glyph; size: 11 }
                            Spinner { anchors.fill: parent; visible: modelData.wait; running: modelData.wait && root.animate; color: Theme.ink3; lineWidth: 1.6 }
                        }
                        Text { Layout.preferredWidth: 82; text: modelData.key; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: modelData.value
                            elide: Text.ElideRight
                            color: modelData.wait ? Theme.ink3 : Theme.ink
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13)
                        }
                    }
                }
            }
        }
    }

    CapsLabel {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        text: qsTr("LocaLink · version %1").arg("1.0.0")
        color: Theme.ink3
    }
}
