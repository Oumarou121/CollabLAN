import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "transferFormat.js" as Fmt

/*
 * PeerFiche - fiche du poste selectionne (Ligne claire) : etat (glyphe +
 * mot), nom en PT Serif, personne connectee, activite en cours (transfert
 * avec progression, ou appel), dernier message echange avec cette personne,
 * faits (adresse, derniere activite, role, confiance pour l'administrateur)
 * et actions. Pas de carte : la fiche est posee sur le papier.
 */
ColumnLayout {
    id: root

    property var peer: null
    property string addressText: ""
    property string lastActivityText: ""
    property string trustText: ""
    property bool isAdmin: false
    property bool anyPeer: true
    // Conversation avec la personne connectee : { conversationId, lastMessage,
    // timestamp, unreadCount } ou null.
    property var conversation: null
    property string conversationTime: ""

    signal messageRequested()
    signal sendFileRequested()
    signal callRequested()
    signal followTransferRequested()
    signal openConversationRequested(int conversationId)
    signal manageRequested()

    readonly property bool off: !!peer && peer.status === "offline"
    readonly property bool hasUser: !!peer && !!peer.userName
    readonly property var stateLabels: ({
        calling: qsTr("En appel"), transferring: qsTr("En transfert"), online: qsTr("En ligne"),
        busy: qsTr("Occupé"), away: qsTr("Absent"), offline: qsTr("Hors ligne")
    })

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        CapsLabel { text: qsTr("Poste sélectionné"); Layout.fillWidth: true }
        Row {
            visible: !!root.peer
            spacing: 6
            StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: root.peer ? root.peer.status : "online"; size: 11 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.peer ? (root.stateLabels[root.peer.status] || "") : ""
                color: Theme.ink2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Theme.weightSemibold
            }
        }
    }

    // ---- Aucun poste -----------------------------------------------------
    Text {
        visible: !root.peer
        Layout.fillWidth: true
        Layout.topMargin: 9
        text: root.anyPeer ? qsTr("Aucune sélection") : qsTr("Aucun poste détecté")
        color: Theme.ink
        font.family: Theme.fontFamilySerif
        font.pixelSize: Theme.fs(24)
        font.weight: Theme.weightBold
    }
    Text {
        visible: !root.peer
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: root.anyPeer ? qsTr("Sélectionnez un siège de l'hémicycle ou une ligne du registre.")
                           : qsTr("Dès qu'un poste apparaît, sélectionnez-le pour afficher ses détails et les actions possibles.")
        color: Theme.ink3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(13)
        wrapMode: Text.WordWrap
    }

    // ---- Identite ---------------------------------------------------------
    Text {
        visible: !!root.peer
        Layout.fillWidth: true
        Layout.topMargin: 9
        text: root.peer ? root.peer.name : ""
        color: Theme.ink
        font.family: Theme.fontFamilySerif
        font.pixelSize: Theme.fs(24)
        font.weight: Theme.weightBold
        lineHeight: 1.05
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: 2
        elide: Text.ElideRight
        Accessible.role: Accessible.Heading
    }
    Text {
        visible: !!root.peer
        Layout.fillWidth: true
        Layout.topMargin: 2
        text: root.hasUser ? root.peer.userName
                           : (root.off ? qsTr("Poste autorisé, actuellement absent") : qsTr("Aucun compte connecté"))
        color: Theme.ink2
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(13.5)
        elide: Text.ElideRight
    }

    // ---- Activite en cours ------------------------------------------------
    Rectangle {
        visible: !!root.peer && (!!root.peer.transfer || root.peer.status === "calling")
        Layout.fillWidth: true
        Layout.topMargin: 13
        Layout.preferredHeight: 1
        color: Theme.line
    }
    ColumnLayout {
        id: xferBlock
        visible: !!root.peer && !!root.peer.transfer
        Layout.fillWidth: true
        Layout.topMargin: 11
        spacing: 0

        readonly property var t: root.peer && root.peer.transfer ? root.peer.transfer : null
        readonly property real pct: t ? Math.max(0, Math.min(100, t.percent || 0)) : 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            LineIcon {
                path: xferBlock.t && xferBlock.t.incoming ? "M12 4.5v15 M18.5 13 12 19.5 5.5 13" : "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                size: 15
                strokeWidth: 1.9
                color: Theme.markTransfer
            }
            Text {
                Layout.fillWidth: true
                text: xferBlock.t ? (xferBlock.t.fileName || "") : ""
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13.5)
                font.weight: Theme.weightSemibold
                elide: Text.ElideMiddle
            }
            Text {
                text: Math.round(xferBlock.pct) + " %"
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(16)
                font.weight: Theme.weightBold
                font.features: ({ "tnum": 1 })
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 9
            Layout.preferredHeight: 2
            color: Theme.line
            Rectangle {
                y: -1
                width: parent.width * xferBlock.pct / 100
                height: 4
                color: Theme.markTransfer
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Text {
                Layout.fillWidth: true
                readonly property var t: xferBlock.t
                text: !t ? "" : (t.incoming ? qsTr("Réception") : qsTr("Envoi"))
                                + (t.totalBytes > 0 ? " · " + qsTr("%1 sur %2").arg(Fmt.formatBytesPrecise(t.bytesTransferred || 0))
                                                                     .arg(Fmt.formatBytesPrecise(t.totalBytes)) : "")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
            }
            TextLink {
                text: qsTr("Suivre")
                tooltip: qsTr("Ouvrir les transferts")
                onClicked: root.followTransferRequested()
            }
        }
    }
    RowLayout {
        visible: !!root.peer && root.peer.status === "calling"
        Layout.fillWidth: true
        Layout.topMargin: 11
        spacing: 8
        LineIcon { path: Icons.phone; size: 15; strokeWidth: 1.8; color: Theme.callColor }
        Text {
            Layout.fillWidth: true
            text: qsTr("Appel en cours avec ce poste")
            color: Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(13.5)
            font.weight: Theme.weightSemibold
        }
    }
    Rectangle {
        visible: !!root.peer && (!!root.peer.transfer || root.peer.status === "calling")
        Layout.fillWidth: true
        Layout.topMargin: 11
        Layout.preferredHeight: 1
        color: Theme.line
    }

    // ---- Dernier message --------------------------------------------------
    Rectangle {
        visible: !!root.peer && !!root.conversation
        Layout.fillWidth: true
        Layout.topMargin: 12
        implicitHeight: convoCol.implicitHeight + 20
        color: Theme.surface0
        border.width: 1
        border.color: Theme.line
        radius: Theme.radiusSheet

        ColumnLayout {
            id: convoCol
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Dernier message")
                          + (root.conversation && root.conversation.unreadCount > 0
                             ? " · <b><font color=\"" + Theme.navActiveInk + "\">"
                               + (root.conversation.unreadCount > 1 ? qsTr("%1 non lus").arg(root.conversation.unreadCount)
                                                                    : qsTr("1 non lu")) + "</font></b>" : "")
                    textFormat: Text.StyledText
                    color: Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11.5)
                }
                Text {
                    text: root.conversationTime
                    color: Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11.5)
                    font.features: ({ "tnum": 1 })
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.conversation ? "« " + (root.conversation.lastMessage || "") + " »" : ""
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                elide: Text.ElideRight
            }
            TextLink {
                text: qsTr("Ouvrir la conversation")
                onClicked: root.openConversationRequested(root.conversation ? root.conversation.conversationId : 0)
            }
        }
    }

    // ---- Faits ------------------------------------------------------------
    GridLayout {
        visible: !!root.peer
        Layout.fillWidth: true
        Layout.topMargin: 12
        columns: 2
        columnSpacing: 16
        rowSpacing: 6

        component FactKey: Text {
            color: Theme.ink3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(13)
        }
        component FactValue: Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            color: Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(13)
            font.features: ({ "tnum": 1 })
            elide: Text.ElideLeft
        }

        FactKey { text: qsTr("Adresse") }
        FactValue { text: root.addressText; font.family: "Cascadia Mono, Consolas, monospace"; font.pixelSize: Theme.fs(12) }
        FactKey { text: qsTr("Dernière activité") }
        FactValue { text: root.lastActivityText }
        FactKey { visible: !!root.peer && !!root.peer.server; text: qsTr("Rôle") }
        FactValue { visible: !!root.peer && !!root.peer.server; text: qsTr("Serveur du réseau") }
        FactKey { visible: root.isAdmin && root.trustText.length > 0; text: qsTr("Confiance") }
        FactValue { visible: root.isAdmin && root.trustText.length > 0; text: root.trustText }
    }

    // ---- Actions ----------------------------------------------------------
    Rectangle {
        visible: !!root.peer
        Layout.fillWidth: true
        Layout.topMargin: 14
        Layout.preferredHeight: 38
        color: "transparent"
        border.width: 1
        border.color: Theme.lineStrong
        radius: Theme.radiusSheet

        component FicheAction: AbstractButton {
            id: fa
            property string iconPath: ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            Accessible.name: fa.text
            HoverHandler { cursorShape: fa.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
            background: Rectangle {
                color: fa.hovered && fa.enabled ? Theme.ink : "transparent"
                border.width: fa.visualFocus ? 2 : 0
                border.color: Theme.focusRing
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            }
            contentItem: Item {
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    LineIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        path: fa.iconPath
                        size: 15
                        strokeWidth: 1.8
                        color: !fa.enabled ? Theme.inkDisabled : (fa.hovered ? Theme.inkOnInk : Theme.ink)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: fa.text
                        color: !fa.enabled ? Theme.inkDisabled : (fa.hovered ? Theme.inkOnInk : Theme.ink)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        font.weight: Theme.weightSemibold
                    }
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0
            FicheAction {
                text: qsTr("Message")
                iconPath: Icons.messageCircle
                enabled: !root.off && root.hasUser
                onClicked: root.messageRequested()
            }
            Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.lineStrong }
            FicheAction {
                text: qsTr("Fichier")
                iconPath: "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                enabled: !root.off
                onClicked: root.sendFileRequested()
            }
            Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.lineStrong }
            FicheAction {
                text: root.peer && root.peer.status === "calling" ? qsTr("En appel") : qsTr("Appeler")
                iconPath: Icons.phone
                enabled: !root.off && !(root.peer && root.peer.status === "calling")
                onClicked: root.callRequested()
            }
        }
    }
    Text {
        visible: !!root.peer && (root.off || !root.hasUser)
        Layout.fillWidth: true
        Layout.topMargin: 7
        text: root.off ? qsTr("Actions disponibles dès que le poste se reconnecte.")
                       : qsTr("Aucun compte connecté : messagerie indisponible.")
        color: Theme.ink3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(11.5)
        wrapMode: Text.WordWrap
    }
    TextLink {
        visible: !!root.peer && root.isAdmin
        Layout.topMargin: 10
        text: qsTr("Gérer dans l'administration")
        onClicked: root.manageRequested()
    }
}
