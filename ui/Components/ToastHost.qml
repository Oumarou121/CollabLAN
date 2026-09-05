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
 * et empile chaque evenement notifiable (message, transfert,
 * connexion/deconnexion) sous forme de Toast.qml, du plus recent en haut.
 */
Item {
    id: root

    // z eleve pour rester au-dessus du StackView et de ses transitions.
    z: 1000
    anchors.fill: parent

    property var toastQueue: []
    property int _nextKey: 0

    // Nombre max de toasts affiches simultanement (les plus anciens sont
    // retires en premier) pour eviter d'inonder l'ecran en cas de rafale
    // d'evenements (ex. plusieurs postes qui se deconnectent d'un coup).
    readonly property int maxVisible: 4

    Column {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall
        width: 360

        Repeater {
            model: root.toastQueue

            delegate: Toast {
                // Chaque Toast calcule sa propre largeur (carte 360px pour
                // les messages, pilule compacte pour le reste, groupe
                // empile pour les rafales) ; on l'aligne a droite de la
                // colonne hote sans lui imposer une largeur.
                anchors.right: parent.right
                title: modelData.title
                message: modelData.message
                category: modelData.category
                count: modelData.count

                onDismissed: root.removeToast(modelData.key)
                // TODO: brancher sur la navigation reelle vers la
                // conversation une fois qu'un identifiant (senderId /
                // conversationId) sera transporte par notificationRequested.
                onReplyRequested: (senderName) => console.log("[ToastHost] Repondre demande pour", senderName)
            }
        }
    }

    function addToast(title, message, category) {
        // Regroupement (design C) : si un toast de la meme categorie est
        // deja affiche (rafale d'evenements identiques, ex. plusieurs
        // messages ou connexions coup sur coup), on l'incremente au lieu
        // d'empiler un nouveau toast individuel.
        const existingIndex = toastQueue.findIndex(function(t) { return t.category === category })
        if (existingIndex !== -1) {
            const merged = toastQueue.slice()
            const existing = merged[existingIndex]
            merged[existingIndex] = {
                key: existing.key,
                title: title,
                message: message,
                category: category,
                count: existing.count + 1
            }
            toastQueue = merged
            return
        }

        const key = _nextKey++
        const updated = toastQueue.concat([{ key: key, title: title, message: message, category: category, count: 1 }])
        toastQueue = updated.length > maxVisible ? updated.slice(updated.length - maxVisible) : updated
    }

    function removeToast(key) {
        toastQueue = toastQueue.filter(function(t) { return t.key !== key })
    }

    Connections {
        target: notificationManager
        function onNotificationRequested(title, message, category) {
            root.addToast(title, message, category)
        }
    }
}
