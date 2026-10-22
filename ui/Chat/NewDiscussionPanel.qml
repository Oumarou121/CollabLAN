import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * NewDiscussionPanel - volet « Nouvelle discussion » (Ligne claire), qui
 * remplace les pages NewConversationView et CreateGroupView. Deux onglets :
 *  - Une personne : liste avec presence et poste ; « Rouvrir » quand une
 *    discussion existe deja (startConversationWith la retrouve) ;
 *  - Un groupe : 1 le nom, 2 les membres, une phrase qui resume, puis
 *    createGroup(name, memberIds).
 */
Rectangle {
    id: root

    property var people: []                 // [{ userId, username, status, machineName, existing }]
    property string mode: "person"          // "person" | "group"
    property string errorText: ""

    property string search: ""
    property string groupName: ""
    property var picked: []

    signal closeRequested()
    signal personChosen(var userId)
    signal groupRequested(string name, var memberIds)
    signal errorDismissed()

    function reset(m) {
        root.mode = m || "person"
        root.search = ""
        root.groupName = ""
        root.picked = []
        personFind.text = ""
        memberFind.text = ""
        nameField.text = ""
    }
    function isPicked(id) { return root.picked.indexOf(id) !== -1 }
    function toggle(id) { root.picked = root.isPicked(id) ? root.picked.filter(function(x) { return x !== id }) : root.picked.concat([id]) }
    function presenceWord(s) {
        switch (s) {
        case "online": return qsTr("En ligne")
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        }
        return qsTr("Hors ligne")
    }
    function presenceKind(s) { return s === "online" || s === "away" || s === "busy" ? s : "offline" }
    function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;") }

    // Personnes connectees d'abord, puis par nom.
    readonly property var sorted: root.people.slice().sort(function(a, b) {
        const oa = a.status === "offline" || !a.status ? 1 : 0, ob = b.status === "offline" || !b.status ? 1 : 0
        return oa - ob || a.username.localeCompare(b.username)
    })
    function filtered(q) {
        q = (q || "").trim().toLowerCase()
        return root.sorted.filter(function(p) { return q.length === 0 || p.username.toLowerCase().indexOf(q) !== -1 })
    }
    readonly property bool canCreate: root.groupName.trim().length > 0 && root.picked.length > 0

    color: Theme.bg
    Rectangle { width: 1; height: parent.height; color: Theme.ruleInk; z: 2 }
    Rectangle {
        x: -28
        width: 28
        height: parent.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.shadowStrong }
        }
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    component StepHeader: RowLayout {
        id: sh
        property string number: "1"
        property string title: ""
        property string meta: ""
        property bool done: false
        spacing: 12
        Text { Layout.preferredWidth: 18; text: sh.done ? "✓" : sh.number; color: sh.done ? Theme.successInk : Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(22); font.weight: Theme.weightBold }
        Text { Layout.fillWidth: true; text: sh.title; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold }
        CapsLabel { visible: sh.meta.length > 0; text: sh.meta }
    }
    component FindField: Rectangle {
        id: ff
        property alias text: ffInput.text
        property string placeholder: ""
        implicitHeight: 32
        radius: Theme.radiusSheet
        color: "transparent"
        border.width: 1
        border.color: ffInput.activeFocus ? Theme.ink : Theme.line
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 7
            LineIcon { path: Icons.search; size: 14; strokeWidth: 1.8; color: Theme.ink3 }
            TextField {
                id: ffInput
                Layout.fillWidth: true
                placeholderText: ff.placeholder
                placeholderTextColor: Theme.ink3
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12.5)
                background: Item {}
                leftPadding: 0
                rightPadding: 0
                selectByMouse: true
                Accessible.name: ff.placeholder
            }
        }
    }
    component ModeButton: AbstractButton {
        id: mb
        property string iconPath: ""
        property bool on: false
        Layout.fillWidth: true
        implicitHeight: 34
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.role: Accessible.PageTab
        Accessible.name: mb.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle { color: mb.on ? Theme.ink : (mb.hovered ? Theme.selectWash : "transparent"); border.width: mb.visualFocus ? 2 : 0; border.color: Theme.focusRing }
        contentItem: Item {
            Row {
                anchors.centerIn: parent
                spacing: 7
                LineIcon { anchors.verticalCenter: parent.verticalCenter; path: mb.iconPath; size: 15; strokeWidth: 1.8; color: mb.on ? Theme.inkOnInk : Theme.ink2 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: mb.text; color: mb.on ? Theme.inkOnInk : Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 1
        spacing: 0

        // ---- En-tete ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 14
            Layout.topMargin: 18
            Layout.bottomMargin: 14
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                CapsLabel { text: qsTr("Nouvelle discussion") }
                Text {
                    text: root.mode === "group" ? qsTr("Créer un groupe") : qsTr("Écrire à quelqu'un")
                    color: Theme.ink
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: Theme.fs(24)
                    font.weight: Theme.weightBold
                }
                Text {
                    Layout.fillWidth: true
                    text: root.mode === "group" ? qsTr("Une discussion partagée avec plusieurs collègues du réseau local.")
                                                : qsTr("Choisissez la personne : la discussion s'ouvre à côté.")
                    color: Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 320
                    Layout.topMargin: 12
                    implicitHeight: 36
                    radius: Theme.radiusSheet
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.lineStrong
                    clip: true
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 1
                        spacing: 0
                        ModeButton { text: qsTr("Une personne"); iconPath: Icons.messageCircle; on: root.mode === "person"; onClicked: root.mode = "person" }
                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Theme.lineStrong }
                        ModeButton { text: qsTr("Un groupe"); iconPath: Icons.users; on: root.mode === "group"; onClicked: root.mode = "group" }
                    }
                }
            }
            AbstractButton {
                id: closeBtn
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                hoverEnabled: true
                Accessible.name: qsTr("Fermer")
                onClicked: root.closeRequested()
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                background: Rectangle { radius: 17; color: closeBtn.hovered ? Theme.selectWash : "transparent"; border.width: closeBtn.visualFocus ? 2 : 0; border.color: Theme.focusRing }
                contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.close; size: 17; strokeWidth: 1.8; color: Theme.ink2 } }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line }

        Rectangle {
            visible: root.errorText.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 12
            implicitHeight: errRow.implicitHeight + 16
            color: Theme.dangerSoft
            Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
            RowLayout {
                id: errRow
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                Text { Layout.fillWidth: true; text: root.errorText; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WordWrap }
                TextLink { text: qsTr("OK"); arrow: false; onClicked: root.errorDismissed() }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight + 20
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: body
                x: 24
                width: parent.width - 48
                spacing: 0

                // ================= Une personne =================
                ColumnLayout {
                    visible: root.mode === "person"
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    spacing: 0
                    FindField { id: personFind; Layout.fillWidth: true; Layout.bottomMargin: 8; placeholder: qsTr("Rechercher une personne…") }
                    Repeater {
                        model: root.filtered(personFind.text)
                        delegate: AbstractButton {
                            id: pr
                            required property var modelData
                            required property int index
                            readonly property var p: modelData
                            Layout.fillWidth: true
                            implicitHeight: 52
                            hoverEnabled: true
                            focusPolicy: Qt.TabFocus
                            Accessible.name: (pr.p.existing ? qsTr("Rouvrir la discussion avec %1") : qsTr("Écrire à %1")).arg(pr.p.username)
                            onClicked: root.personChosen(pr.p.userId)
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            background: Rectangle {
                                color: pr.hovered || pr.visualFocus ? Theme.selectWash : "transparent"
                                border.width: pr.visualFocus ? 2 : 0
                                border.color: Theme.focusRing
                                Rectangle { visible: pr.index > 0; width: parent.width; height: 1; color: Theme.line }
                            }
                            contentItem: RowLayout {
                                spacing: 12
                                ChatMonogram { Layout.leftMargin: 6; size: 28; label: pr.p.username; status: pr.p.status || "offline" }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { Layout.fillWidth: true; text: pr.p.username; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold; elide: Text.ElideRight }
                                    Text {
                                        Layout.fillWidth: true
                                        text: root.presenceWord(pr.p.status)
                                              + (pr.p.machineName && pr.p.status !== "offline" ? " · " + pr.p.machineName : "")
                                              + (pr.p.existing ? " · " + qsTr("discussion existante") : "")
                                        color: Theme.ink3
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12)
                                        elide: Text.ElideRight
                                    }
                                }
                                Row {
                                    Layout.rightMargin: 6
                                    opacity: pr.hovered || pr.visualFocus ? 1 : 0
                                    spacing: 4
                                    Text { text: pr.p.existing ? qsTr("Rouvrir") : qsTr("Écrire"); color: Theme.navActiveInk; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
                                    LineIcon { anchors.verticalCenter: parent.verticalCenter; path: Icons.arrowRight; size: 13; strokeWidth: 1.9; color: Theme.navActiveInk }
                                }
                            }
                        }
                    }
                    Text {
                        visible: root.filtered(personFind.text).length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        text: root.people.length === 0 ? qsTr("Aucun autre compte sur ce réseau pour l'instant.") : qsTr("Personne ne correspond.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        text: qsTr("Si une discussion existe déjà avec cette personne, elle est rouverte.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        wrapMode: Text.WordWrap
                    }
                }

                // ================= Un groupe =================
                ColumnLayout {
                    visible: root.mode === "group"
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 8
                    StepHeader { Layout.fillWidth: true; number: "1"; title: qsTr("Le nom"); done: root.groupName.trim().length > 0 }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        implicitHeight: 36
                        radius: Theme.radiusSheet
                        color: Theme.surface0
                        border.width: nameField.activeFocus ? 1.5 : 1
                        border.color: nameField.activeFocus ? Theme.ink : Theme.lineStrong
                        TextField {
                            id: nameField
                            anchors.fill: parent
                            leftPadding: 12
                            rightPadding: 12
                            placeholderText: qsTr("ex. Comptabilité, Équipe logistique")
                            placeholderTextColor: Theme.ink3
                            color: Theme.ink
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13.5)
                            background: Item {}
                            selectByMouse: true
                            Accessible.name: qsTr("Nom du groupe")
                            onTextChanged: root.groupName = text
                        }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 10; Layout.preferredHeight: 1; color: Theme.line }

                    StepHeader {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        number: "2"
                        title: qsTr("Les membres")
                        done: root.picked.length > 0
                        meta: root.picked.length > 1 ? qsTr("%1 choisis").arg(root.picked.length) : root.picked.length === 1 ? qsTr("1 choisi") : ""
                    }
                    FindField { id: memberFind; Layout.fillWidth: true; Layout.leftMargin: 30; placeholder: qsTr("Rechercher une personne…") }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        spacing: 0
                        Repeater {
                            model: root.filtered(memberFind.text)
                            delegate: AbstractButton {
                                id: mr
                                required property var modelData
                                required property int index
                                readonly property bool on: root.isPicked(mr.modelData.userId)
                                Layout.fillWidth: true
                                implicitHeight: 50
                                hoverEnabled: true
                                focusPolicy: Qt.TabFocus
                                Accessible.role: Accessible.CheckBox
                                Accessible.checked: mr.on
                                Accessible.name: mr.modelData.username
                                onClicked: root.toggle(mr.modelData.userId)
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                background: Rectangle {
                                    color: mr.hovered ? Theme.selectWash : "transparent"
                                    border.width: mr.visualFocus ? 2 : 0
                                    border.color: Theme.focusRing
                                    Rectangle { visible: mr.index > 0; width: parent.width; height: 1; color: Theme.line }
                                }
                                contentItem: RowLayout {
                                    spacing: 12
                                    Rectangle {
                                        Layout.leftMargin: 6
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        radius: 2
                                        color: mr.on ? Theme.ink : "transparent"
                                        border.width: mr.on ? 0 : 1.5
                                        border.color: Theme.lineStrong
                                        LineIcon { visible: mr.on; anchors.centerIn: parent; path: Icons.check; size: 12; strokeWidth: 2.6; color: Theme.inkOnInk }
                                    }
                                    ChatMonogram { size: 28; label: mr.modelData.username }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text { Layout.fillWidth: true; text: mr.modelData.username; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold; elide: Text.ElideRight }
                                        Text { text: root.presenceWord(mr.modelData.status); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        visible: root.canCreate
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        color: Theme.ink2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(14)
                        text: {
                            const names = root.people.filter(function(p) { return root.isPicked(p.userId) }).map(function(p) { return "<b>" + root.esc(p.username) + "</b>" })
                            const who = names.length === 1 ? names[0]
                                      : names.length === 2 ? names[0] + " " + qsTr("et") + " " + names[1]
                                      : qsTr("<b>%1 personnes</b>").arg(names.length)
                            return qsTr("Créer <b>« %1 »</b> avec %2. Vous en faites partie.").arg(root.esc(root.groupName.trim())).arg(who)
                        }
                    }
                }
            }
        }

        // ---- Pied (groupe) -------------------------------------------------
        Rectangle { visible: root.mode === "group"; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }
        RowLayout {
            visible: root.mode === "group"
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: root.canCreate ? qsTr("%1 personnes, vous compris").arg(root.picked.length + 1)
                      : root.groupName.trim().length === 0 ? qsTr("Donnez un nom pour continuer") : qsTr("Choisissez au moins un membre")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                wrapMode: Text.WordWrap
            }
            AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.closeRequested() }
            AppButton {
                variant: "ink"
                iconPath: Icons.users
                text: qsTr("Créer le groupe")
                enabled: root.canCreate
                onClicked: root.groupRequested(root.groupName.trim(), root.picked)
            }
        }
    }
}
