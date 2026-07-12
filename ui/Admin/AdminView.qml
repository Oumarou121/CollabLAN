import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AdminView - gestion des postes de confiance pour la synchronisation
 * chiffree des dossiers partages (issue #12 / TLS).
 *
 * network::SyncNetworkService delegue a sa propre instance de
 * TlsHandshakeService : seuls les postes dont l'empreinte de certificat
 * figure dans TrustedPeerStore peuvent etablir une session de
 * synchronisation. Cette vue permet a l'administrateur de :
 *  - voir les postes actuellement autorises (et les revoquer),
 *  - voir les postes qui ont tente de se connecter mais ont ete refuses
 *    (unknownPeerRejected), et les autoriser en un clic.
 */
Item {
    id: root

    property var service: (typeof syncNetworkService !== "undefined") ? syncNetworkService : null

    ListModel { id: pendingModel }

    Connections {
        target: root.service
        function onUnknownPeerRejected(fingerprint, peerAddress) {
            for (let i = 0; i < pendingModel.count; ++i) {
                if (pendingModel.get(i).fingerprint === fingerprint) {
                    return
                }
            }
            pendingModel.append({ fingerprint: fingerprint, peerAddress: peerAddress })
        }
        function onPeerConnected() { refreshTrusted() }
    }

    function refreshTrusted() {
        trustedModel.clear()
        if (!root.service) {
            return
        }
        const fingerprints = root.service.trustedFingerprints()
        for (let i = 0; i < fingerprints.length; ++i) {
            trustedModel.append({ fingerprint: fingerprints[i] })
        }
    }

    Component.onCompleted: refreshTrusted()

    ListModel { id: trustedModel }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingMedium

        Label {
            text: qsTr("Administration - Postes de confiance")
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            font.family: Theme.fontFamily
            color: Theme.text
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("La synchronisation des dossiers partages est chiffree (TLS). Seuls les postes autorises ci-dessous peuvent echanger des fichiers avec ce poste.")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacingMedium

            // Colonne des postes en attente d'autorisation
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusLarge
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMedium
                    spacing: Theme.spacingSmall

                    Label {
                        text: qsTr("En attente d'autorisation (%1)").arg(pendingModel.count)
                        font.bold: true
                        color: Theme.text
                    }

                    Label {
                        visible: pendingModel.count === 0
                        Layout.fillWidth: true
                        text: qsTr("Aucune tentative de connexion refusee pour le moment.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Theme.spacingSmall
                        model: pendingModel

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 56
                            radius: Theme.radiusMedium
                            color: Theme.surfaceAlt

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingMedium
                                anchors.rightMargin: Theme.spacingMedium
                                spacing: Theme.spacingSmall

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Label {
                                        text: peerAddress
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Label {
                                        text: fingerprint
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                }

                                Button {
                                    text: qsTr("Autoriser")
                                    onClicked: {
                                        if (root.service) {
                                            root.service.trustPeer(fingerprint, peerAddress)
                                        }
                                        pendingModel.remove(index)
                                        refreshTrusted()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Colonne des postes deja autorises
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusLarge
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMedium
                    spacing: Theme.spacingSmall

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            text: qsTr("Postes autorises (%1)").arg(trustedModel.count)
                            font.bold: true
                            color: Theme.text
                            Layout.fillWidth: true
                        }

                        Button {
                            text: qsTr("Actualiser")
                            onClicked: refreshTrusted()
                        }
                    }

                    Label {
                        visible: trustedModel.count === 0
                        Layout.fillWidth: true
                        text: qsTr("Aucun poste autorise pour l'instant.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Theme.spacingSmall
                        model: trustedModel

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 48
                            radius: Theme.radiusMedium
                            color: Theme.surfaceAlt

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingMedium
                                anchors.rightMargin: Theme.spacingMedium
                                spacing: Theme.spacingSmall

                                Label {
                                    text: fingerprint
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: qsTr("Revoquer")
                                    onClicked: {
                                        if (root.service) {
                                            root.service.revokePeer(fingerprint)
                                        }
                                        trustedModel.remove(index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
