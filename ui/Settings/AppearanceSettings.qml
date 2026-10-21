import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * AppearanceSettings - Parametres > Apparence.
 *
 * Chaque reglage ecrit une preference du singleton Theme (persistee dans
 * QSettings, categorie "Appearance") et s'applique immediatement a toute
 * l'application : aucun redemarrage.
 */
ColumnLayout {
    id: root
    spacing: Theme.spacingLarge

    // ---- Theme ------------------------------------------------------------
    SettingsSectionCard {
        Layout.fillWidth: true
        icon: ""
        title: qsTr("Thème")
        subtitle: qsTr("Choisissez l'apparence de LocaLink. « Système » suit le réglage de Windows.")

        AppSegmentedControl {
            Layout.fillWidth: true
            model: [
                { label: qsTr("Clair"), glyph: "" },
                { label: qsTr("Sombre"), glyph: "" },
                { label: qsTr("Système"), glyph: "" }
            ]
            currentIndex: ["light", "dark", "system"].indexOf(Theme.mode)
            onActivated: function(index) { Theme.setMode(["light", "dark", "system"][index]) }
        }

        Text {
            visible: Theme.mode === "system"
            Layout.fillWidth: true
            text: Theme.systemDark ? qsTr("Windows est actuellement en mode sombre.")
                                   : qsTr("Windows est actuellement en mode clair.")
            color: Theme.ink3
            font.pixelSize: Theme.fs(12)
            font.family: Theme.fontFamily
        }
    }

    // ---- Couleur d'accent ---------------------------------------------------
    SettingsSectionCard {
        Layout.fillWidth: true
        icon: ""
        title: qsTr("Couleur d'accent")
        subtitle: qsTr("Utilisée pour les actions principales, la sélection et la navigation active. Toutes respectent les contrastes d'accessibilité.")

        Flow {
            Layout.fillWidth: true
            spacing: 12

            Repeater {
                model: Theme.accentKeys

                delegate: AbstractButton {
                    id: swatch
                    required property string modelData
                    readonly property bool selected: Theme.accentName === swatch.modelData
                    readonly property var swatchColors: Theme.accentPalettes[swatch.modelData][Theme.darkMode ? "dark" : "light"]

                    width: 108
                    height: 84
                    hoverEnabled: true
                    focusPolicy: Qt.TabFocus
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: Theme.accentPalettes[swatch.modelData].label
                    Accessible.checked: swatch.selected
                    onClicked: Theme.setAccent(swatch.modelData)

                    HoverHandler { cursorShape: Qt.PointingHandCursor }

                    background: Rectangle {
                        radius: Theme.radiusMedium
                        color: swatch.selected ? Theme.surface1 : (swatch.hovered ? Theme.hover : "transparent")
                        border.width: swatch.selected ? 2 : 1
                        border.color: swatch.selected ? swatch.swatchColors[0] : Theme.line

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: parent.radius + 3
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.focusRing
                            visible: swatch.visualFocus
                        }
                    }

                    contentItem: ColumnLayout {
                        spacing: 8

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: 15
                            color: swatch.swatchColors[0]

                            FaIcon {
                                anchors.centerIn: parent
                                visible: swatch.selected
                                glyph: ""
                                color: Theme.accentInk
                                font.pixelSize: Theme.fs(13)
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: Theme.accentPalettes[swatch.modelData].label
                            color: swatch.selected ? Theme.ink : Theme.ink2
                            font.pixelSize: Theme.fs(12)
                            font.weight: swatch.selected ? Theme.weightSemibold : Theme.weightRegular
                            font.family: Theme.fontFamily
                        }
                    }
                }
            }
        }
    }

    // ---- Lisibilite -----------------------------------------------------------
    SettingsSectionCard {
        Layout.fillWidth: true
        icon: ""
        title: qsTr("Lisibilité")
        subtitle: qsTr("Taille du texte et densité de l'interface, appliquées à tous les écrans.")

        Text {
            text: qsTr("Taille du texte")
            color: Theme.ink2
            font.pixelSize: Theme.fs(12)
            font.weight: Theme.weightSemibold
            font.family: Theme.fontFamily
        }

        AppSegmentedControl {
            Layout.fillWidth: true
            readonly property var scales: [0.9, 1.0, 1.1, 1.2]
            model: [ { label: "90 %" }, { label: qsTr("100 % (par défaut)") }, { label: "110 %" }, { label: "120 %" } ]
            currentIndex: {
                let best = 1
                for (let i = 0; i < scales.length; i++)
                    if (Math.abs(scales[i] - Theme.fontScale) < 0.01) best = i
                return best
            }
            onActivated: function(index) { Theme.setFontScale(scales[index]) }
        }

        // Apercu en direct.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: previewColumn.implicitHeight + 24
            radius: Theme.radiusControl
            color: Theme.surface1
            border.width: 1
            border.color: Theme.line

            ColumnLayout {
                id: previewColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4

                Text {
                    text: qsTr("Aperçu — Transferts récents")
                    color: Theme.ink
                    font.pixelSize: Theme.fontSizeCardTitle
                    font.weight: Theme.weightSemibold
                    font.family: Theme.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Bilan_2026_T3.xlsx envoyé à PC-COMPTA-01 · 48 Mo · il y a 2 min")
                    color: Theme.ink2
                    font.pixelSize: Theme.fontSizeBody
                    font.family: Theme.fontFamily
                    wrapMode: Text.WordWrap
                }
            }
        }

        Text {
            Layout.topMargin: 6
            text: qsTr("Densité")
            color: Theme.ink2
            font.pixelSize: Theme.fs(12)
            font.weight: Theme.weightSemibold
            font.family: Theme.fontFamily
        }

        AppSegmentedControl {
            Layout.fillWidth: true
            model: [ { label: qsTr("Confortable"), glyph: "" },
                     { label: qsTr("Compacte"), glyph: "" } ]
            currentIndex: Theme.compact ? 1 : 0
            onActivated: function(index) { Theme.setDensity(index === 1 ? "compact" : "comfortable") }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("La densité compacte réduit les marges et la hauteur des lignes pour afficher davantage d'éléments à l'écran.")
            color: Theme.ink3
            font.pixelSize: Theme.fs(12)
            font.family: Theme.fontFamily
            wrapMode: Text.WordWrap
        }
    }

    // ---- Navigation -------------------------------------------------------------
    SettingsSectionCard {
        Layout.fillWidth: true
        icon: ""
        title: qsTr("Navigation")

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMedium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: qsTr("Réduire la barre latérale")
                    color: Theme.ink
                    font.pixelSize: Theme.fs(14)
                    font.family: Theme.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("N'affiche que les icônes pour laisser plus de place au contenu. Elle se réduit aussi automatiquement sur les fenêtres étroites.")
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                    wrapMode: Text.WordWrap
                }
            }

            AppSwitch {
                checked: Theme.sidebarCollapsed
                Accessible.name: qsTr("Réduire la barre latérale")
                onToggled: Theme.setSidebarCollapsed(checked)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Item { Layout.fillWidth: true }

        AppButton {
            text: qsTr("Rétablir l'apparence par défaut")
            iconGlyph: ""
            variant: "ghost"
            enabled: Theme.mode !== "light" || Theme.accentName !== "blue" || Math.abs(Theme.fontScale - 1.0) > 0.01
                     || Theme.compact || Theme.sidebarCollapsed
            onClicked: {
                Theme.setMode("light")
                Theme.setAccent("blue")
                Theme.setFontScale(1.0)
                Theme.setDensity("comfortable")
                Theme.setSidebarCollapsed(false)
            }
        }
    }
}
