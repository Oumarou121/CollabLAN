import QtQuick
import QtQuick.Controls
import Themes

/*
 * ServerStatusIndicator - indicateur discret de l'etat de la bascule
 * automatique de serveur (HYBRID_SERVER_FAILOVER.md section 9, etape 5) :
 *   - "Connecté au serveur"                      (role Client, normal)
 *   - "Mode secours (serveur de secours actif)"  (role TempServer)
 *   - "Serveur actif"                            (role Server, ce poste)
 *   - "Reconnexion en cours..."                  (heartbeat perdu, election
 *                                                  en cours, avant qu'un
 *                                                  nouveau role soit connu)
 *
 * Purement passif : se contente d'observer "electionService" (expose
 * globalement depuis app/main.cpp), aucune action utilisateur.
 */
Item {
    id: root

    property var election: (typeof electionService !== "undefined") ? electionService : null
    property bool reconnecting: false

    // Se cache silencieusement si ElectionService n'est pas disponible
    // (ex. contexte de preview/design sans backend).
    visible: election !== null
    implicitWidth: badge.implicitWidth
    implicitHeight: badge.implicitHeight

    Connections {
        target: root.election
        function onHeartbeatLost() { root.reconnecting = true }
        function onRoleChanged() { root.reconnecting = false }
    }

    readonly property string statusLabel: {
        if (!election)
            return ""
        if (reconnecting)
            return qsTr("Reconnexion en cours...")
        if (election.roleLabel === "TEMP_SERVER")
            return qsTr("Mode secours (serveur de secours actif)")
        if (election.roleLabel === "SERVER")
            return qsTr("Serveur actif")
        return qsTr("Connecté au serveur")
    }

    readonly property color statusColor: {
        if (!election)
            return Theme.textSecondary
        if (reconnecting)
            return Theme.warning
        if (election.roleLabel === "TEMP_SERVER")
            return Theme.warning
        return Theme.success
    }

    Rectangle {
        id: badge
        radius: height / 2
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        implicitWidth: content.implicitWidth + Theme.spacingMedium * 2
        implicitHeight: content.implicitHeight + Theme.spacingSmall * 1.5

        Row {
            id: content
            anchors.centerIn: parent
            spacing: Theme.spacingSmall / 2

            Rectangle {
                width: 8
                height: 8
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: root.statusColor
            }

            Label {
                text: root.statusLabel
                color: Theme.text
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
