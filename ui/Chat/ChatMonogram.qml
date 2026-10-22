import QtQuick
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * ChatMonogram - signe d'une discussion (Ligne claire) : initiales serif sur
 * disque d'encre et pastille de presence pour une personne ; carre a filet,
 * icone de groupe et nombre de membres pour un groupe ; cercle a filet et
 * icone d'ecran pour un poste sans compte (`machine`).
 */
Item {
    id: root

    property string label: ""
    property bool group: false
    property bool machine: false
    property string status: ""              // online | away | busy | offline | "" (sans pastille)
    property int memberCount: 0
    property real size: 40

    implicitWidth: size
    implicitHeight: size

    function initials(t) {
        const w = (t || "?").split(/[\s-]+/).filter(function(x) { return x.length > 0 })
        return ((w[0] || "?").charAt(0) + (w.length > 1 ? w[1].charAt(0) : "")).toUpperCase()
    }
    function presenceKind(s) {
        s = (s || "").toLowerCase()
        return s === "online" || s === "away" || s === "busy" ? s : "offline"
    }

    Rectangle {
        anchors.fill: parent
        radius: root.group ? Theme.radiusSheet : width / 2
        color: root.group || root.machine ? "transparent" : Theme.ink
        border.width: root.group || root.machine ? 1 : 0
        border.color: Theme.lineStrong
        Text {
            visible: !root.group && !root.machine
            anchors.centerIn: parent
            text: root.initials(root.label)
            color: Theme.inkOnInk
            font.family: Theme.fontFamilySerif
            font.pixelSize: Math.round(root.size * 0.35)
            font.weight: Theme.weightBold
        }
        LineIcon {
            visible: root.group || root.machine
            anchors.centerIn: parent
            path: root.machine ? Icons.monitor : Icons.users
            size: Math.round(root.size * 0.45)
            strokeWidth: 1.6
            color: Theme.ink2
        }
    }

    // Presence (personne)
    Rectangle {
        visible: !root.group && root.status.length > 0
        x: root.width - width + 2
        y: root.height - height + 2
        width: 14
        height: 14
        radius: 7
        color: Theme.bg
        StateGlyph { anchors.centerIn: parent; kind: root.presenceKind(root.status); size: 10 }
    }

    // Nombre de membres (groupe)
    Rectangle {
        visible: root.group && root.memberCount > 0
        x: root.width - width + 5
        y: root.height - height + 5
        width: Math.max(17, countText.implicitWidth + 8)
        height: 17
        radius: 8.5
        color: Theme.bg
        border.width: 1
        border.color: Theme.lineStrong
        Text {
            id: countText
            anchors.centerIn: parent
            text: root.memberCount
            color: Theme.ink2
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fs(10)
            font.weight: Theme.weightBold
        }
    }
}
