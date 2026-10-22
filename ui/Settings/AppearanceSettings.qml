import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * AppearanceSettings - Parametres > Apparence (Ligne claire).
 *
 * Chaque choix ecrit une preference du singleton Theme (QSettings,
 * categorie "Appearance") et s'applique tout de suite a toute
 * l'application. « Rétablir l'apparence par défaut » peut etre annule
 * pendant quelques secondes.
 */
ColumnLayout {
    id: root
    spacing: 0

    readonly property bool isDefault: Theme.mode === "light" && Theme.accentName === "encre" && Math.abs(Theme.fontScale - 1.0) < 0.01
                                      && !Theme.compact && !Theme.sidebarCollapsed
    property var undoLook: null

    function resetLook() {
        root.undoLook = { mode: Theme.mode, accent: Theme.accentName, scale: Theme.fontScale,
                          density: Theme.density, rail: Theme.sidebarCollapsed }
        Theme.setMode("light")
        Theme.setAccent("encre")
        Theme.setFontScale(1.0)
        Theme.setDensity("comfortable")
        Theme.setSidebarCollapsed(false)
        undoTimer.restart()
    }
    function undoReset() {
        const u = root.undoLook
        if (!u) return
        Theme.setMode(u.mode)
        Theme.setAccent(u.accent)
        Theme.setFontScale(u.scale)
        Theme.setDensity(u.density)
        Theme.setSidebarCollapsed(u.rail)
        root.undoLook = null
    }
    Timer { id: undoTimer; interval: 8000; onTriggered: root.undoLook = null }

    // Vignette dessinee d'un theme (couleurs fixes de Papier et de Nuit,
    // independantes du theme affiche).
    component MiniPage: Rectangle {
        id: mp
        property bool night: false
        readonly property color ink: mp.night ? "#EEEAE1" : "#17161B"
        readonly property color sheet: mp.night ? "#151A25" : "#FBF9F4"
        readonly property color rule: mp.night ? "#272C37" : "#D9D4CB"
        color: mp.night ? "#0F131C" : "#F3EFE6"
        Rectangle { y: 13; width: parent.width; height: 1; color: mp.ink }
        Rectangle { x: 30; y: 13; width: 1; height: parent.height - 13; color: mp.ink }
        Rectangle { x: 5; y: 20; width: 20; height: 4; radius: 1; color: mp.ink; opacity: 0.7 }
        Rectangle { x: 5; y: 29; width: 16; height: 3; radius: 1; color: mp.ink; opacity: 0.3 }
        Rectangle { x: 5; y: 36; width: 18; height: 3; radius: 1; color: mp.ink; opacity: 0.3 }
        Rectangle { x: 37; y: 20; width: parent.width - 50; height: 7; radius: 1; color: mp.ink; opacity: 0.8 }
        Rectangle { x: 37; y: 33; width: parent.width - 44; height: 18; radius: 2; color: mp.sheet; border.width: 1; border.color: mp.rule }
        Rectangle { x: 37; y: 56; width: parent.width - 44; height: 18; radius: 2; color: mp.sheet; border.width: 1; border.color: mp.rule }
    }

    component ThemeCard: AbstractButton {
        id: tc
        property string mode: "light"
        readonly property bool selected: Theme.mode === tc.mode
        implicitWidth: 150
        implicitHeight: 84 + 30
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.role: Accessible.RadioButton
        Accessible.checked: tc.selected
        Accessible.name: tc.text
        onClicked: Theme.setMode(tc.mode)
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Item {}
        contentItem: Item {
            Item {
                id: thumb
                width: 150; height: 84
                clip: true
                MiniPage { anchors.fill: parent; night: tc.mode === "dark" }
                Item {
                    visible: tc.mode === "system"
                    x: 75; width: 75; height: 84
                    clip: true
                    MiniPage { x: -75; width: 150; height: 84; night: true }
                }
            }
            Rectangle {
                x: tc.selected ? -2 : 0; y: tc.selected ? -2 : 0
                width: thumb.width - 2 * x; height: thumb.height - 2 * y
                radius: Theme.radiusSheet
                color: "transparent"
                border.width: tc.selected ? 2 : 1
                border.color: tc.selected || tc.hovered ? Theme.ruleInk : Theme.lineStrong
            }
            Rectangle {
                x: -4; y: -4; width: thumb.width + 8; height: thumb.height + 8
                color: "transparent"; radius: Theme.radiusSheet
                border.width: tc.visualFocus ? 2 : 0; border.color: Theme.focusRing
            }
            Row {
                y: 84 + 8
                spacing: 7
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14; radius: 7
                    color: "transparent"
                    border.width: tc.selected ? 4.5 : 1.5
                    border.color: tc.selected ? Theme.ink : Theme.lineStrong
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tc.text
                    color: tc.selected ? Theme.ink : Theme.ink2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(13)
                    font.weight: tc.selected ? Theme.weightSemibold : Theme.weightMedium
                }
            }
        }
    }

    component AccentSwatch: AbstractButton {
        id: sw
        property string key: ""
        readonly property bool selected: Theme.accentName === sw.key
        readonly property color tint: Theme.accentPalettes[sw.key][Theme.darkMode ? "dark" : "light"][0]
        implicitWidth: 74
        implicitHeight: 64
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.role: Accessible.RadioButton
        Accessible.checked: sw.selected
        Accessible.name: Theme.accentPalettes[sw.key].label
        onClicked: Theme.setAccent(sw.key)
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            radius: Theme.radiusSheet
            color: sw.selected ? Theme.surface0 : sw.hovered ? Theme.hover : "transparent"
            border.width: sw.selected ? 1 : (sw.visualFocus ? 2 : 0)
            border.color: sw.visualFocus ? Theme.focusRing : Theme.lineStrong
        }
        contentItem: Item {
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 9
                width: 26; height: 26; radius: 13
                color: sw.tint
                LineIcon { anchors.centerIn: parent; visible: sw.selected; path: Icons.check; size: 14; strokeWidth: 2.6; color: Theme.darkMode ? "#10141D" : "#FFFFFF" }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 41
                text: Theme.accentPalettes[sw.key].label
                color: sw.selected ? Theme.ink : Theme.ink2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: sw.selected ? Theme.weightSemibold : Theme.weightRegular
            }
        }
    }

    // ---- Theme et couleur ---------------------------------------------------
    SettingGroup {
        first: true
        title: qsTr("Thème et couleur")
        scopeIcon: Icons.user
        scopeText: qsTr("<b>Vous</b>, sur ce poste · immédiat")

        SettingRow {
            label: qsTr("Thème")
            help: qsTr("Papier le jour, Nuit pour les écrans sombres. « Système » suit le réglage de Windows.")
            Flow {
                Layout.fillWidth: true
                spacing: 12
                ThemeCard { mode: "light"; text: qsTr("Papier") }
                ThemeCard { mode: "dark"; text: qsTr("Nuit") }
                ThemeCard { mode: "system"; text: qsTr("Système") }
            }
            Text {
                visible: Theme.mode === "system"
                Layout.fillWidth: true
                textFormat: Text.StyledText
                text: Theme.systemDark ? qsTr("Windows est en mode <b>sombre</b> : LocaLink affiche Nuit.")
                                       : qsTr("Windows est en mode <b>clair</b> : LocaLink affiche Papier.")
                wrapMode: Text.WordWrap
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
            }
        }
        SettingRow {
            label: qsTr("Couleur d'accent")
            help: qsTr("Pour les liens, la sélection et ce qui est en cours. Les états (en ligne, alerte, erreur) gardent leurs couleurs.")
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: Theme.accentKeys
                    delegate: AccentSwatch { required property string modelData; key: modelData }
                }
            }
        }
    }

    // ---- Lisibilite -----------------------------------------------------------
    SettingGroup {
        title: qsTr("Lisibilité")
        scopeIcon: Icons.user
        scopeText: qsTr("<b>Vous</b>, sur ce poste · immédiat")

        SettingRow {
            label: qsTr("Taille du texte")
            help: qsTr("Agrandit le texte de tous les écrans, sans redémarrer.")
            InkSegmented {
                options: [{ label: "90 %", value: 0.9 }, { label: "100 %", value: 1 }, { label: "110 %", value: 1.1 }, { label: "120 %", value: 1.2 }]
                current: {
                    const s = [0.9, 1, 1.1, 1.2]
                    let best = 1
                    for (let i = 0; i < s.length; i++) if (Math.abs(s[i] - Theme.fontScale) < 0.01) best = s[i]
                    return best
                }
                onPicked: function(v) { Theme.setFontScale(v) }
            }
        }
        SettingRow {
            label: qsTr("Densité")
            help: qsTr("Compacte resserre les lignes des listes pour en montrer davantage.")
            InkSegmented {
                options: [{ label: qsTr("Confortable"), value: "comfortable" }, { label: qsTr("Compacte"), value: "compact" }]
                current: Theme.density
                onPicked: function(v) { Theme.setDensity(v) }
            }
        }
        SettingRow {
            label: qsTr("Barre latérale")
            help: qsTr("Elle se réduit d'elle-même quand la fenêtre fait moins de 1 180 px de large.")
            InkSwitch {
                on: Theme.sidebarCollapsed
                text: Theme.sidebarCollapsed ? qsTr("Réduite aux icônes") : qsTr("Avec les libellés")
                onSwitched: function(v) { Theme.setSidebarCollapsed(v) }
            }
        }
    }

    // ---- Retablir ---------------------------------------------------------------
    Flow {
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.leftMargin: root.width >= 560 ? Math.max(180, Math.min(300, root.width * 0.3)) + (root.width > 900 ? 32 : 24) : 0
        spacing: 12
        TextLink {
            visible: root.undoLook === null
            enabled: !root.isDefault
            arrow: false
            text: qsTr("Rétablir l'apparence par défaut")
            onClicked: root.resetLook()
        }
        Text {
            visible: root.undoLook === null
            height: 24
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Papier, encre, 100 %, confortable.")
            color: Theme.ink3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12)
        }
        SavedNote { visible: root.undoLook !== null; height: 24; text: qsTr("Apparence par défaut rétablie") }
        TextLink { visible: root.undoLook !== null; arrow: false; text: qsTr("Annuler"); onClicked: root.undoReset() }
    }
}
