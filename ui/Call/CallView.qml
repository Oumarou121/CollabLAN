import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * CallView - ecran d'appel vocal P2P (issues #60/#61/#64).
 *
 * Purement reactif, comme UsersView/FileTransferView : s'appuie sur le
 * contexte QML global "callContext" (core::CallContext, expose depuis
 * app/main.cpp), lui-meme branche sur network::VoiceService. Deux zones :
 *  - hors appel (callState === "idle") : liste des postes decouverts
 *    (reutilise "peersModel", comme UsersView/FileTransferView) avec un
 *    bouton "Appeler" par poste ;
 *  - pendant un appel (tout autre etat) : panneau plein ecran refletant
 *    calling/ringing/connecting/connected/ending, avec les actions
 *    pertinentes (decrocher/refuser/raccrocher/mute).
 */
Item {
    id: root

    // Proprietes optionnelles : permettent de charger cette vue dans un
    // contexte de preview/design sans que les contextes globaux existent.
    property var call: (typeof callContext !== "undefined") ? callContext : null
    property var peers: (typeof peersModel !== "undefined") ? peersModel : null

    readonly property string callState: root.call ? root.call.callState : "idle"
    readonly property bool inCall: root.callState !== "idle"

    signal backRequested()

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    // Banniere d'erreur discrete (adresse invalide, appel refuse par le
    // service, perte de connexion...), auto-masquee apres quelques secondes.
    Rectangle {
        id: errorBanner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: errorLabel.implicitHeight + Theme.spacingMedium
        color: Theme.error
        visible: opacity > 0
        opacity: 0
        z: 10

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Label {
            id: errorLabel
            anchors.centerIn: parent
            width: parent.width - Theme.spacingLarge * 2
            color: "#FFFFFF"
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Timer {
            id: hideErrorTimer
            interval: 4000
            onTriggered: errorBanner.opacity = 0
        }

        function show(message) {
            errorLabel.text = message
            opacity = 1
            hideErrorTimer.restart()
        }
    }

    Connections {
        target: root.call
        function onErrorOccurred(message) { errorBanner.show(message) }
        function onCallEnded(reason) {
            if (reason === "connection-lost") {
                errorBanner.show(qsTr("Connexion perdue avec le correspondant."))
            }
        }
    }

    // --- Ecran hors appel : liste des postes a appeler --------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingMedium
        visible: !root.inCall

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Button {
                text: qsTr("< Retour")
                Layout.preferredHeight: 32

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                    border.width: 1
                    border.color: Theme.border
                }

                contentItem: Text {
                    text: qsTr("< Retour")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: root.backRequested()
            }

            Label {
                text: qsTr("Appel")
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.text
            }

            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.spacingSmall
                visible: peersListView.count === 0
                width: parent.width * 0.7

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Aucun poste detecte pour le moment")
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.text
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    text: qsTr("Choisissez un poste des que quelqu'un est detecte pour l'appeler.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            ListView {
                id: peersListView
                anchors.fill: parent
                anchors.margins: Theme.spacingSmall
                spacing: Theme.spacingSmall
                clip: true
                model: root.peers

                delegate: Rectangle {
                    width: peersListView.width
                    height: 60
                    radius: Theme.radiusMedium
                    color: Theme.surfaceAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMedium
                        anchors.rightMargin: Theme.spacingMedium
                        spacing: Theme.spacingMedium

                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: Theme.primary

                            Text {
                                anchors.centerIn: parent
                                text: name && name.length > 0 ? name.charAt(0).toUpperCase() : "?"
                                color: Theme.primaryText
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                text: name
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Label {
                                text: address
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        Button {
                            text: qsTr("Appeler")
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: 96
                            enabled: root.call !== null

                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: parent.enabled ? (parent.hovered ? Theme.primaryHover : Theme.primary)
                                                       : Theme.surfaceAlt
                            }

                            contentItem: Text {
                                text: qsTr("Appeler")
                                color: parent.enabled ? Theme.primaryText : Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                if (!root.call) {
                                    return
                                }
                                if (!root.call.call(address)) {
                                    errorBanner.show(qsTr("Impossible d'appeler %1").arg(name))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Panneau plein ecran pendant un appel ------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingLarge
        visible: root.inCall

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 96
            height: 96
            radius: 48
            color: Theme.primary

            Text {
                anchors.centerIn: parent
                text: root.call && root.call.remoteAddress.length > 0
                      ? root.call.remoteAddress.charAt(0).toUpperCase() : "?"
                color: Theme.primaryText
                font.pixelSize: 36
                font.bold: true
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.call ? root.call.remoteAddress : ""
            color: Theme.text
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeBody
            text: {
                switch (root.callState) {
                case "calling":    return qsTr("Appel en cours...")
                case "ringing":    return qsTr("Appel entrant")
                case "connecting": return qsTr("Connexion...")
                case "connected":  return qsTr("En communication")
                case "ending":     return qsTr("Fin de l'appel...")
                default:           return ""
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Appel entrant : accepter / refuser.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spacingLarge
            visible: root.callState === "ringing"

            CallActionButton {
                label: qsTr("Refuser")
                bgColor: Theme.error
                onClicked: root.call && root.call.hangUp()
            }

            CallActionButton {
                label: qsTr("Decrocher")
                bgColor: Theme.success
                onClicked: root.call && root.call.acceptCall()
            }
        }

        // Appel sortant en attente de reponse, ou en cours de negociation :
        // seule action possible, annuler.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spacingLarge
            visible: root.callState === "calling" || root.callState === "connecting"

            CallActionButton {
                label: qsTr("Annuler")
                bgColor: Theme.error
                onClicked: root.call && root.call.hangUp()
            }
        }

        // Appel etabli : mute + raccrocher.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spacingLarge
            visible: root.callState === "connected"

            CallActionButton {
                label: root.call && root.call.muted ? qsTr("Reactiver micro") : qsTr("Couper micro")
                bgColor: root.call && root.call.muted ? Theme.warning : Theme.surfaceAlt
                textColor: root.call && root.call.muted ? Theme.primaryText : Theme.text
                onClicked: root.call && root.call.toggleMute()
            }

            CallActionButton {
                label: qsTr("Raccrocher")
                bgColor: Theme.error
                onClicked: root.call && root.call.hangUp()
            }
        }

        Item { Layout.fillHeight: true }
    }

    // Bouton d'action rond (raccrocher/decrocher/mute...), factorise ici
    // plutot que dans un fichier separe : usage limite a cet ecran.
    component CallActionButton: Button {
        property string label: ""
        property color bgColor: Theme.primary
        property color textColor: Theme.primaryText

        implicitWidth: 120
        implicitHeight: 48

        background: Rectangle {
            radius: Theme.radiusMedium
            color: parent.hovered ? Qt.darker(parent.bgColor, 1.1) : parent.bgColor
        }

        contentItem: Text {
            text: parent.label
            color: parent.textColor
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
