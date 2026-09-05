import QtQuick
import Themes

/*
 * ToastHost - superposition globale gerant la file des toasts (issue #58).
 *
 * A placer une seule fois, en dernier enfant de la fenetre racine
 * (Main.qml), pour s'afficher au-dessus de tous les ecrans quelle que
 * soit la vue courante du StackView.
 *
 * Ecoute NotificationManager::notificationRequested (expose globalement
 * en contexte QML sous le nom "notificationManager", voir app/main.cpp)
 * et empile chaque evenement notifiable sous forme de Toast.qml, dans
 * l'une de deux piles independantes :
 *  - messageQueue (categorie "message") : en bas a droite de l'ecran.
 *  - otherQueue (transfert/connexion/deconnexion/groupe/dossier) : en
 *    haut a droite.
 * Chaque pile affiche le design A (carte enrichie : icone/avatar, titre,
 * message, horodatage, lien d'action) pour un evenement isole, ou le
 * design C (groupe empile + compteur) des qu'un meme type d'evenement se
 * repete (rafale).
 * Dans chaque pile, le plus recent pousse les plus anciens (vers le haut
 * pour la pile du bas, vers le bas pour la pile du haut).
 */
Item {
    id: toastHost

    // z eleve pour rester au-dessus du StackView et de ses transitions.
    z: 1000
    anchors.fill: parent

    property var messageQueue: []
    property var otherQueue: []
    property int _nextKey: 0

    signal conversationRequested(int conversationId)
    // Relaye le clic sur une notification non-message (transfert, dossier,
    // connexion/deconnexion, groupe) : Main.qml route vers l'ecran adapte.
    signal actionRequested(string category)

    // Nombre max de toasts affiches simultanement par pile (les plus
    // anciens sont retires en premier) pour eviter d'inonder l'ecran en
    // cas de rafale d'evenements (ex. plusieurs postes qui se
    // deconnectent d'un coup).
    readonly property int maxVisible: 4

    // ---- Pile "message" : bas-droite ---------------------------------
    Column {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall
        width: 360

        Repeater {
            model: toastHost.messageQueue

            delegate: Toast {
                anchors.right: parent.right
                title: modelData.title
                message: modelData.message
                category: modelData.category
                count: modelData.count
                conversationId: modelData.conversationId

                onDismissed: toastHost.removeToast(modelData.key, true)
                onConversationRequested: (conversationId) => {
                    toastHost.conversationRequested(conversationId)
                    toastHost.removeToast(modelData.key, true)
                }
                onReplyRequested: {
                    const targetConversationId = modelData.conversationId || 0
                    if (targetConversationId > 0) {
                        toastHost.conversationRequested(targetConversationId)
                        toastHost.removeToast(modelData.key, true)
                    }
                }
                onActionRequested: (category) => {
                    toastHost.actionRequested(category)
                    toastHost.removeToast(modelData.key, true)
                }
            }
        }
    }

    // ---- Pile "autres" (transfert/connexion/...) : haut-droite --------
    Column {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall
        width: 360

        Repeater {
            model: toastHost.otherQueue

            delegate: Toast {
                // Chaque Toast calcule sa propre largeur (pilule compacte,
                // ou groupe empile pour les rafales) ; on l'aligne a droite
                // de la colonne hote sans lui imposer une largeur.
                anchors.right: parent.right
                title: modelData.title
                message: modelData.message
                category: modelData.category
                count: modelData.count

                onDismissed: toastHost.removeToast(modelData.key, false)
                onActionRequested: (category) => {
                    toastHost.actionRequested(category)
                    toastHost.removeToast(modelData.key, false)
                }
            }
        }
    }

    function addToast(title, message, category, conversationId) {
        const isMessage = category === "message"
        const queue = isMessage ? messageQueue : otherQueue

        // Regroupement (design C) : si un toast de la meme categorie est
        // deja affiche dans la meme pile (rafale d'evenements identiques,
        // ex. plusieurs messages ou connexions coup sur coup), on
        // l'incremente au lieu d'empiler un nouveau toast individuel.
        const existingIndex = queue.findIndex(function(t) { return t.category === category })
        if (existingIndex !== -1) {
            const merged = queue.slice()
            const existing = merged[existingIndex]
            merged[existingIndex] = {
                key: existing.key,
                title: title,
                message: message,
                category: category,
                count: existing.count + 1,
                conversationId: conversationId || existing.conversationId || 0
            }
            if (isMessage) messageQueue = merged
            else otherQueue = merged
            return
        }

        const key = _nextKey++
        const updated = queue.concat([{ key: key, title: title, message: message, category: category,
                        count: 1, conversationId: conversationId || 0 }])
        const trimmed = updated.length > maxVisible ? updated.slice(updated.length - maxVisible) : updated
        if (isMessage) messageQueue = trimmed
        else otherQueue = trimmed
    }

    function removeToast(key, isMessage) {
        if (isMessage) {
            messageQueue = messageQueue.filter(function(t) { return t.key !== key })
        } else {
            otherQueue = otherQueue.filter(function(t) { return t.key !== key })
        }
    }

    Connections {
        target: userManager
        function onAuthenticationChanged() {
            if (!userManager.authenticated) {
                toastHost.messageQueue = []
                toastHost.otherQueue = []
            }
        }
    }

    Connections {
        target: notificationManager
        function onNotificationRequested(title, message, category, conversationId) {
            // Securite : un utilisateur non connecte (ecran de login) ne
            // doit ni voir de notification, ni pouvoir cliquer dessus pour
            // etre redirige vers une conversation/vue qui suppose une
            // session active.
            if (!userManager || !userManager.authenticated)
                return
            toastHost.addToast(title, message, category, conversationId || 0)
        }
    }
}
