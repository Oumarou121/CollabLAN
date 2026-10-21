import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * FolderExclusionsSheet - « Fichiers à ne pas partager » : motifs glob en
 * puces (Entree ou virgule pour ajouter), apercu des fichiers deja partages
 * qui seront retires (previewExcludePatternsImpact), rappel des exclusions
 * par defaut. Local a ce poste.
 */
SheetModal {
    id: root

    property var context: null
    property var folderId: -1
    property string folderName: ""
    property var patterns: []
    property var impacted: []

    signal saved()

    kicker: qsTr("Exclusions · %1").arg(root.folderName.replace(/&/g, "&amp;").replace(/</g, "&lt;"))
    title: qsTr("Fichiers à ne pas partager")
    lead: qsTr("Motifs de noms, par exemple *.log, node_modules ou Brouillons/*. Ils ne valent que pour ce poste.")
    sheetWidth: 540

    onOpenChanged: {
        if (!open) return
        const current = root.context && root.folderId >= 0 ? root.context.excludePatternsForFolder(root.folderId) : ""
        root.patterns = current.split(",").map(function(p) { return p.trim() }).filter(function(p) { return p.length > 0 })
        root.impacted = []
        field.text = ""
    }

    function addPattern(raw) {
        const v = (raw || "").trim()
        if (v.length === 0 || root.patterns.indexOf(v) !== -1) return
        root.patterns = root.patterns.concat([v])
        previewTimer.restart()
    }
    function removePattern(v) {
        root.patterns = root.patterns.filter(function(p) { return p !== v })
        previewTimer.restart()
    }
    Timer {
        id: previewTimer
        interval: 250
        onTriggered: root.impacted = (root.context && root.folderId >= 0)
                     ? root.context.previewExcludePatternsImpact(root.folderId, root.patterns.join(",")) : []
    }

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool removable: true
        signal removeRequested()
        implicitWidth: chipRow.implicitWidth + (removable ? 12 : 20)
        implicitHeight: 26
        radius: 13
        color: "transparent"
        border.width: 1
        border.color: chip.removable ? Theme.lineStrong : Theme.line
        Row {
            id: chipRow
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: chip.removable ? Theme.ink : Theme.ink3
                font.family: chip.removable ? "Cascadia Mono" : Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: chip.removable ? Theme.weightMedium : Theme.weightRegular
            }
            AbstractButton {
                id: x
                visible: chip.removable
                width: 18; height: 18
                hoverEnabled: true
                Accessible.name: qsTr("Retirer %1").arg(chip.label)
                onClicked: chip.removeRequested()
                background: Rectangle { radius: 9; color: x.hovered ? Theme.selectWash : "transparent" }
                contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.close; size: 11; strokeWidth: 2.2; color: Theme.ink3 } }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text { Layout.bottomMargin: 6; text: qsTr("Motifs de ce dossier"); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightSemibold }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            radius: Theme.radiusSheet
            color: Theme.surface0
            border.width: field.activeFocus ? 1.5 : 1
            border.color: field.activeFocus ? Theme.ink : Theme.lineStrong
            TextField {
                id: field
                anchors.fill: parent
                leftPadding: 12
                rightPadding: 12
                placeholderText: qsTr("Tapez un motif puis Entrée…")
                placeholderTextColor: Theme.ink3
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13.5)
                background: Item {}
                selectByMouse: true
                onAccepted: { root.addPattern(text); text = "" }
                // Une virgule tapee cree directement une puce.
                onTextChanged: {
                    if (text.indexOf(",") === -1) return
                    const parts = text.split(",")
                    for (let i = 0; i < parts.length - 1; i++) root.addPattern(parts[i])
                    text = parts[parts.length - 1]
                }
            }
        }
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 6
            visible: root.patterns.length > 0
            Repeater {
                model: root.patterns
                delegate: Chip {
                    required property var modelData
                    label: modelData
                    onRemoveRequested: root.removePattern(modelData)
                }
            }
        }
        Text {
            visible: root.patterns.length === 0
            Layout.topMargin: 10
            text: qsTr("Aucun motif pour ce dossier : tout son contenu est partagé.")
            color: Theme.ink3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12.5)
        }

        // Effet a l'enregistrement
        Rectangle {
            visible: root.impacted.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 14
            implicitHeight: impactCol.implicitHeight + 20
            color: Theme.warningSoft
            Rectangle { width: 2; height: parent.height; color: Theme.warningColor }
            ColumnLayout {
                id: impactCol
                x: 14
                y: 10
                width: parent.width - 26
                spacing: 4
                CapsLabel { text: qsTr("À l'enregistrement"); color: Theme.warningInk }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.impacted.length > 1
                          ? qsTr("%1 fichiers déjà partagés seront retirés du partage (ils restent sur ce disque) :").arg(root.impacted.length)
                          : qsTr("1 fichier déjà partagé sera retiré du partage (il reste sur ce disque) :")
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                }
                Repeater {
                    model: root.impacted.slice(0, 5)
                    delegate: Text {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData
                        color: Theme.ink2
                        font.family: "Cascadia Mono"
                        font.pixelSize: Theme.fs(12)
                        elide: Text.ElideMiddle
                    }
                }
                Text {
                    visible: root.impacted.length > 5
                    text: qsTr("et %1 autre(s)").arg(root.impacted.length - 5)
                    color: Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: 16; Layout.bottomMargin: 14; Layout.preferredHeight: 1; color: Theme.line }
        Text { Layout.bottomMargin: 8; text: qsTr("Toujours exclus"); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightSemibold }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Chip { label: qsTr("dossiers système"); removable: false }
            Chip { label: qsTr("fichiers temporaires"); removable: false }
        }
    }

    footer: [
        AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.closeRequested() },
        AppButton {
            variant: "ink"
            text: qsTr("Enregistrer")
            onClicked: {
                if (field.text.trim().length > 0) { root.addPattern(field.text); field.text = "" }
                if (root.context && root.folderId >= 0 && root.context.updateExcludePatterns(root.folderId, root.patterns.join(",")))
                    root.saved()
            }
        }
    ]
}
