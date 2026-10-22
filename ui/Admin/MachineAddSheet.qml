import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * MachineAddSheet - « Ajouter une machine » en Ligne claire.
 *
 * Chemin court : un poste visible sur le reseau mais pas encore enregistre
 * (discoveryService.machineCandidates()) ; son empreinte s'affiche en grand
 * pour etre comparee avec celle du poste. Sinon, saisie manuelle (empreinte
 * et identifiant obligatoires, nom et adresse facultatifs).
 * Enregistre par authorizedMachineModel.addMachineByCertificate().
 */
SheetModal {
    id: root

    property var registered: []           // machines deja enregistrees (AdminView.machines)
    property var candidates: []
    property int pick: 0
    property bool manual: false
    property string errorText: ""

    signal added(string name)

    kicker: qsTr("Ajouter une machine")
    title: root.manual ? qsTr("Saisie manuelle") : qsTr("Autoriser un poste du réseau")
    sheetWidth: 520
    onCloseRequested: root.open = false

    function reload() {
        const all = (typeof discoveryService !== "undefined" && discoveryService && discoveryService.machineCandidates)
                    ? (discoveryService.machineCandidates() || []) : []
        const clean = function(f) { return String(f || "").replace(/[^0-9a-fA-F]/g, "").toUpperCase() }
        root.candidates = all.filter(function(c) {
            for (let i = 0; i < root.registered.length; i++) {
                const m = root.registered[i]
                if ((c.id && c.id === m.machineId) || (c.fingerprint && clean(c.fingerprint) === clean(m.fingerprint)))
                    return false
            }
            return true
        })
        root.pick = 0
        root.manual = root.candidates.length === 0
        root.errorText = ""
        fpField.text = ""; idField.text = ""; nameField.text = ""; ipField.text = ""
    }
    onOpenChanged: if (open) root.reload()

    readonly property var current: root.candidates.length > root.pick ? root.candidates[root.pick] : null
    readonly property string cleanFp: fpField.text.replace(/[^0-9a-fA-F]/g, "")

    function submit() {
        if (typeof authorizedMachineModel === "undefined" || !authorizedMachineModel) return
        let ok = false, name = ""
        if (root.manual) {
            name = nameField.text.trim() || ipField.text.trim() || idField.text.trim()
            ok = authorizedMachineModel.addMachineByCertificate(root.cleanFp.toUpperCase(), idField.text.trim(),
                                                               ipField.text.trim(), nameField.text.trim(), "Ajouté par admin")
        } else if (root.current) {
            name = root.current.name || root.current.ip
            ok = authorizedMachineModel.addMachineByCertificate(root.current.fingerprint || "", root.current.id || "",
                                                               root.current.ip || "", root.current.name || "", "Ajouté par admin")
        }
        if (ok) {
            root.open = false
            root.added(name)
        } else {
            root.errorText = qsTr("La machine n'a pas été ajoutée. Vérifiez l'empreinte puis réessayez.")
        }
    }

    component PickRow: AbstractButton {
        id: pr
        property var c: null
        property bool current: false
        property bool first: false
        Layout.fillWidth: true
        implicitHeight: 54
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.role: Accessible.RadioButton
        Accessible.name: pr.c ? pr.c.name + ", " + pr.c.ip : ""
        Accessible.checked: pr.current
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            color: pr.current ? Theme.surface0 : pr.hovered ? Theme.selectWash : "transparent"
            Rectangle { visible: !pr.first; width: parent.width; height: 1; color: Theme.line }
            Rectangle { visible: pr.current; width: 3; height: parent.height; color: Theme.ruleInk }
            Rectangle { anchors.fill: parent; color: "transparent"; border.width: pr.visualFocus ? 2 : 0; border.color: Theme.focusRing }
        }
        contentItem: RowLayout {
            spacing: 10
            Rectangle {
                Layout.leftMargin: 12
                implicitWidth: 16; implicitHeight: 16; radius: 8
                color: "transparent"
                border.width: pr.current ? 5 : 1.5
                border.color: pr.current ? Theme.ink : Theme.lineStrong
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { text: pr.c ? pr.c.name || pr.c.ip : ""; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold }
                Text { Layout.fillWidth: true; text: pr.c ? pr.c.ip + (pr.c.id ? " · " + pr.c.id : "") : ""; color: Theme.ink3; font.family: "Cascadia Mono"; font.pixelSize: Theme.fs(11.5); elide: Text.ElideRight }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        // -- Postes detectes ----------------------------------------------------
        Text {
            visible: !root.manual
            Layout.fillWidth: true
            text: qsTr("Ces postes lancent LocaLink sur le réseau local mais ne sont pas encore enregistrés.")
            color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); wrapMode: Text.WordWrap
        }
        Text { visible: !root.manual; text: qsTr("Postes détectés"); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
        Rectangle {
            visible: !root.manual
            Layout.fillWidth: true
            implicitHeight: pickCol.implicitHeight + 2
            radius: Theme.radiusSheet
            color: "transparent"
            border.width: 1
            border.color: Theme.lineStrong
            clip: true
            ColumnLayout {
                id: pickCol
                x: 1; y: 1
                width: parent.width - 2
                spacing: 0
                Repeater {
                    model: root.candidates
                    delegate: PickRow {
                        required property var modelData
                        required property int index
                        c: modelData
                        first: index === 0
                        current: index === root.pick
                        onClicked: root.pick = index
                    }
                }
            }
        }
        Text {
            visible: !root.manual && root.current !== null
            Layout.topMargin: 4
            text: qsTr("Empreinte de %1").arg(root.current ? (root.current.name || root.current.ip) : "")
            color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold
        }
        FingerprintGrid {
            visible: !root.manual && root.current !== null
            Layout.fillWidth: true
            large: true
            fingerprint: root.current ? root.current.fingerprint || "" : ""
        }
        Text {
            visible: !root.manual
            Layout.fillWidth: true
            text: qsTr("Comparez-la avec l'empreinte affichée sur le poste avant d'autoriser.")
            color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
        }
        TextLink {
            visible: !root.manual
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            arrow: false
            text: qsTr("Saisir l'empreinte à la main")
            onClicked: { root.manual = true; root.errorText = ""; fpField.field.forceActiveFocus() }
        }

        // -- Saisie manuelle -----------------------------------------------------
        Text {
            visible: root.manual
            Layout.fillWidth: true
            text: root.candidates.length === 0
                  ? qsTr("Aucun poste non enregistré n'est visible sur le réseau en ce moment. L'empreinte et l'identifiant sont affichés sur le poste lui-même.")
                  : qsTr("Pour un poste qui n'est pas visible en ce moment. L'empreinte et l'identifiant sont affichés sur le poste lui-même.")
            color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); wrapMode: Text.WordWrap
        }
        SheetField {
            id: fpField
            visible: root.manual
            label: qsTr("Empreinte SHA-256 du certificat")
            mono: true
            placeholderText: qsTr("64 caractères hexadécimaux")
            hint: root.cleanFp.length > 0 && root.cleanFp.length !== 64
                  ? qsTr("%1 caractères sur 64 ; espaces et deux-points acceptés.").arg(root.cleanFp.length)
                  : qsTr("64 caractères ; espaces et deux-points acceptés.")
        }
        SheetField { id: idField; visible: root.manual; label: qsTr("Identifiant de la machine"); mono: true; placeholderText: qsTr("identifiant annoncé par le poste") }
        RowLayout {
            visible: root.manual
            Layout.fillWidth: true
            spacing: 12
            SheetField { id: nameField; label: qsTr("Nom"); optional: qsTr("facultatif"); placeholderText: "PC-…" }
            SheetField { id: ipField; label: qsTr("Adresse"); optional: qsTr("facultatif"); mono: true; placeholderText: "192.168.1.x" }
        }
        Text {
            visible: root.manual
            Layout.fillWidth: true
            text: qsTr("Le nom et l'adresse servent seulement à retrouver ce poste dans la liste.")
            color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
        }
        Text {
            visible: root.errorText.length > 0
            Layout.fillWidth: true
            text: root.errorText
            color: Theme.dangerInk; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold; wrapMode: Text.WordWrap
        }
    }

    footer: [
        AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.open = false },
        AppButton {
            visible: root.manual && root.candidates.length > 0
            variant: "line"
            text: qsTr("Retour")
            onClicked: { root.manual = false; root.errorText = "" }
        },
        AppButton {
            variant: "ink"
            iconPath: Icons.check
            text: root.manual ? qsTr("Autoriser la machine")
                              : qsTr("Autoriser %1").arg(root.current ? (root.current.name || root.current.ip) : "")
            enabled: root.manual ? (root.cleanFp.length === 64 && idField.text.trim().length > 0) : root.current !== null
            onClicked: root.submit()
        }
    ]
}
