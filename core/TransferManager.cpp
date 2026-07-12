#include "TransferManager.h"

#include <QDebug>
#include <QFileInfo>

#include "database/DatabaseManager.h"
#include "network/Transfer/TransferService.h"
#include "Discovery/DiscoveryService.h"

namespace core {

TransferManager::TransferManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_repository(dbManager ? dbManager->database() : QSqlDatabase())
{
}

TransferManager::~TransferManager() = default;

void TransferManager::setTransferService(network::TransferService *transferService)
{
    if (m_transferService) {
        m_transferService->disconnect(this);
    }

    m_transferService = transferService;
    if (!m_transferService) {
        return;
    }

    connect(m_transferService, &network::TransferService::transferStarted,
            this, &TransferManager::onNetworkTransferStarted);
    connect(m_transferService, &network::TransferService::transferCompleted,
            this, &TransferManager::onNetworkTransferCompleted);
    connect(m_transferService, &network::TransferService::transferFailed,
            this, &TransferManager::onNetworkTransferFailed);
}

void TransferManager::setDiscoveryService(network::DiscoveryService *discoveryService)
{
    m_discoveryService = discoveryService;
}

QString TransferManager::resolvePeerName(const QHostAddress &peerAddress) const
{
    if (!m_discoveryService) {
        return QString();
    }
    const QList<network::DiscoveredPeer> peers = m_discoveryService->peers();
    for (const network::DiscoveredPeer &peer : peers) {
        if (peer.address == peerAddress) {
            return peer.name;
        }
    }
    return QString();
}

bool TransferManager::sendFile(const QHostAddress &host, quint16 port, const QString &filePath,
                                int senderId, int recipientId)
{
    if (!m_transferService) {
        qWarning() << "TransferManager: no TransferService configured";
        return false;
    }
    // L'enregistrement en base a lieu dans onNetworkTransferStarted(), une
    // fois la connexion TCP etablie (evite d'enregistrer un transfert qui
    // n'a en realite jamais demarre si sendFile() echoue avant meme de
    // se connecter, par ex. fichier local introuvable). On memorise donc
    // le chemin local ici (voir m_pendingSendFilePaths) pour pouvoir le
    // rattacher a l'enregistrement une fois celui-ci cree.
    const QString fileName = QFileInfo(filePath).fileName();
    m_pendingSendFilePaths[fileName].append(filePath);

    const bool started = m_transferService->sendFile(host, port, filePath, senderId, recipientId);
    if (!started) {
        // La connexion n'a jamais demarre : retirer le chemin mis en
        // attente pour ne pas polluer un transfert futur du meme nom.
        QStringList &pending = m_pendingSendFilePaths[fileName];
        pending.removeOne(filePath);
        if (pending.isEmpty()) {
            m_pendingSendFilePaths.remove(fileName);
        }
    }
    return started;
}

std::vector<models::Transfer> TransferManager::allTransfers() const
{
    return m_repository.findAll();
}

std::vector<models::Transfer> TransferManager::userTransfers(int userId) const
{
    return m_repository.findByUser(userId);
}

std::optional<models::Transfer> TransferManager::transfer(int id) const
{
    return m_repository.findById(id);
}

void TransferManager::onNetworkTransferStarted(const QString &transferKey, const QString &fileName,
                                                qint64 fileSize, bool incoming, qint64 resumeOffset,
                                                int senderId, int recipientId, const QHostAddress &peerAddress)
{
    // Accepter les IDs negatifs comme "inconnus" - le transfert doit
    // toujours etre enregistre pour l'historique, meme sans identite
    // complete (ex. recipientId inconnu sur un reseau P2P : c'est le cas
    // le plus courant pour un envoi vers un poste decouvert sur le LAN,
    // qui n'a pas necessairement de compte utilisateur associe). Voir
    // migration #012 : sender_id/recipient_id sont desormais nullables.
    models::Transfer transfer;
    transfer.setSenderId(senderId > 0 ? senderId : -1);
    transfer.setRecipientId(recipientId > 0 ? recipientId : -1);
    transfer.setFileName(fileName);
    transfer.setFileSize(fileSize);
    // peer_address/peer_name (migration #015) : permettent de regrouper
    // l'historique par correspondant, independamment de tout compte
    // utilisateur local (voir la meme logique dans core::CallHistoryManager).
    if (!peerAddress.isNull()) {
        transfer.setPeerAddress(peerAddress.toString());
        transfer.setPeerName(resolvePeerName(peerAddress));
    }
    // Une reprise (resumeOffset > 0) redemarre un transfert deja en
    // cours : son statut reste "in_progress" comme un demarrage normal.
    Q_UNUSED(resumeOffset);
    transfer.setStatus(models::TransferStatus::InProgress);

    if (!incoming) {
        // Envoi sortant : le chemin local a ete memorise par sendFile()
        // avant que la connexion TCP (asynchrone) n'aboutisse a ce signal.
        QStringList &pending = m_pendingSendFilePaths[fileName];
        if (!pending.isEmpty()) {
            transfer.setFilePath(pending.takeFirst());
            if (pending.isEmpty()) {
                m_pendingSendFilePaths.remove(fileName);
            }
        }
    }
    // Pour une reception, le chemin de destination final n'est connu
    // qu'a la fin du transfert (voir onNetworkTransferCompleted()).

    const int id = m_repository.create(transfer);
    if (id < 0) {
        qWarning() << "TransferManager: echec de l'enregistrement du transfert" << transferKey
                   << ":" << m_repository.lastError();
        return;
    }

    transfer.setId(id);
    m_activeTransfers.insert(transferKey, id);
    emit transferRecorded(id, transfer);
}

void TransferManager::onNetworkTransferCompleted(const QString &transferKey, const QString &filePath)
{
    const int id = m_activeTransfers.take(transferKey);
    if (id <= 0) {
        return;
    }

    // filePath est le chemin final ecrit par TransferService : deja connu
    // pour un envoi (chemin local source), mais c'est la premiere fois
    // qu'on le connait pour une reception (dossier de reception + nom de
    // fichier, une fois le ".part" renomme). On l'enregistre dans les deux
    // cas pour permettre "ouvrir l'emplacement du fichier" depuis l'UI.
    if (!filePath.isEmpty()) {
        m_repository.updateFilePath(id, filePath);
    }

    if (m_repository.updateStatus(id, models::TransferStatus::Completed)) {
        emit transferStatusChanged(id, models::TransferStatus::Completed);
    }
}

void TransferManager::onNetworkTransferFailed(const QString &transferKey, const QString &errorString)
{
    Q_UNUSED(errorString);

    const int id = m_activeTransfers.take(transferKey);
    if (id <= 0) {
        return;
    }

    if (m_repository.updateStatus(id, models::TransferStatus::Failed)) {
        emit transferStatusChanged(id, models::TransferStatus::Failed);
    }
}

} // namespace core
