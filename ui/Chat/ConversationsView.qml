import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * ConversationsView - liste des discussions (Ligne claire), colonne gauche
 * de l'espace Discussions. Recoit les lignes deja preparees par
 * ChatWorkspaceView (apercu, presence, nombre de membres) ; filtre localement
 * (recherche, Toutes / Non lues / Groupes). La plus recente en tete.
 */
Item {
    id: root

    property var conversations: []          // [{ conversationId, name, preview, timestamp, unreadCount, isGroup, status, memberCount }]
    property var selectedConversationId: null
    property string filter: "all"           // "all" | "unread" | "groups"
    property string search: ""

    signal conversationSelected(var conversationId, string name)

    function timeLabel(value) {
        if (!value) return ""
        const d = new Date(value)
        if (isNaN(d.getTime())) return ""
        const now = new Date()
        if (d.toDateString() === now.toDateString())
            return d.toLocaleTimeString(Qt.locale(), "HH:mm")
        const yesterday = new Date(now.getTime() - 86400000)
        if (d.toDateString() === yesterday.toDateString())
            return qsTr("hier")
        if (now.getTime() - d.getTime() < 6 * 86400000)
            return d.toLocaleDateString(Qt.locale(), "ddd")
        return d.toLocaleDateString(Qt.locale(), "d MMM")
    }

    readonly property int unreadCount: root.conversations.filter(function(c) { return c.unreadCount > 0 }).length
    readonly property int groupCount: root.conversations.filter(function(c) { return c.isGroup }).length

    readonly property var rows: {
        const q = root.search.trim().toLowerCase()
        return root.conversations.filter(function(c) {
            const f = root.filter === "unread" ? c.unreadCount > 0 : root.filter === "groups" ? c.isGroup : true
            return f && (q.length === 0 || (c.name || "").toLowerCase().indexOf(q) !== -1)
        })
    }

    component InkTab: AbstractButton {
        id: it
        property bool current: false
        property string count: ""
        property bool brand: false
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        padding: 0
        implicitHeight: 28
        implicitWidth: itRow.implicitWidth
        Accessible.role: Accessible.PageTab
        Accessible.name: it.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Item {
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 2; color: it.current ? Theme.ruleInk : "transparent" }
            Rectangle { anchors.fill: parent; anchors.margins: -3; color: "transparent"; radius: Theme.radiusSheet; border.width: it.visualFocus ? 2 : 0; border.color: Theme.focusRing }
        }
        contentItem: Item {
            Row {
                id: itRow
                spacing: 5
                anchors.top: parent.top
                anchors.topMargin: 3
                Text { text: it.text; color: it.current || it.hovered ? Theme.ink : Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: it.current ? Theme.weightSemibold : Theme.weightMedium }
                Text { text: it.count; color: it.brand && it.count !== "0" ? Theme.navActiveInk : Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(12); font.weight: Theme.weightBold }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 14
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 10
            CapsLabel { text: qsTr("Discussions"); Layout.fillWidth: true }
            Text { text: root.conversations.length; color: Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            Layout.bottomMargin: 10
            radius: Theme.radiusSheet
            color: "transparent"
            border.width: 1
            border.color: findField.activeFocus ? Theme.ink : Theme.line
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 7
                LineIcon { path: Icons.search; size: 14; strokeWidth: 1.8; color: Theme.ink3 }
                TextField {
                    id: findField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Personne ou groupe…")
                    placeholderTextColor: Theme.ink3
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                    background: Item {}
                    leftPadding: 0
                    rightPadding: 0
                    selectByMouse: true
                    Accessible.name: qsTr("Rechercher une discussion")
                    onTextChanged: root.search = text
                }
            }
        }
        Row {
            Layout.bottomMargin: 6
            spacing: 16
            InkTab { text: qsTr("Toutes"); count: String(root.conversations.length); current: root.filter === "all"; onClicked: root.filter = "all" }
            InkTab { text: qsTr("Non lues"); count: String(root.unreadCount); brand: true; current: root.filter === "unread"; onClicked: root.filter = "unread" }
            InkTab { text: qsTr("Groupes"); count: String(root.groupCount); current: root.filter === "groups"; onClicked: root.filter = "groups" }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 4
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.rows
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: AbstractButton {
                id: row
                required property var modelData
                readonly property var c: modelData
                readonly property bool on: root.selectedConversationId !== null && root.selectedConversationId !== undefined
                                           && row.c.conversationId === root.selectedConversationId
                readonly property bool unread: row.c.unreadCount > 0
                width: ListView.view.width
                implicitHeight: rowLayout.implicitHeight + 20
                hoverEnabled: true
                focusPolicy: Qt.TabFocus
                Accessible.role: Accessible.Button
                Accessible.name: row.c.name + (row.unread ? ", " + qsTr("%1 non lu(s)").arg(row.c.unreadCount) : "")
                onClicked: root.conversationSelected(row.c.conversationId, row.c.name)
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                background: Rectangle {
                    radius: Theme.radiusSheet
                    color: row.on ? Theme.surface0 : (row.hovered ? Theme.selectWash : "transparent")
                    border.width: row.on ? 1 : (row.visualFocus ? 2 : 0)
                    border.color: row.visualFocus ? Theme.focusRing : Theme.line
                    Rectangle { visible: row.on; x: -1; y: 8; width: 3; height: parent.height - 16; color: Theme.ruleInk }
                }
                contentItem: RowLayout {
                    id: rowLayout
                    spacing: 12
                    ChatMonogram {
                        Layout.leftMargin: 10
                        label: row.c.name
                        group: row.c.isGroup
                        status: row.c.status
                        memberCount: row.c.memberCount
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.rightMargin: 10
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: row.c.name
                                color: Theme.ink
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(13.5)
                                font.weight: row.unread ? Theme.weightBold : Theme.weightMedium
                                elide: Text.ElideRight
                            }
                            Text {
                                text: root.timeLabel(row.c.timestamp)
                                color: row.unread ? Theme.navActiveInk : Theme.ink3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11.5)
                                font.weight: row.unread ? Theme.weightSemibold : Theme.weightRegular
                                font.features: ({ "tnum": 1 })
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.StyledText
                                text: row.c.preview.length > 0 ? row.c.preview : "<i>" + qsTr("Aucun message") + "</i>"
                                color: row.unread ? Theme.ink2 : Theme.ink3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12.5)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            Text {
                                visible: row.unread
                                text: row.c.unreadCount > 99 ? "99+" : row.c.unreadCount
                                color: Theme.navActiveInk
                                font.family: Theme.fontFamilySerif
                                font.pixelSize: Theme.fs(14)
                                font.weight: Theme.weightBold
                            }
                        }
                    }
                }
            }

            Text {
                visible: list.count === 0
                width: list.width
                y: 8
                text: root.conversations.length === 0 ? qsTr("Vos discussions apparaîtront ici.")
                      : root.search.length > 0 ? qsTr("Aucune discussion ne correspond.")
                      : root.filter === "unread" ? qsTr("Tout est lu.") : qsTr("Aucun groupe pour l'instant.")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12.5)
                wrapMode: Text.WordWrap
            }
        }
    }
}
