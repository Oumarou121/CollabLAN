import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * SettingsView - reglages de l'election de serveur temporaire
 * (HYBRID_SERVER_FAILOVER.md section 9, etape 5) :
 *   - priority_weight : quel poste doit devenir TEMP_SERVER en priorite
 *     en cas de panne (plus petit = plus prioritaire).
 *   - delai de timeout heartbeat avant declenchement d'une election.
 *
 * Se branche sur "electionService" (network::ElectionService, expose
 * globalement depuis app/main.cpp) pour l'affichage temps reel, et passe
 * par application.setElectionPriorityWeight() pour persister priority_weight
 * en base (electionService seul ne persiste rien, cf. Application.cpp).
 */
Item {
    id: root

    property var election: (typeof electionService !== "undefined") ? electionService : null
    property var app: (typeof application !== "undefined") ? application : null

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingLarge

        Label {
            text: qsTr("Paramètres")
            color: Theme.text
            font.pixelSize: Theme.fontSizeTitle
            font.bold: true
        }

        // --- Etat courant (lecture seule, temps reel) -------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: statusColumn.implicitHeight + Theme.spacingMedium * 2
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            visible: root.election !== null

            ColumnLayout {
                id: statusColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Label {
                    text: qsTr("Bascule automatique")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                }

                RowLayout {
                    spacing: Theme.spacingSmall
                    Label { text: qsTr("Rôle actuel :"); color: Theme.textSecondary }
                    Label {
                        text: root.election ? root.election.roleLabel : ""
                        color: Theme.text
                        font.bold: true
                    }
                }
                RowLayout {
                    spacing: Theme.spacingSmall
                    Label { text: qsTr("Epoch :"); color: Theme.textSecondary }
                    Label { text: root.election ? root.election.epoch : ""; color: Theme.text }
                }
                RowLayout {
                    spacing: Theme.spacingSmall
                    Label { text: qsTr("Serveur actif :"); color: Theme.textSecondary }
                    Label {
                        text: (root.election && root.election.activeServerUuid.length > 0)
                              ? root.election.activeServerUuid : qsTr("inconnu")
                        color: Theme.text
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: 260
                    }
                }
            }
        }

        // --- Reglages ------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: settingsColumn.implicitHeight + Theme.spacingMedium * 2
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
            visible: root.election !== null

            ColumnLayout {
                id: settingsColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingMedium

                Label {
                    text: qsTr("Priorité de secours")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                }
                Label {
                    text: qsTr("Plus la valeur est basse, plus ce poste sera choisi en priorité pour prendre le relais en cas de panne du serveur.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: Theme.spacingMedium

                    SpinBox {
                        id: priorityWeightSpin
                        from: 1
                        to: 1000
                        stepSize: 10
                        editable: true
                        value: root.election ? root.election.priorityWeight : 100

                        // On evite d'ecraser la saisie de l'utilisateur par
                        // le binding temps reel : la valeur n'est
                        // resynchronisee sur electionService.priorityWeight
                        // que quand ce dernier change ailleurs (ex. un autre
                        // poste admin a modifie le reglage).
                        Connections {
                            target: root.election
                            function onPriorityWeightChanged() {
                                if (root.election)
                                    priorityWeightSpin.value = root.election.priorityWeight
                            }
                        }
                    }

                    Button {
                        text: qsTr("Appliquer")
                        Layout.preferredHeight: 32

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: parent.hovered ? Theme.primaryHover : Theme.primary
                        }
                        contentItem: Text {
                            text: qsTr("Appliquer")
                            color: Theme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            if (root.app)
                                root.app.setElectionPriorityWeight(priorityWeightSpin.value)
                        }
                    }
                }

                Label {
                    text: qsTr("Délai avant bascule")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                }
                Label {
                    text: qsTr("Temps sans nouvelle du serveur avant qu'un poste de secours prenne le relais.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: Theme.spacingMedium

                    SpinBox {
                        id: timeoutSecondsSpin
                        from: 5
                        to: 300
                        stepSize: 5
                        editable: true
                        value: root.election ? Math.round(root.election.heartbeatTimeoutMs / 1000) : 15

                        Connections {
                            target: root.election
                            function onHeartbeatTimeoutMsChanged() {
                                if (root.election)
                                    timeoutSecondsSpin.value = Math.round(root.election.heartbeatTimeoutMs / 1000)
                            }
                        }
                    }
                    Label { text: qsTr("secondes"); color: Theme.textSecondary }

                    Button {
                        text: qsTr("Appliquer")
                        Layout.preferredHeight: 32

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: parent.hovered ? Theme.surfaceAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                        }
                        contentItem: Text {
                            text: qsTr("Appliquer")
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            if (root.election)
                                root.election.heartbeatTimeoutMs = timeoutSecondsSpin.value * 1000
                        }
                    }
                }
            }
        }

        Label {
            visible: root.election === null
            text: qsTr("Service d'élection indisponible.")
            color: Theme.textSecondary
        }

        // --- Sons et notifications -------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: audioColumn.implicitHeight + Theme.spacingMedium * 2
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                id: audioColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingMedium

                Label {
                    text: qsTr("Sons & notifications")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                }

                // --- Activation globale des sons ---
                RowLayout {
                    spacing: Theme.spacingMedium
                    Label {
                        text: qsTr("Sons activés")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true
                    }
                    Switch {
                        id: soundSwitch
                        checked: (typeof audioService !== "undefined") && audioService.soundEnabled
                        onCheckedChanged: {
                            if (typeof audioService !== "undefined")
                                audioService.soundEnabled = checked
                        }
                        // Resynchronise si le backend change la valeur depuis le C++.
                        Connections {
                            target: (typeof audioService !== "undefined") ? audioService : null
                            function onSoundEnabledChanged() {
                                if (typeof audioService !== "undefined")
                                    soundSwitch.checked = audioService.soundEnabled
                            }
                        }
                    }
                }

                // --- Volume -----------------------------------------------
                ColumnLayout {
                    enabled: soundSwitch.checked
                    opacity: soundSwitch.checked ? 1.0 : 0.4
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    RowLayout {
                        spacing: Theme.spacingSmall
                        Label {
                            text: qsTr("Volume")
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: Math.round(volumeSlider.value * 100) + " %"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    Slider {
                        id: volumeSlider
                        from: 0.0
                        to: 1.0
                        stepSize: 0.05
                        value: (typeof audioService !== "undefined") ? audioService.volume : 1.0
                        Layout.fillWidth: true

                        onMoved: {
                            if (typeof audioService !== "undefined")
                                audioService.volume = value
                        }

                        Connections {
                            target: (typeof audioService !== "undefined") ? audioService : null
                            function onVolumeChanged() {
                                if (typeof audioService !== "undefined"
                                        && Math.abs(volumeSlider.value - audioService.volume) > 0.01)
                                    volumeSlider.value = audioService.volume
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
