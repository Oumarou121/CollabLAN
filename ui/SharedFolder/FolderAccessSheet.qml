import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * FolderAccessSheet - « Qui peut ouvrir… » : membres d'un dossier partage
 * par ce poste, droit de chacun (Consulte / Modifie), retrait avec
 * confirmation dans la ligne, ajout d'une personne avec son droit.
 * Chaque changement s'applique tout de suite (grantAccess, changePermission,
 * revokeAccess) ; `accessChanged` previent l'ecran hote.
 */
SheetModal {
    id: root

    property var context: null
    property var folderId: -1
    property string folderName: ""

    property var grants: []                 // [{ userId, username, permission }]
    property var candidates: []             // [{ userId, username }]
    property var pendingRevokeId: -1
    property int pickedIndex: -1
    property bool addWrite: true

    signal accessChanged()

    kicker: qsTr("Accès")
    boldTitle: false
    title: qsTr("Qui peut ouvrir <b>« %1 »</b>").arg(root.folderName.replace(/&/g, "&amp;").replace(/</g, "&lt;"))
    lead: qsTr("Les membres reçoivent le dossier sur leur poste. « Modifie » : leurs changements reviennent chez tous ; « Consulte » : lecture seule.")
    footNote: qsTr("Chaque changement s'applique tout de suite.")
    sheetWidth: 600

    onOpenChanged: if (open) reload()

    function reload() {
        root.pendingRevokeId = -1
        root.pickedIndex = -1
        if (!root.context || root.folderId < 0) {
            root.grants = []
            root.candidates = []
            return
        }
        root.grants = root.context.accessForFolder(root.folderId)
        const granted = {}
        for (let i = 0; i < root.grants.length; i++) granted[root.grants[i].userId] = true
        root.candidates = root.context.availableUsers().filter(function(u) { return !granted[u.userId] })
        // Un ComboBox remet son index a 0 quand son modele change.
        Qt.callLater(function() { picker.currentIndex = -1 })
    }
    function initials(label) {
        const w = (label || "?").split(/\s+/).filter(function(x) { return x.length > 0 })
        return ((w[0] || "?").charAt(0) + (w.length > 1 ? w[1].charAt(0) : "")).toUpperCase()
    }

    // Bascule Consulte | Modifie d'un seul tenant.
    component PermissionSwitch: Rectangle {
        id: ps
        property bool write: false
        signal picked(bool write)
        implicitWidth: psRow.implicitWidth + 2
        implicitHeight: 30
        radius: Theme.radiusSheet
        color: "transparent"
        border.width: 1
        border.color: Theme.lineStrong
        Row {
            id: psRow
            x: 1; y: 1
            Repeater {
                model: [{ w: false, t: qsTr("Consulte"), i: Icons.eye }, { w: true, t: qsTr("Modifie"), i: Icons.pencil }]
                delegate: AbstractButton {
                    id: pb
                    required property var modelData
                    required property int index
                    readonly property bool on: pb.modelData.w === ps.write
                    implicitHeight: 28
                    implicitWidth: pbRow.implicitWidth + 20
                    hoverEnabled: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: pb.on
                    Accessible.name: pb.modelData.t
                    onClicked: if (!pb.on) ps.picked(pb.modelData.w)
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    background: Rectangle {
                        color: pb.on ? Theme.ink : (pb.hovered ? Theme.selectWash : "transparent")
                        Rectangle { visible: pb.index > 0; width: 1; height: parent.height; color: Theme.lineStrong }
                    }
                    contentItem: Item {
                        Row {
                            id: pbRow
                            anchors.centerIn: parent
                            spacing: 5
                            LineIcon { anchors.verticalCenter: parent.verticalCenter; path: pb.modelData.i; size: 13; strokeWidth: 1.8; color: pb.on ? Theme.inkOnInk : Theme.ink2 }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: pb.modelData.t; color: pb.on ? Theme.inkOnInk : Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightSemibold }
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text {
            Layout.bottomMargin: 6
            text: root.grants.length > 1 ? qsTr("%1 membres").arg(root.grants.length)
                  : root.grants.length === 1 ? qsTr("1 membre") : qsTr("Aucun membre")
            color: Theme.ink2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12)
            font.weight: Theme.weightSemibold
        }
        Text {
            visible: root.grants.length === 0
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            text: qsTr("Ce dossier n'est partagé avec personne pour l'instant.")
            color: Theme.ink3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12.5)
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.grants
            delegate: ColumnLayout {
                id: g
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 0
                Rectangle { visible: g.index > 0; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    spacing: 12
                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: 15
                        color: Theme.ink
                        Text { anchors.centerIn: parent; text: root.initials(g.modelData.username); color: Theme.inkOnInk; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(11); font.weight: Theme.weightBold }
                    }
                    Text { Layout.fillWidth: true; text: g.modelData.username; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13.5); font.weight: Theme.weightSemibold; elide: Text.ElideRight }
                    PermissionSwitch {
                        write: g.modelData.permission === "Write"
                        onPicked: function(write) {
                            if (root.context && root.context.changePermission(root.folderId, g.modelData.userId, write)) {
                                root.reload()
                                root.accessChanged()
                            }
                        }
                    }
                    TextLink {
                        text: qsTr("Retirer")
                        arrow: false
                        fontSize: Theme.fs(12.5)
                        onClicked: root.pendingRevokeId = g.modelData.userId
                    }
                }
                // Confirmation dans la ligne
                Rectangle {
                    visible: root.pendingRevokeId === g.modelData.userId
                    Layout.fillWidth: true
                    Layout.bottomMargin: 10
                    implicitHeight: confirmRow.implicitHeight + 18
                    color: Theme.dangerSoft
                    Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
                    RowLayout {
                        id: confirmRow
                        anchors.verticalCenter: parent.verticalCenter
                        x: 14
                        width: parent.width - 24
                        spacing: 10
                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.StyledText
                            wrapMode: Text.WordWrap
                            text: qsTr("Retirer l'accès de <b>%1</b> ? Son poste ne recevra plus les modifications ; ses copies déjà reçues restent chez lui.").arg(g.modelData.username)
                            color: Theme.ink
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12.5)
                        }
                        AppButton { variant: "ghost"; size: "small"; text: qsTr("Annuler"); onClicked: root.pendingRevokeId = -1 }
                        AppButton {
                            variant: "danger"
                            size: "small"
                            text: qsTr("Retirer")
                            onClicked: {
                                if (root.context && root.context.revokeAccess(root.folderId, g.modelData.userId)) {
                                    root.reload()
                                    root.accessChanged()
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: 12; Layout.bottomMargin: 14; Layout.preferredHeight: 1; color: Theme.line }

        Text {
            Layout.bottomMargin: 8
            text: qsTr("Ajouter une personne")
            color: Theme.ink2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12)
            font.weight: Theme.weightSemibold
        }
        Text {
            visible: root.candidates.length === 0
            Layout.fillWidth: true
            text: qsTr("Tous les utilisateurs ont déjà accès à ce dossier.")
            color: Theme.ink3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12.5)
        }
        RowLayout {
            visible: root.candidates.length > 0
            Layout.fillWidth: true
            spacing: 8
            ComboBox {
                id: picker
                Layout.fillWidth: true
                implicitHeight: 32
                model: root.candidates
                textRole: "username"
                currentIndex: root.pickedIndex
                displayText: currentIndex < 0 ? qsTr("Choisir parmi %1 utilisateur(s)…").arg(root.candidates.length) : currentText
                onActivated: function(i) { root.pickedIndex = i }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                background: Rectangle {
                    radius: Theme.radiusSheet
                    color: Theme.surface0
                    border.width: 1
                    border.color: picker.activeFocus || picker.hovered ? Theme.ink : Theme.lineStrong
                }
                contentItem: Text {
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    text: picker.displayText
                    color: picker.currentIndex < 0 ? Theme.ink3 : Theme.ink
                    font: picker.font
                    elide: Text.ElideRight
                }
                indicator: LineIcon {
                    x: picker.width - width - 10
                    y: (picker.height - height) / 2
                    path: Icons.chevronDown
                    size: 14
                    strokeWidth: 1.8
                    color: Theme.ink2
                }
                popup.background: Rectangle { color: Theme.surface0; border.width: 1; border.color: Theme.ruleInk; radius: Theme.radiusSheet }
                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: picker.width
                    height: 34
                    highlighted: picker.highlightedIndex === index
                    background: Rectangle { color: parent.highlighted ? Theme.selectWash : "transparent" }
                    contentItem: Text { text: modelData.username; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); verticalAlignment: Text.AlignVCenter }
                }
            }
            PermissionSwitch { write: root.addWrite; onPicked: function(write) { root.addWrite = write } }
            AppButton {
                variant: "ink"
                size: "small"
                text: qsTr("Ajouter")
                enabled: root.pickedIndex >= 0
                onClicked: {
                    const u = root.candidates[root.pickedIndex]
                    if (u && root.context && root.context.grantAccess(root.folderId, u.userId, root.addWrite)) {
                        root.reload()
                        root.accessChanged()
                    }
                }
            }
        }
    }

    footer: [
        AppButton { variant: "line"; text: qsTr("Fermer"); onClicked: root.closeRequested() }
    ]
}
