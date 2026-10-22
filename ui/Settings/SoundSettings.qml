import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * SoundSettings - Parametres > Notifications et sons (Ligne claire).
 *
 *   - Notifications Windows : settingsModel.enableNotifications, enregistre
 *     aussitot (save()) ; branche sur NotificationManager (main.cpp).
 *   - Sons, volume, son par evenement : audioService, qui enregistre
 *     lui-meme chaque reglage. Chaque option se choisit d'un clic et
 *     s'ecoute avec son propre bouton (previewSound joue cette variante-la,
 *     meme sons coupes).
 */
ColumnLayout {
    id: root
    spacing: 0

    readonly property var settings: (typeof settingsModel !== "undefined") ? settingsModel : null
    readonly property var audio: (typeof audioService !== "undefined") ? audioService : null
    readonly property bool soundOn: !!root.audio && root.audio.soundEnabled
    property string playing: ""              // "<type>:<variante>" pendant l'ecoute
    Timer { id: playingTimer; interval: 900; onTriggered: root.playing = "" }

    // type : valeurs de AudioService::EventType (0 Message, 1 Transfert, 2 Appel).
    readonly property var events: [
        { type: 0, label: qsTr("Message"), icon: Icons.messageCircle, prop: "messageSound",
          help: qsTr("Pour chaque message reçu hors de la conversation ouverte."),
          names: { soft: qsTr("Douce"), pop: qsTr("Pop"), bell: qsTr("Clochette") } },
        { type: 1, label: qsTr("Transfert"), icon: Icons.exchange, prop: "transferSound",
          help: qsTr("Quand un fichier vous est envoyé."),
          names: { rising: qsTr("Montant"), ding: qsTr("Ding"), done: qsTr("Terminé") } },
        { type: 2, label: qsTr("Appel"), icon: Icons.phone, prop: "callSound",
          help: qsTr("Sonne en boucle jusqu'à ce que vous répondiez ou refusiez."),
          names: { classic: qsTr("Classique"), soft: qsTr("Douce"), upbeat: qsTr("Rythmée") } }
    ]

    function preview(type, id) {
        if (!root.audio) return
        root.audio.previewSound(type, id)
        root.playing = type + ":" + id
        playingTimer.restart()
    }

    // Une option : choisir (clic sur le libelle) | ecouter (bouton ▶).
    component VariantChip: Rectangle {
        id: vc
        property int type: 0
        property string variant: ""
        property string label: ""
        property bool selected: false
        signal picked()
        readonly property bool isPlaying: root.playing === vc.type + ":" + vc.variant
        implicitWidth: pickBtn.implicitWidth + 33
        implicitHeight: 34
        radius: Theme.radiusSheet
        color: vc.selected ? Theme.surface0 : "transparent"
        border.width: vc.selected ? 1.5 : 1
        border.color: vc.selected ? Theme.ink : Theme.lineStrong

        AbstractButton {
            id: pickBtn
            height: parent.height
            implicitWidth: pickRow.implicitWidth + 21
            opacity: root.soundOn ? 1 : 0.45
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            Accessible.role: Accessible.RadioButton
            Accessible.checked: vc.selected
            Accessible.name: vc.label
            onClicked: vc.picked()
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            background: Rectangle { color: "transparent"; border.width: pickBtn.visualFocus ? 2 : 0; border.color: Theme.focusRing; radius: Theme.radiusSheet }
            contentItem: Item {
                Row {
                    id: pickRow
                    x: 11
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: 7
                        color: "transparent"
                        border.width: vc.selected ? 4.5 : 1.5
                        border.color: vc.selected ? Theme.ink : Theme.lineStrong
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: vc.label
                        color: vc.selected || pickBtn.hovered ? Theme.ink : Theme.ink2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        font.weight: vc.selected ? Theme.weightSemibold : Theme.weightRegular
                    }
                }
            }
        }
        AbstractButton {
            id: hearBtn
            x: pickBtn.width
            width: 32
            height: parent.height
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            Accessible.name: qsTr("Écouter %1").arg(vc.label)
            ToolTip.visible: hovered
            ToolTip.delay: 500
            ToolTip.text: qsTr("Écouter")
            onClicked: root.preview(vc.type, vc.variant)
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            background: Rectangle {
                color: hearBtn.hovered ? Theme.ink : "transparent"
                radius: Theme.radiusSheet
                border.width: hearBtn.visualFocus ? 2 : 0
                border.color: Theme.focusRing
                Rectangle { width: 1; height: parent.height; color: Theme.line }
            }
            contentItem: Item {
                LineIcon {
                    anchors.centerIn: parent
                    path: Icons.play
                    size: 13
                    strokeWidth: 1.8
                    color: hearBtn.hovered ? Theme.inkOnInk : vc.isPlaying ? Theme.navActiveInk : Theme.ink3
                }
            }
        }
    }

    // ---- Alertes --------------------------------------------------------------
    SettingGroup {
        first: true
        title: qsTr("Alertes")
        scopeIcon: Icons.user
        scopeText: qsTr("<b>Vous</b>, sur ce poste · immédiat")

        SettingRow {
            label: qsTr("Notifications Windows")
            help: qsTr("Une alerte pour les nouveaux messages, les fichiers reçus et les postes qui se connectent.")
            InkSwitch {
                on: !!root.settings && root.settings.enableNotifications
                text: on ? qsTr("Activées") : qsTr("Coupées")
                onSwitched: function(v) { if (root.settings) { root.settings.enableNotifications = v; root.settings.save() } }
            }
        }
    }

    // ---- Sons -------------------------------------------------------------------
    SettingGroup {
        title: qsTr("Sons")
        scopeIcon: Icons.user
        scopeText: qsTr("<b>Vous</b>, sur ce poste · immédiat")

        SettingRow {
            label: qsTr("Sons")
            help: root.soundOn ? qsTr("Joués pour les messages, les transferts et les appels.")
                               : qsTr("Coupés : aucun son ne sera joué. Vous pouvez quand même écouter chaque son ci-dessous.")
            InkSwitch {
                on: root.soundOn
                text: on ? qsTr("Activés") : qsTr("Coupés")
                onSwitched: function(v) { if (root.audio) root.audio.soundEnabled = v }
            }
        }
        SettingRow {
            label: qsTr("Volume")
            help: qsTr("Le même pour tous les sons de LocaLink.")
            dimmed: !root.soundOn
            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: 560
                spacing: 12
                opacity: root.soundOn ? 1 : 0.45
                enabled: root.soundOn
                LineIcon { path: volumeSlider.value > 0 ? Icons.volume : Icons.volumeOff; size: 16; strokeWidth: 1.7; color: Theme.ink3 }
                Slider {
                    id: volumeSlider
                    Layout.fillWidth: true
                    from: 0; to: 1; stepSize: 0.05
                    value: root.audio ? root.audio.volume : 1
                    Accessible.name: qsTr("Volume")
                    onMoved: if (root.audio) root.audio.volume = value
                    background: Rectangle {
                        x: volumeSlider.leftPadding
                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                        width: volumeSlider.availableWidth
                        height: 2
                        color: Theme.lineStrong
                        Rectangle { width: volumeSlider.visualPosition * parent.width; height: 2; color: Theme.ink }
                    }
                    handle: Rectangle {
                        x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                        y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                        width: 14; height: 14; radius: 7
                        color: Theme.ink
                        border.width: volumeSlider.visualFocus ? 2 : 0
                        border.color: Theme.focusRing
                    }
                }
                Text {
                    Layout.preferredWidth: 48
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(volumeSlider.value * 100) + " %"
                    color: Theme.ink
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: Theme.fs(16)
                    font.weight: Theme.weightBold
                    font.features: ({ "tnum": 1 })
                }
            }
        }
        Repeater {
            model: root.events
            delegate: SettingRow {
                id: evRow
                required property var modelData
                label: evRow.modelData.label
                labelIcon: evRow.modelData.icon
                help: evRow.modelData.help
                dimmed: !root.soundOn
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: root.audio ? root.audio.soundVariants(evRow.modelData.type) : []
                        delegate: VariantChip {
                            required property string modelData
                            type: evRow.modelData.type
                            variant: modelData
                            label: evRow.modelData.names[modelData] || modelData
                            selected: !!root.audio && root.audio[evRow.modelData.prop] === modelData
                            onPicked: {
                                if (!root.audio) return
                                root.audio[evRow.modelData.prop] = modelData
                                root.preview(evRow.modelData.type, modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
