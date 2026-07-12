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
                width: 360
                title: modelData.title
                message: modelData.message
                category: modelData.category

                onDismissed: root.removeToast(modelData.key)
            }
        }
    }

    function addToast(title, message, category) {
        const key = _nextKey++
        const updated = toastQueue.concat([{ key: key, title: title, message: message, category: category }])
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
