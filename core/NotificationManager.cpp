#include "NotificationManager.h"
#include "UserManager.h"

#include <QDebug>

namespace core {

NotificationManager::NotificationManager(QObject *parent)
    : QObject(parent)
{
}

NotificationManager::~NotificationManager()
{
}

void NotificationManager::onMessageReceived(const models::Message &message)
{
    qDebug() << "[NotificationManager] onMessageReceived called, enabled:" << m_notificationsEnabled;
    if (!m_notificationsEnabled) {
        qDebug() << "[NotificationManager] Notifications disabled, skipping";
        return;
    }

    // Titre = nom de l'expediteur quand il est resolvable (necessaire au
    // nouveau design de notification enrichi, qui affiche un avatar +
    // nom d'expediteur - cf. Toast.qml), sinon repli sur le titre
    // generique precedent.
    const QString senderName = m_userManager ? m_userManager->usernameForId(message.senderId()) : QString();
    const QString title = senderName.isEmpty() ? QStringLiteral("Nouveau message") : senderName;
    const QString notificationMessage = message.content();

    qDebug() << "[NotificationManager] Emitting notificationRequested for message:" << notificationMessage;
    emit notificationRequested(title, notificationMessage, QStringLiteral("message"),
                               message.conversationId());
}

void NotificationManager::onTransferCompleted(const QString &transferKey, const QString &filePath)
{
    Q_UNUSED(transferKey);

    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Transfert termine");
    // filePath est le chemin complet ; seul le nom de fichier interesse
    // l'utilisateur dans la notification.
    const QString fileName = filePath.section(QLatin1Char('/'), -1).section(QLatin1Char('\\'), -1);

    emit notificationRequested(title, fileName, QStringLiteral("transfer"));
}

void NotificationManager::onTransferFailed(const QString &transferKey, const QString &errorString)
{
    Q_UNUSED(transferKey);

    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Echec du transfert");

    emit notificationRequested(title, errorString, QStringLiteral("transfer"));
}

void NotificationManager::onPeerConnected(const QString &peerName)
{
    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Poste connecte");

    emit notificationRequested(title, peerName, QStringLiteral("connection"));
}

void NotificationManager::onPeerDisconnected(const QString &peerName)
{
    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Poste deconnecte");

    emit notificationRequested(title, peerName, QStringLiteral("disconnection"));
}

void NotificationManager::onGroupCreated(const models::Group &group)
{
    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Nouveau groupe");
    const QString message = QStringLiteral("Vous avez ete ajoute au groupe \"%1\"").arg(group.name());

    emit notificationRequested(title, message, QStringLiteral("group"));
}

void NotificationManager::onFolderCreated(const QString &folderName, const QString &ownerName)
{
    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Nouveau dossier partagé");
    const QString message = QStringLiteral("\"%1\" a partagé le dossier \"%2\" avec vous").arg(ownerName, folderName);

    emit notificationRequested(title, message, QStringLiteral("folder"));
}

void NotificationManager::onFolderAccessRevoked(const QString &folderName)
{
    if (!m_notificationsEnabled) {
        return;
    }

    const QString title = QStringLiteral("Accès révoqué");
    const QString message = QStringLiteral("Votre accès au dossier \"%1\" a été révoqué").arg(folderName);

    emit notificationRequested(title, message, QStringLiteral("folder"));
}

void NotificationManager::onFolderFilesReceived(const QString &folderUuid, const QString &folderName,
                                                 int fileCount, const QString &localPath)
{
    Q_UNUSED(folderUuid);

    if (!m_notificationsEnabled || fileCount <= 0) {
        return;
    }

    const QString title = QStringLiteral("Dossier synchronisé");
    // localPath peut être vide si le dossier n'a pas pu être retrouvé au
    // moment de l'appel (cf. Application.cpp) -- on retombe alors sur le
    // message sans emplacement plutôt que d'afficher "dans """.
    const QString message = localPath.isEmpty()
        ? (fileCount == 1
               ? QStringLiteral("1 fichier reçu dans \"%1\"").arg(folderName)
               : QStringLiteral("%1 fichiers reçus dans \"%2\"").arg(fileCount).arg(folderName))
        : (fileCount == 1
               ? QStringLiteral("\"%1\" synchronisé (1 fichier) dans %2").arg(folderName, localPath)
               : QStringLiteral("\"%1\" synchronisé (%2 fichiers) dans %3").arg(folderName).arg(fileCount).arg(localPath));

    // CORRECTIF (debrief : "le petit bilan récapitulatif de partage reste
    // bloqué sans disparaître") : ce récapitulatif était émis avec la
    // catégorie "transfer" -- la MÊME que chaque transfert de fichier
    // individuel (cf. onTransferCompleted() ci-dessus). ToastHost::
    // addToast() fusionne tout nouvel évènement de même catégorie dans le
    // toast déjà affiché et relance son minuteur d'auto-disparition
    // (Toast.qml, onCountChanged). Résultat : pendant toute la durée d'une
    // synchronisation de dossier avec plusieurs fichiers, CHAQUE fichier
    // individuel transféré repoussait la disparition de ce récapitulatif
    // -- qui ne disparaissait donc jamais tant que la rafale de transferts
    // ne s'arrêtait pas pendant plus de 4s (cf. Toast::duration). Catégorie
    // "folder" (déjà utilisée par onFolderCreated()/onFolderAccessRevoked()
    // ci-dessus, jamais en rafale rapide) : ce récapitulatif vit
    // desormais sa propre vie, independante des transferts de fichiers
    // individuels en cours.
    emit notificationRequested(title, message, QStringLiteral("folder"));
}

void NotificationManager::onFolderFilesSent(const QString &folderUuid, const QString &folderName, int fileCount)
{
    Q_UNUSED(folderUuid);

    if (!m_notificationsEnabled || fileCount <= 0) {
        return;
    }

    const QString title = QStringLiteral("Dossier envoyé");
    const QString message = fileCount == 1
        ? QStringLiteral("1 fichier envoyé depuis \"%1\"").arg(folderName)
        : QStringLiteral("%1 fichiers envoyés depuis \"%2\"").arg(fileCount).arg(folderName);

    // CORRECTIF : même raison que onFolderFilesReceived() ci-dessus --
    // "folder" plutôt que "transfer", pour ne plus se faire perpétuellement
    // repousser par chaque fichier individuel envoyé pendant la rafale.
    emit notificationRequested(title, message, QStringLiteral("folder"));
}

} // namespace core