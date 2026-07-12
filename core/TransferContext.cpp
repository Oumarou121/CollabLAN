#include "TransferContext.h"

#include <QDebug>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QHostAddress>
#include <QProcess>
#include <QUrl>

namespace core {

TransferContext::TransferContext(QObject *parent)
    : QObject(parent)
{
}

TransferContext::~TransferContext() = default;

void TransferContext::setTransferManager(TransferManager *manager)
{
    if (m_transferManager == manager) {
        return;
    }

    m_transferManager = manager;
    emit transferManagerChanged();

    // Recharge l'historique persiste (issue : "plus aucun fichier visible
    // apres redemarrage de l'app"). A ce stade m_userManager peut ne pas
    // encore etre renseigne (voir main.cpp, setUserManager() appele en
    // dernier) : loadHistory() est donc appelee a nouveau depuis
    // setUserManager() pour affiner la direction Envoi/Reception une fois
    // l'utilisateur courant connu.
    loadHistory();
}

void TransferContext::setTransferService(network::TransferService *service)
{
    if (m_transferService == service) {
        return;
    }

    if (m_transferService) {
        disconnect(m_transferService, nullptr, this, nullptr);
    }

    m_transferService = service;

    if (m_transferService) {
        // TransferManager ne relaie pas transferProgress() (il ne s'occupe
        // que de la persistance) : on ecoute directement TransferService
        // pour obtenir la progression en temps reel (issue #57).
        connect(m_transferService, &network::TransferService::transferStarted,
                this, &TransferContext::onTransferStarted);
        connect(m_transferService, &network::TransferService::transferProgress,
                this, &TransferContext::onTransferProgress);
        connect(m_transferService, &network::TransferService::transferCompleted,
                this, &TransferContext::onTransferCompleted);
        connect(m_transferService, &network::TransferService::transferFailed,
                this, &TransferContext::onTransferFailed);
    }

    emit transferServiceChanged();
}

void TransferContext::setPeersModel(network::PeersModel *model)
{
    if (m_peersModel == model) {
        return;
    }

    m_peersModel = model;
    emit peersModelChanged();
}

void TransferContext::setUserManager(UserManager *manager)
{
    m_userManager = manager;

    // Refait le calcul Envoi/Reception de l'historique deja charge
    // (base sur senderUuid == utilisateur courant), potentiellement
    // indetermine si setUserManager() est appele apres setTransferManager().
    loadHistory();
}

QString TransferContext::resolvePeerName(const QHostAddress &peerAddress, const QString &peerMachineId) const
{
    if (!m_peersModel) {
        return QString();
    }

    const int rows = m_peersModel->rowCount();

    // Priorite a l'UUID (voir la documentation de resolvePeerName() dans
    // TransferContext.h) : insensible a l'interface reseau empruntee,
    // contrairement a l'adresse IP.
    if (!peerMachineId.isEmpty()) {
        for (int row = 0; row < rows; ++row) {
            const QModelIndex idx = m_peersModel->index(row, 0);
            const QString peerId = m_peersModel->data(idx, network::PeersModel::IdRole).toString();
            if (peerId == peerMachineId) {
                return m_peersModel->data(idx, network::PeersModel::NameRole).toString();
            }
        }
    }

    if (peerAddress.isNull()) {
        return QString();
    }
    for (int row = 0; row < rows; ++row) {
        const QModelIndex idx = m_peersModel->index(row, 0);
        const QString address = m_peersModel->data(idx, network::PeersModel::AddressRole).toString();
        // Comparaison tolerante (QHostAddress::isEqual + TolerantConversion) :
        // operator== compare par defaut en mode StrictConversion, qui ne
        // reconnait pas "::ffff:192.168.1.1" (adresse IPv4-mappee, souvent
        // rapportee par QTcpSocket::peerAddress() sur une connexion
        // entrante en double pile) comme egale a "192.168.1.1".
        if (QHostAddress(address).isEqual(peerAddress, QHostAddress::TolerantConversion)) {
            return m_peersModel->data(idx, network::PeersModel::NameRole).toString();
        }
    }
    return QString();
}

QVariantList TransferContext::availableRecipients() const
{
    QVariantList list;

    if (!m_peersModel) {
        return list;
    }

    const int rows = m_peersModel->rowCount();
    for (int row = 0; row < rows; ++row) {
        const QModelIndex idx = m_peersModel->index(row, 0);

        QVariantMap entry;
        entry[QStringLiteral("name")] = m_peersModel->data(idx, network::PeersModel::NameRole);
        entry[QStringLiteral("address")] = m_peersModel->data(idx, network::PeersModel::AddressRole);
        entry[QStringLiteral("port")] = m_peersModel->data(idx, network::PeersModel::TransferPortRole);
        entry[QStringLiteral("status")] = m_peersModel->data(idx, network::PeersModel::StatusRole);
        list.append(entry);
    }

    return list;
}

bool TransferContext::sendFile(const QString &filePath, const QString &address, int portHint)
{
    if (!m_transferManager) {
        emit transferRejected(tr("Le service de transfert n'est pas disponible."));
        return false;
    }

    // filePath peut etre soit un chemin local classique, soit l'URL brute
    // renvoyee par FileDialog en QML (ex. "file:///C:/chemin/fichier.ext"
    // sous Windows, avec 3 slashes). QUrl::toLocalFile() gere correctement
    // ce cas sur toutes les plateformes ; un decoupage regex manuel cote
    // QML (ex. remplacer juste "file://") laisse un slash en trop devant
    // la lettre de lecteur ("/C:/...") et rend le chemin invalide.
    const QUrl url(filePath);
    const QString localPath = url.isLocalFile() ? url.toLocalFile() : filePath;

    const QFileInfo info(localPath);
    if (!info.exists() || !info.isFile() || !info.isReadable()) {
        emit transferRejected(tr("Fichier introuvable ou illisible : %1").arg(localPath));
        return false;
    }

    const QHostAddress host(address);
    if (host.isNull()) {
        emit transferRejected(tr("Adresse de destination invalide : %1").arg(address));
        return false;
    }

    const quint16 port = portHint > 0 ? static_cast<quint16>(portHint)
                                       : network::TransferService::defaultPort();

    // senderUuid identifie l'utilisateur courant dans l'historique persiste
    // (issue #55, migration #017) ; recipientUuid n'est pas resolvable a
    // partir d'un poste reseau (aucun compte utilisateur associe a un pair
    // decouvert), donc laisse vide plutot que de deviner un identifiant
    // errone (voir peer_machine_id, migration #016, pour l'identification
    // fiable du poste lui-meme).
    const QString senderUuid = m_userManager ? m_userManager->currentUserUuid() : QString();
    const QString recipientUuid;

    // TransferService::transferStarted() (qui alimente activeTransfers)
    // n'est emis qu'une fois la connexion TCP etablie, de maniere
    // asynchrone : on memorise le chemin local ici, indexe par nom de
    // fichier, pour pouvoir renseigner "filePath" sur l'entree des que
    // onTransferStarted() la cree (voir m_pendingSendFilePaths).
    const QString fileName = info.fileName();
    m_pendingSendFilePaths[fileName].append(localPath);

    const bool started = m_transferManager->sendFile(host, port, localPath, senderUuid, recipientUuid);
    if (!started) {
        QStringList &pending = m_pendingSendFilePaths[fileName];
        pending.removeOne(localPath);
        if (pending.isEmpty()) {
            m_pendingSendFilePaths.remove(fileName);
        }
        emit transferRejected(tr("Impossible de demarrer l'envoi de %1").arg(info.fileName()));
    }

    return started;
}

int TransferContext::indexOfTransfer(const QString &transferKey) const
{
    for (int i = 0; i < m_activeTransfers.size(); ++i) {
        const QVariantMap entry = m_activeTransfers.at(i).toMap();
        if (entry.value(QStringLiteral("transferKey")).toString() == transferKey) {
            return i;
        }
    }
    return -1;
}

int TransferContext::percentOf(qint64 bytesTransferred, qint64 totalBytes)
{
    if (totalBytes <= 0) {
        return 0;
    }
    const qint64 percent = (bytesTransferred * 100) / totalBytes;
    return static_cast<int>(qBound(qint64(0), percent, qint64(100)));
}

void TransferContext::onTransferStarted(const QString &transferKey, const QString &fileName, qint64 fileSize,
                                         bool incoming, qint64 resumeOffset, const QString &senderUuid,
                                         const QString &recipientUuid, const QHostAddress &peerAddress,
                                         const QString &peerMachineId)
{
    Q_UNUSED(senderUuid)
    Q_UNUSED(recipientUuid)

    QVariantMap entry;
    entry[QStringLiteral("transferKey")] = transferKey;
    entry[QStringLiteral("fileName")] = fileName;
    entry[QStringLiteral("direction")] = incoming ? tr("Reception") : tr("Envoi");
    entry[QStringLiteral("statusText")] = tr("En cours");
    entry[QStringLiteral("bytesTransferred")] = resumeOffset;
    entry[QStringLiteral("totalBytes")] = fileSize;
    entry[QStringLiteral("percent")] = percentOf(resumeOffset, fileSize);
    entry[QStringLiteral("errorString")] = QString();
    entry[QStringLiteral("peerAddress")] = peerAddress.isNull() ? QString() : peerAddress.toString();
    entry[QStringLiteral("peerName")] = resolvePeerName(peerAddress, peerMachineId);
    entry[QStringLiteral("timestamp")] = QDateTime::currentDateTime().toString(Qt::ISODate);

    // Pour un envoi, le chemin local est deja connu (voir sendFile()) ;
    // pour une reception, il ne sera connu qu'a la fin du transfert
    // (dossier de reception + nom de fichier final, voir onTransferCompleted()).
    QString filePath;
    if (!incoming) {
        QStringList &pending = m_pendingSendFilePaths[fileName];
        if (!pending.isEmpty()) {
            filePath = pending.takeFirst();
            if (pending.isEmpty()) {
                m_pendingSendFilePaths.remove(fileName);
            }
        }
    }
    entry[QStringLiteral("filePath")] = filePath;

    const int existing = indexOfTransfer(transferKey);
    if (existing >= 0) {
        m_activeTransfers[existing] = entry;
    } else {
        m_activeTransfers.append(entry);
    }

    emit activeTransfersChanged();
}

void TransferContext::onTransferProgress(const QString &transferKey, qint64 bytesTransferred, qint64 totalBytes)
{
    const int index = indexOfTransfer(transferKey);
    if (index < 0) {
        // Progression pour un transfert dont on n'a pas vu le demarrage
        // (ex. contexte cree apres coup) : on cree une entree minimale
        // plutot que de perdre l'information de progression.
        QVariantMap entry;
        entry[QStringLiteral("transferKey")] = transferKey;
        entry[QStringLiteral("fileName")] = tr("Transfert en cours");
        entry[QStringLiteral("direction")] = QString();
        entry[QStringLiteral("statusText")] = tr("En cours");
        entry[QStringLiteral("bytesTransferred")] = bytesTransferred;
        entry[QStringLiteral("totalBytes")] = totalBytes;
        entry[QStringLiteral("percent")] = percentOf(bytesTransferred, totalBytes);
        entry[QStringLiteral("errorString")] = QString();
        entry[QStringLiteral("filePath")] = QString();
        entry[QStringLiteral("peerAddress")] = QString();
        entry[QStringLiteral("peerName")] = QString();
        entry[QStringLiteral("timestamp")] = QDateTime::currentDateTime().toString(Qt::ISODate);
        m_activeTransfers.append(entry);
        emit activeTransfersChanged();
        return;
    }

    QVariantMap entry = m_activeTransfers.at(index).toMap();
    entry[QStringLiteral("bytesTransferred")] = bytesTransferred;
    entry[QStringLiteral("totalBytes")] = totalBytes;
    entry[QStringLiteral("percent")] = percentOf(bytesTransferred, totalBytes);
    m_activeTransfers[index] = entry;

    emit activeTransfersChanged();
}

void TransferContext::onTransferCompleted(const QString &transferKey, const QString &filePath)
{
    const int index = indexOfTransfer(transferKey);
    if (index < 0) {
        return;
    }

    QVariantMap entry = m_activeTransfers.at(index).toMap();
    entry[QStringLiteral("statusText")] = tr("Termine");
    entry[QStringLiteral("percent")] = 100;
    entry[QStringLiteral("bytesTransferred")] = entry.value(QStringLiteral("totalBytes"));
    // filePath est le chemin final ecrit par TransferService : pour une
    // reception, c'est la premiere fois qu'il est connu (dossier de
    // reception + nom de fichier, une fois le ".part" renomme) ; pour un
    // envoi il correspond au chemin local deja renseigne dans
    // onTransferStarted(), donc sans effet ici.
    if (!filePath.isEmpty()) {
        entry[QStringLiteral("filePath")] = filePath;
    }
    m_activeTransfers[index] = entry;

    emit activeTransfersChanged();
}

void TransferContext::onTransferFailed(const QString &transferKey, const QString &errorString)
{
    const int index = indexOfTransfer(transferKey);
    if (index < 0) {
        return;
    }

    QVariantMap entry = m_activeTransfers.at(index).toMap();
    entry[QStringLiteral("statusText")] = tr("Echoue");
    entry[QStringLiteral("errorString")] = errorString;
    m_activeTransfers[index] = entry;

    emit activeTransfersChanged();
}

void TransferContext::loadHistory()
{
    m_activeTransfers.clear();

    if (m_transferManager) {
        const std::vector<models::Transfer> history = m_transferManager->allTransfers();
        // allTransfers() renvoie le plus recent en premier (ORDER BY
        // created_at DESC en base) ; activeTransfers() documente
        // l'inverse (le plus recent en dernier, coherent avec l'ajout de
        // chaque nouveau transfert via append()), d'ou le parcours en
        // sens inverse ci-dessous.
        for (auto it = history.rbegin(); it != history.rend(); ++it) {
            m_activeTransfers.append(entryFromHistory(*it));
        }
    }

    emit activeTransfersChanged();
}

QVariantMap TransferContext::entryFromHistory(const models::Transfer &transfer) const
{
    QString direction = tr("Reception");
    if (m_userManager && !m_userManager->currentUserUuid().isEmpty()
        && transfer.senderUuid() == m_userManager->currentUserUuid()) {
        direction = tr("Envoi");
    }

    QString statusText;
    qint64 bytesTransferred = 0;
    switch (transfer.status()) {
    case models::TransferStatus::Completed:
        statusText = tr("Termine");
        bytesTransferred = transfer.fileSize();
        break;
    case models::TransferStatus::Failed:
        statusText = tr("Echoue");
        break;
    case models::TransferStatus::Cancelled:
        statusText = tr("Annule");
        break;
    case models::TransferStatus::InProgress:
    case models::TransferStatus::Pending:
    default:
        // Reste "in_progress"/"pending" en base uniquement si l'application
        // a ete fermee (ou a plante) avant la fin reelle du transfert :
        // le transfert reseau n'existe plus, donc "En cours" serait
        // trompeur (rien ne progresse plus). On l'affiche comme interrompu.
        statusText = tr("Interrompu");
        break;
    }

    QVariantMap entry;
    entry[QStringLiteral("transferKey")] = QStringLiteral("history:%1").arg(transfer.id());
    entry[QStringLiteral("fileName")] = transfer.fileName();
    entry[QStringLiteral("direction")] = direction;
    entry[QStringLiteral("statusText")] = statusText;
    entry[QStringLiteral("bytesTransferred")] = bytesTransferred;
    entry[QStringLiteral("totalBytes")] = transfer.fileSize();
    entry[QStringLiteral("percent")] = percentOf(bytesTransferred, transfer.fileSize());
    entry[QStringLiteral("errorString")] = QString();
    entry[QStringLiteral("filePath")] = transfer.filePath();
    entry[QStringLiteral("peerAddress")] = transfer.peerAddress();
    entry[QStringLiteral("peerName")] = transfer.peerName();
    entry[QStringLiteral("timestamp")] = transfer.createdAt().toLocalTime().toString(Qt::ISODate);
    return entry;
}

bool TransferContext::openFileLocation(const QString &filePath) const
{
    if (filePath.isEmpty()) {
        return openDownloadsFolder();
    }

    const QFileInfo info(filePath);
    if (info.exists()) {
#ifdef Q_OS_WIN
        // "Reveal in Explorer" : ouvre le dossier parent en selectionnant
        // le fichier, plus pratique que de deposer l'utilisateur dans un
        // dossier sans indication de quel fichier y chercher.
        QProcess::startDetached(QStringLiteral("explorer.exe"),
                                 {QStringLiteral("/select,"), QDir::toNativeSeparators(info.absoluteFilePath())});
        return true;
#else
        return QDesktopServices::openUrl(QUrl::fromLocalFile(info.absolutePath()));
#endif
    }

    // Le fichier a ete deplace/supprime depuis : essaie au moins le
    // dossier parent s'il existe encore, sinon retombe sur le dossier de
    // reception par defaut plutot que de ne rien faire.
    const QDir parentDir(info.absolutePath());
    if (!info.absolutePath().isEmpty() && parentDir.exists()) {
        return QDesktopServices::openUrl(QUrl::fromLocalFile(parentDir.absolutePath()));
    }

    return openDownloadsFolder();
}

bool TransferContext::openDownloadsFolder() const
{
    if (!m_transferService) {
        return false;
    }

    const QString dir = m_transferService->receiveDirectory();
    if (dir.isEmpty()) {
        return false;
    }

    // Le dossier n'existe que s'il a deja servi a recevoir un fichier
    // (cree a la volee par TransferService) : le creer ici si besoin pour
    // que le bouton fonctionne meme avant toute reception.
    QDir().mkpath(dir);

    return QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
}

} // namespace core