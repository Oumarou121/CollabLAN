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
    if (m_userManager == manager) {
        return;
    }

    if (m_userManager) {
        disconnect(m_userManager, nullptr, this, nullptr);
    }

    m_userManager = manager;

    if (m_userManager) {
        connect(m_userManager, &UserManager::authenticationChanged,
                this, &TransferContext::loadHistory);
        connect(m_userManager, &UserManager::usersChanged,
                this, &TransferContext::loadHistory);
    }

    // Refait le calcul Envoi/Reception de l'historique deja charge
    // (base sur senderUuid == utilisateur courant), potentiellement
    // indetermine si setUserManager() est appele apres setTransferManager()
    // ou avant la connexion effective de l'utilisateur.
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
        // id (UUID DiscoveryService) : indispensable pour que sendFile()
        // puisse transmettre le peerMachineId exact du destinataire choisi,
        // au lieu de le re-deviner plus tard par adresse IP (fragile sur
        // machine multi-interfaces, voir sendFile()/resolvePeerMachineId()).
        entry[QStringLiteral("id")] = m_peersModel->data(idx, network::PeersModel::IdRole);
        list.append(entry);
    }

    return list;
}

bool TransferContext::sendFile(const QString &filePath, const QString &address, int portHint,
                                const QString &peerMachineId)
{
    return sendFileWithRelativeDir(filePath, address, portHint, peerMachineId, QString());
}

bool TransferContext::sendFolder(const QString &folderPath, const QString &address, int portHint,
                                  const QString &peerMachineId)
{
    const QUrl url(folderPath);
    const QString localPath = url.isLocalFile() ? url.toLocalFile() : folderPath;

    const QFileInfo rootInfo(localPath);
    if (!rootInfo.exists() || !rootInfo.isDir()) {
        emit transferRejected(tr("Dossier introuvable : %1").arg(localPath));
        return false;
    }

    // Le nom du dossier choisi devient la racine recreee cote reception
    // (voir relativeDirPath dans TransferService::encodeHeader()), pour
    // que le destinataire retrouve la meme arborescence que celle
    // envoyee plutot que son seul contenu deverse a plat.
    const QString rootName = rootInfo.fileName();
    const QDir rootDir(localPath);

    QDirIterator it(localPath, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    bool anyQueued = false;
    while (it.hasNext()) {
        const QString absoluteFilePath = it.next();
        const QString relativeFromRoot = rootDir.relativeFilePath(absoluteFilePath);
        const QString relativeDirOfFile = QFileInfo(relativeFromRoot).path();
        const QString relativeDirPath = (relativeDirOfFile == QLatin1String("."))
            ? rootName
            : rootName + QLatin1Char('/') + relativeDirOfFile;

        if (sendFileWithRelativeDir(absoluteFilePath, address, portHint, peerMachineId, relativeDirPath)) {
            anyQueued = true;
        }
    }

    if (!anyQueued) {
        emit transferRejected(tr("Aucun fichier n'a pu être envoyé depuis %1").arg(rootName));
    }
    return anyQueued;
}

bool TransferContext::sendFileWithRelativeDir(const QString &filePath, const QString &address, int portHint,
                                               const QString &peerMachineId, const QString &relativeDirPath)
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
    // (issue #55, migration #017).
    const QString senderUuid = m_userManager ? m_userManager->currentUserUuid() : QString();

    // CORRECTIF (bug #2 : recipient_uuid toujours vide) : DiscoveryService
    // diffuse desormais aussi l'UUID du compte utilisateur connecte sur
    // chaque poste (cf. DiscoveryService::setLocalUserUuid(), alimente sur
    // authenticationChanged dans Application.cpp), en plus du nom "lisible"
    // qu'il diffusait deja. On peut donc resoudre recipientUuid a partir du
    // peerMachineId choisi par l'utilisateur, exactement comme peer_name
    // est deja resolu ailleurs (resolvePeerName()). Reste vide si le pair
    // n'a jamais authentifie de compte (ou n'est plus dans peersModel() au
    // moment de l'envoi) : dans ce cas l'historique reste sans compte
    // associe, comme avant ce correctif, mais sans jamais deviner un
    // identifiant errone.
    const QString recipientUuid = m_peersModel
        ? m_peersModel->userUuidForMachineId(peerMachineId)
        : QString();

    // TransferService::transferStarted() (qui alimente activeTransfers)
    // n'est emis qu'une fois la connexion TCP etablie, de maniere
    // asynchrone : on memorise le chemin local ici, indexe par nom de
    // fichier, pour pouvoir renseigner "filePath" sur l'entree des que
    // onTransferStarted() la cree (voir m_pendingSendFilePaths).
    const QString fileName = info.fileName();
    m_pendingSendFilePaths[fileName].append(localPath);
    m_pendingSendPorts[fileName].append(static_cast<int>(port));

    const bool started = m_transferManager->sendFile(host, port, localPath, senderUuid, recipientUuid,
                                                       peerMachineId, relativeDirPath);
    if (!started) {
        QStringList &pending = m_pendingSendFilePaths[fileName];
        pending.removeOne(localPath);
        if (pending.isEmpty()) {
            m_pendingSendFilePaths.remove(fileName);
        }
        QList<int> &pendingPorts = m_pendingSendPorts[fileName];
        pendingPorts.removeOne(static_cast<int>(port));
        if (pendingPorts.isEmpty()) {
            m_pendingSendPorts.remove(fileName);
        }
        emit transferRejected(tr("Impossible de demarrer l'envoi de %1").arg(info.fileName()));
    }

    return started;
}

bool TransferContext::retryTransfer(const QString &transferKey)
{
    const int index = indexOfTransfer(transferKey);
    if (index < 0) {
        emit transferRejected(tr("Transfert introuvable."));
        return false;
    }

    const QVariantMap entry = m_activeTransfers.at(index).toMap();

    // Seul un ENVOI en echec peut etre relance : nous avons toujours le
    // fichier local dans ce cas. Une RECEPTION echouee ne peut etre
    // relancee que par l'expediteur (aucune action locale possible).
    if (entry.value(QStringLiteral("statusText")).toString() != tr("Échoué")) {
        emit transferRejected(tr("Seul un transfert en echec peut etre relance."));
        return false;
    }
    if (entry.value(QStringLiteral("direction")).toString() != tr("Envoi")) {
        emit transferRejected(tr("Seul l'expediteur peut relancer ce transfert."));
        return false;
    }

    const QString filePath = entry.value(QStringLiteral("filePath")).toString();
    const QString peerAddress = entry.value(QStringLiteral("peerAddress")).toString();
    if (filePath.isEmpty() || peerAddress.isEmpty()) {
        emit transferRejected(tr("Impossible de relancer : fichier ou destinataire inconnu."));
        return false;
    }

    // Reprend le port actuellement annonce par le pair (peut avoir changé
    // depuis l'echec initial). S'il n'est plus decouvert dans
    // m_peersModel, on prefere le dernier port reellement utilise par ce
    // transfert (memorise dans l'entree "port" au moment du sendFile()
    // initial) plutot que de deviner network::TransferService::defaultPort() :
    // le pair a tres bien pu ecouter sur un port different du port par
    // defaut (voir issue de test transfercontext::retryTransfer...
    // AfterPeerReturns, qui echouait silencieusement pour cette raison
    // avant ce correctif). sendFile() ne retombe sur defaultPort() que si
    // meme ce dernier port connu est absent (portHint <= 0).
    const int discoveredPort = resolvePeerPort(peerAddress);
    const int lastKnownPort = entry.value(QStringLiteral("port")).toInt();
    const int portHint = discoveredPort > 0 ? discoveredPort : lastKnownPort;

    // sendFile() revalide fichier/adresse et delegue a
    // TransferManager::sendFile() -> network::TransferService::sendFile(),
    // qui reconnait automatiquement le ".part" partiel deja recu cote
    // destinataire et reprend a partir du dernier octet confirme (voir la
    // documentation de retryTransfer() dans TransferContext.h).
    return sendFile(filePath, peerAddress, portHint);
}

int TransferContext::resolvePeerPort(const QString &peerAddress) const
{
    if (!m_peersModel || peerAddress.isEmpty()) {
        return -1;
    }

    const QHostAddress target(peerAddress);
    if (target.isNull()) {
        return -1;
    }

    const int rows = m_peersModel->rowCount();
    for (int row = 0; row < rows; ++row) {
        const QModelIndex idx = m_peersModel->index(row, 0);
        const QString address = m_peersModel->data(idx, network::PeersModel::AddressRole).toString();
        // Comparaison tolerante : voir resolvePeerName() ci-dessus pour le
        // detail (adresses IPv4-mappees en IPv6 sur connexion entrante).
        if (QHostAddress(address).isEqual(target, QHostAddress::TolerantConversion)) {
            const int port = m_peersModel->data(idx, network::PeersModel::TransferPortRole).toInt();
            return port > 0 ? port : -1;
        }
    }
    return -1;
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
                                         const QString &peerMachineId, bool isFolderTransfer)
{

    // CORRECTIF : les transferts de synchronisation de dossier ne doivent
    // pas apparaitre dans l'UI de transfert manuel (activeTransfers), au
    // meme titre qu'ils ne sont pas persistes en base (voir le meme
    // filtre dans TransferManager::onNetworkTransferStarted()).
    // transferProgress/transferCompleted/transferFailed ne portent pas ce
    // flag : on retient donc la cle ici pour les ignorer eux aussi.
    if (isFolderTransfer) {
        m_folderSyncTransferKeys.insert(transferKey);
        return;
    }

    QVariantMap entry;
    entry[QStringLiteral("transferKey")] = transferKey;
    entry[QStringLiteral("fileName")] = fileName;
    entry[QStringLiteral("direction")] = incoming ? tr("Réception") : tr("Envoi");
    entry[QStringLiteral("incoming")] = incoming;
    entry[QStringLiteral("statusText")] = tr("En cours");
    entry[QStringLiteral("state")] = QStringLiteral("in_progress");
    entry[QStringLiteral("bytesTransferred")] = resumeOffset;
    entry[QStringLiteral("totalBytes")] = fileSize;
    entry[QStringLiteral("percent")] = percentOf(resumeOffset, fileSize);
    entry[QStringLiteral("errorString")] = QString();
    entry[QStringLiteral("peerAddress")] = peerAddress.isNull() ? QString() : peerAddress.toString();
    entry[QStringLiteral("peerName")] = resolvePeerName(peerAddress, peerMachineId);
    entry[QStringLiteral("peerMachineId")] = peerMachineId;
    entry[QStringLiteral("senderUuid")] = senderUuid;
    entry[QStringLiteral("recipientUuid")] = recipientUuid;
    const QString currentUserUuid = m_userManager ? m_userManager->currentUserUuid() : QString();
    const QString peerUserUuid = (!currentUserUuid.isEmpty() && senderUuid == currentUserUuid)
        ? recipientUuid
        : senderUuid;
    entry[QStringLiteral("peerUserUuid")] = peerUserUuid;
    entry[QStringLiteral("peerUserName")] = m_userManager ? m_userManager->userNameForUuid(peerUserUuid) : QString();
    entry[QStringLiteral("timestamp")] = QDateTime::currentDateTime().toString(Qt::ISODate);

    // Pour un envoi, le chemin local est deja connu (voir sendFile()) ;
    // pour une reception, il ne sera connu qu'a la fin du transfert
    // (dossier de reception + nom de fichier final, voir onTransferCompleted()).
    QString filePath;
    int sendPort = 0;
    if (!incoming) {
        QStringList &pending = m_pendingSendFilePaths[fileName];
        if (!pending.isEmpty()) {
            filePath = pending.takeFirst();
            if (pending.isEmpty()) {
                m_pendingSendFilePaths.remove(fileName);
            }
        }
        // Pris dans le meme ordre (FIFO) que filePath ci-dessus : les deux
        // listes sont alimentees ensemble par sendFile() pour chaque envoi
        // de ce fileName, donc restent alignees meme en cas d'envois
        // concurrents du meme nom de fichier vers des destinations differentes.
        QList<int> &pendingPorts = m_pendingSendPorts[fileName];
        if (!pendingPorts.isEmpty()) {
            sendPort = pendingPorts.takeFirst();
            if (pendingPorts.isEmpty()) {
                m_pendingSendPorts.remove(fileName);
            }
        }
    }
    entry[QStringLiteral("filePath")] = filePath;
    entry[QStringLiteral("port")] = sendPort;

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
    if (m_folderSyncTransferKeys.contains(transferKey)) {
        return;
    }

    const int index = indexOfTransfer(transferKey);
    if (index < 0) {
        // Progression pour un transfert dont on n'a pas vu le demarrage
        // (ex. contexte cree apres coup) : on cree une entree minimale
        // plutot que de perdre l'information de progression.
        QVariantMap entry;
        entry[QStringLiteral("transferKey")] = transferKey;
        entry[QStringLiteral("fileName")] = tr("Transfert en cours");
        entry[QStringLiteral("direction")] = QString();
        // Sens inconnu ici (progression recue avant le signal de demarrage,
        // voir le commentaire ci-dessus) : par defaut "sortant" plutot que
        // de deviner, a corriger si onTransferStarted() finit par arriver
        // pour cette cle.
        entry[QStringLiteral("incoming")] = false;
        entry[QStringLiteral("statusText")] = tr("En cours");
        entry[QStringLiteral("state")] = QStringLiteral("in_progress");
        entry[QStringLiteral("bytesTransferred")] = bytesTransferred;
        entry[QStringLiteral("totalBytes")] = totalBytes;
        entry[QStringLiteral("percent")] = percentOf(bytesTransferred, totalBytes);
        entry[QStringLiteral("errorString")] = QString();
        entry[QStringLiteral("filePath")] = QString();
        entry[QStringLiteral("peerAddress")] = QString();
        entry[QStringLiteral("peerName")] = QString();
        entry[QStringLiteral("peerMachineId")] = QString();
        entry[QStringLiteral("senderUuid")] = QString();
        entry[QStringLiteral("recipientUuid")] = QString();
        entry[QStringLiteral("peerUserUuid")] = QString();
        entry[QStringLiteral("peerUserName")] = QString();
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
    if (m_folderSyncTransferKeys.remove(transferKey)) {
        return;
    }

    const int index = indexOfTransfer(transferKey);
    if (index < 0) {
        return;
    }

    QVariantMap entry = m_activeTransfers.at(index).toMap();
    entry[QStringLiteral("statusText")] = tr("Terminé");
    entry[QStringLiteral("state")] = QStringLiteral("completed");
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
    if (m_folderSyncTransferKeys.remove(transferKey)) {
        return;
    }

    const int index = indexOfTransfer(transferKey);
    if (index < 0) {
        return;
    }

    QVariantMap entry = m_activeTransfers.at(index).toMap();
    entry[QStringLiteral("statusText")] = tr("Échoué");
    entry[QStringLiteral("state")] = QStringLiteral("failed");
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
    bool incoming = true;
    if (m_userManager && !m_userManager->currentUserUuid().isEmpty()
        && transfer.senderUuid() == m_userManager->currentUserUuid()) {
        incoming = false;
    }
    const QString direction = incoming ? tr("Réception") : tr("Envoi");

    QString statusText;
    QString state;
    qint64 bytesTransferred = 0;
    switch (transfer.status()) {
    case models::TransferStatus::Completed:
        statusText = tr("Terminé");
        state = QStringLiteral("completed");
        bytesTransferred = transfer.fileSize();
        break;
    case models::TransferStatus::Failed:
        statusText = tr("Échoué");
        state = QStringLiteral("failed");
        break;
    case models::TransferStatus::Cancelled:
        statusText = tr("Annulé");
        state = QStringLiteral("cancelled");
        break;
    case models::TransferStatus::InProgress:
    case models::TransferStatus::Pending:
    default:
        // Reste "in_progress"/"pending" en base uniquement si l'application
        // a ete fermee (ou a plante) avant la fin reelle du transfert :
        // le transfert reseau n'existe plus, donc "En cours" serait
        // trompeur (rien ne progresse plus). On l'affiche comme interrompu.
        statusText = tr("Interrompu");
        state = QStringLiteral("interrupted");
        break;
    }

    QVariantMap entry;
    entry[QStringLiteral("transferKey")] = QStringLiteral("history:%1").arg(transfer.id());
    entry[QStringLiteral("fileName")] = transfer.fileName();
    entry[QStringLiteral("direction")] = direction;
    entry[QStringLiteral("incoming")] = incoming;
    entry[QStringLiteral("statusText")] = statusText;
    entry[QStringLiteral("state")] = state;
    entry[QStringLiteral("bytesTransferred")] = bytesTransferred;
    entry[QStringLiteral("totalBytes")] = transfer.fileSize();
    entry[QStringLiteral("percent")] = percentOf(bytesTransferred, transfer.fileSize());
    entry[QStringLiteral("errorString")] = QString();
    entry[QStringLiteral("filePath")] = transfer.filePath();
    entry[QStringLiteral("peerAddress")] = transfer.peerAddress();
    entry[QStringLiteral("peerName")] = transfer.peerName();
    // Identifiant machine stable necessaire au regroupement des historiques dans QML.
    entry[QStringLiteral("peerMachineId")] = transfer.peerMachineId();
    entry[QStringLiteral("senderUuid")] = transfer.senderUuid();
    entry[QStringLiteral("recipientUuid")] = transfer.recipientUuid();
    const QString currentUserUuid = m_userManager ? m_userManager->currentUserUuid() : QString();
    const QString peerUserUuid = (!currentUserUuid.isEmpty() && transfer.senderUuid() == currentUserUuid)
        ? transfer.recipientUuid()
        : transfer.senderUuid();
    entry[QStringLiteral("peerUserUuid")] = peerUserUuid;
    entry[QStringLiteral("peerUserName")] = m_userManager ? m_userManager->userNameForUuid(peerUserUuid) : QString();
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