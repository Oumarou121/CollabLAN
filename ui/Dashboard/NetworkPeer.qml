import QtQuick
import Themes

/*
 * NetworkPeer - Poste sur la carte réseau, transcription fidèle de la
 * maquette HTML (localink-workspace-v2-1.html, fonction buildNet()).
 *
 * Un seul composant couvre les deux familles de rendu de la maquette :
 *  - postes autorisés présents (en ligne / absent / en transfert / en appel)
 *  - postes autorisés mais absents ("hors ligne", orbite extérieure),
 *    activés via `offline: true`
 *
 * Rayons/marges/couleurs recopiés depuis buildNet() : cercle r=17,
 * enveloppe r=17+3.5=20.5, halo hover r=29, halo sélection r=30, badge
 * décalé de r*0.74 en x/y, texte à r+20 / r+33 sous le centre.
 */
Item {
    id: root

    // Largeur du bloc étiquette. Refonte 2026 : 120 px au lieu de 86, pour
    // qu'un nom long ("PC-COMMERCIAL-04") ne soit plus tronqué. La boîte de
    // collision correspondante est peerBoxW dans NetworkWorkspace.qml.
    // Largeur de l'etiquette : un nom long passe sur deux lignes plutot que
    // d'etre elide des 16 caracteres ("PC-COMMERCIAL-04").
    width: 148
    // Hauteur reelle du contenu (1 ou 2 lignes de nom) : le noeud reste
    // ancre en haut, seule l'etiquette fait varier le bas.
    height: nameLabel.y + nameLabel.height + 1 + statusLabel.height

    property string peerId: ""
    property string label: ""
    property string address: ""
    // online | away | busy | transferring | calling | offline
    property string status: "online"
    property bool isSelected: false
    property bool isHovered: false
    // Rend un poste hors ligne cliquable (selection pour un panneau exterieur).
    property bool selectable: false
    readonly property bool offline: status === "offline"
    readonly property bool hasBadgeIcon: status === "transferring" || status === "calling"
    readonly property real nodeRadius: 17

    signal clicked()
    signal entered()
    signal exited()

    // Marques de la carte réseau (jetons dashboardMark*) : la couleur
    // n'encode que l'activité, "en ligne" garde l'anneau vert neutre.
    readonly property color statusColor: {
        switch (root.status) {
        case "transferring": return Theme.dashboardMarkTransfer
        case "calling": return Theme.dashboardMarkCall
        case "away": return Theme.dashboardMarkAway
        case "busy": return Theme.dashboardMarkAway
        case "offline": return Theme.dashboardNodeOfflineLine
        default: return Theme.dashboardSuccess
        }
    }

    readonly property color labelColor: {
        switch (root.status) {
        case "transferring": return Theme.dashboardMarkTransfer
        case "calling": return Theme.dashboardMarkCall
        case "away": return Theme.dashboardWarningText
        case "busy": return Theme.dashboardWarningText
        case "offline": return Theme.dashboardInkTertiary
        default: return Theme.dashboardSuccessText
        }
    }

    readonly property string statusLabel: {
        switch (root.status) {
        case "transferring": return qsTr("En transfert")
        case "calling": return qsTr("En appel")
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        case "offline": return qsTr("Hors ligne")
        default: return qsTr("En ligne")
        }
    }

    // Halo de sélection - rayon 30, fond primary très léger, bordure primary
    // (maquette : §23 « background primary très léger / border primary »)
    Rectangle {
        visible: root.isSelected
        anchors.centerIn: node
        width: 60
        height: 60
        radius: 30
        color: Theme.dashboardPrimary
        opacity: 0.09
        border.width: 1.8
        border.color: Theme.dashboardPrimary
    }

    // Halo de survol - rayon 29, discret, disparaît en dehors du hover
    Rectangle {
        id: hoverHalo
        visible: !root.offline
        anchors.centerIn: node
        width: 58
        height: 58
        radius: 29
        color: Theme.dashboardPrimary
        opacity: root.isHovered ? 0.07 : 0
        border.width: root.isHovered ? 1.4 : 0
        border.color: Theme.dashboardPrimary
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Item {
        id: node
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 8
        width: root.nodeRadius * 2
        height: root.nodeRadius * 2

        // --- Poste hors ligne : rempli très clair, bordure pointillée grise ---
        Rectangle {
            visible: root.offline
            anchors.fill: parent
            radius: width / 2
            color: Theme.dashboardNodeOffline
            border.width: 1.6
            border.color: Theme.dashboardNodeOfflineLine
        }
        // Qt Quick n'a pas de bordure pointillée native pour Rectangle : on
        // superpose un Canvas qui redessine le cercle en pointillés (3 3),
        // fidèle au stroke-dasharray de la maquette.
        Canvas {
            visible: root.offline
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = Theme.dashboardNodeOfflineLine
                ctx.lineWidth = 1.6
                ctx.setLineDash([3, 3])
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, width / 2 - 0.8, 0, 2 * Math.PI)
                ctx.stroke()
            }
        }
        Text {
            visible: root.offline
            anchors.centerIn: parent
            text: "\uf108"
            color: Theme.dashboardNodeOfflineInk
            font.pixelSize: Theme.fs(15)
            font.family: "FontAwesome"
            opacity: 0.8
        }

        // --- Poste présent : cercle blanc + bordure colorée + cercle intérieur ---
        Rectangle {
            visible: !root.offline
            anchors.fill: parent
            radius: width / 2
            color: Theme.dashboardSurface
            border.width: 2.4
            border.color: root.statusColor
        }
        Rectangle {
            visible: !root.offline
            anchors.centerIn: parent
            width: parent.width - 7
            height: width
            radius: width / 2
            color: Theme.dashboardPrimarySoft
        }
        Text {
            visible: !root.offline
            anchors.centerIn: parent
            text: "\uf108"
            color: Theme.dashboardPrimary
            font.pixelSize: Theme.fs(16)
            font.family: "FontAwesome"
        }

        // Badge de statut - décalé de r*0.74 en x et y depuis le centre
        Rectangle {
            visible: !root.offline
            width: root.hasBadgeIcon ? 17 : 9.2
            height: width
            radius: width / 2
            color: root.statusColor
            border.width: 2
            border.color: Theme.dashboardSurface
            x: root.nodeRadius + root.nodeRadius * 0.74 - width / 2
            y: root.nodeRadius + root.nodeRadius * 0.74 - height / 2

            Text {
                visible: root.hasBadgeIcon
                anchors.centerIn: parent
                text: root.status === "transferring" ? "\uf1d8" : "\uf095"
                color: Theme.dashboardSurface
                font.pixelSize: Theme.fs(9)
                font.family: "FontAwesome"
            }
        }
    }

    // Hostname - largeur contrainte + elide pour les noms longs (doc §17)
    Text {
        id: nameLabel
        anchors.top: node.bottom
        anchors.topMargin: root.offline ? 4 : 3
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        // Deux lignes maximum ; Text.Wrap (et non WordWrap) coupe aussi un
        // nom d'un seul tenant, frequent pour un nom d'hote.
        wrapMode: Text.Wrap
        maximumLineCount: 2
        lineHeight: 0.95
        elide: Text.ElideRight
        text: root.label
        color: root.offline ? Theme.dashboardInkTertiary : Theme.dashboardInk
        // Detourage : reste lisible quand une liaison passe sous l'etiquette.
        style: Text.Outline
        styleColor: Theme.dashboardSurfaceAlt
        font.pixelSize: Theme.fs(12)
        font.weight: root.isSelected ? Font.Bold : Font.DemiBold
        font.family: Theme.fontFamily
    }

    Text {
        id: statusLabel
        anchors.top: nameLabel.bottom
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.statusLabel
        color: root.labelColor
        style: Text.Outline
        styleColor: Theme.dashboardSurfaceAlt
        font.pixelSize: Theme.fs(11)
        font.weight: Font.Medium
        font.family: Theme.fontFamily
    }

    MouseArea {
        anchors.fill: node
        hoverEnabled: !root.offline || root.selectable
        enabled: !root.offline || root.selectable
        cursorShape: Qt.PointingHandCursor
        onEntered: root.entered()
        onExited: root.exited()
        onClicked: root.clicked()
    }
}
