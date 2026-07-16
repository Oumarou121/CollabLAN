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

QString TransferManager::resolvePeerName(const QHostAddress &peerAddress, const QString &peerMachineId) const
{
    if (!m_discoveryService) {
        return QString();
    }
    const QList<network::DiscoveredPeer> peers = m_discoveryService->peers();

    // Priorite a l'identifiant machine (UUID DiscoveryService::localId(),
    // transmis dans l'en-tete du transfert - voir TransferService::
    // encodeHeader()) : contrairement a l'adresse IP, il ne depend pas de
    // l'interface reseau empruntee. Sur une machine multi-interfaces
    // (Wi-Fi + Ethernet + adaptateurs virtuels VPN/VirtualBox/Hyper-V,
    // frequent sous Windows), l'annonce UDP de decouverte et la connexion
    // TCP entrante du transfert peuvent tres bien emprunter deux
    // interfaces differentes, donc deux adresses IP differentes : la
    // comparaison par adresse echoue alors meme apres normalisation des
    // adresses IPv4-mappees en IPv6. L'UUID, lui, reste identique quel que
    // soit le chemin reseau emprunte.
    if (!peerMachineId.isEmpty()) {
        for (const network::DiscoveredPeer &peer : peers) {
            if (peer.id == peerMachineId) {
                return peer.name;
            }
        }
    }

    // Repli sur l'adresse IP : cas d'un envoi (peerMachineId n'est pas
    // transmis dans ce sens, voir TransferService::onClientSocketConnected())
    // ou d'une reception depuis un en-tete anterieur a l'ajout de
    // senderMachineId. Comparaison tolerante pour gerer les adresses
    // IPv4-mappees en IPv6 (::ffff:x.x.x.x), rapportees par
    // QTcpSocket::peerAddress() sur une connexion entrante en double pile
    // (QHostAddress::Any).
    for (const network::DiscoveredPeer &peer : peers) {
        if (peer.address.isEqual(peerAddress, QHostAddress::TolerantConversion)) {
            return peer.name;
        }
    }
    return QString();
}

QString TransferManager::resolvePeerMachineId(const QHostAddress &peerAddress) const
{
    if (!m_discoveryService) {
        return QString();
    }
    const QList<network::DiscoveredPeer> peers = m_discoveryService->peers();
    for (const network::DiscoveredPeer &peer : peers) {
        if (peer.address.isEqual(peerAddress, QHostAddress::TolerantConversion)) {
            return peer.id;
        }
    }
    return QString();
}

bool TransferManager::sendFile(const QHostAddress &host, quint16 port, const QString &filePath,
                                const QString &senderUuid, const QString &recipientUuid)
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

    const bool started = m_transferService->sendFile(host, port, filePath, senderUuid, recipientUuid);
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

std::vector<models::Transfer> TransferManager::userTransfers(const QString &userUuid) const
{
    return m_repository.findByUser(userUuid);
}

std::optional<models::Transfer> TransferManager::transfer(int id) const
{
    return m_repository.findById(id);
}

void TransferManager::onNetworkTransferStarted(const QString &transferKey, const QString &fileName,
                                                qint64 fileSize, bool incoming, qint64 resumeOffset,
                                                const QString &senderUuid, const QString &recipientUuid,
                                                const QHostAddress &peerAddress,
                                                const QString &peerMachineId, bool isFolderTransfer)
{
    // CORRECTIF : les transferts de synchronisation de dossier (FolderSyncService)
    // ne doivent pas être enregistrés dans la table Transfers, réservée aux
    // transferts manuels P2P. FolderSyncService gère son propre historique via
    // SyncOperations et SharedFiles.
    if (isFolderTransfer) {
        qDebug() << "[TransferManager] Transfert ignoré (folder-sync):" << fileName;
        return;
    }

    // Chaine vide acceptee comme "inconnu" - le transfert doit toujours
    // etre enregistre pour l'historique, meme sans identite complete (ex.
    // recipientUuid inconnu sur un reseau P2P : c'est le cas le plus
    // courant pour un envoi vers un poste decouvert sur le LAN, qui n'a
    // pas necessairement de compte utilisateur associe). Voir migration
    // #017 : sender_uuid/recipient_uuid remplacent les anciens
    // sender_id/recipient_id entiers, supprimes.
    models::Transfer transfer;
    transfer.setSenderUuid(senderUuid);
    transfer.setRecipientUuid(recipientUuid);
    transfer.setFileName(fileName);
    transfer.setFileSize(fileSize);
    // peer_address/peer_name (migration #015) : permettent de regrouper
    // l'historique par correspondant, independamment de tout compte
    // utilisateur local (voir la meme logique dans core::CallHistoryManager).
    if (!peerAddress.isNull()) {
        transfer.setPeerAddress(peerAddress.toString());
        transfer.setPeerName(resolvePeerName(peerAddress, peerMachineId));
    }
    // peer_machine_id (migration #016) : UUID stable du pair, renseigne
    // independamment de sender_uuid/recipient_uuid qui restent vides en
    // P2P LAN sans compte utilisateur (voir migration #017). Contrairement a
    // peerAddress(), c'est fiable meme sur une machine multi-interfaces.
    // Cote envoi, peerMachineId arrive vide (TransferService::
    // onClientSocketConnected() ne le transmet pas, voir son commentaire) :
    // on le retrouve alors par adresse via DiscoveryService, comme
    // resolvePeerName() le fait deja pour le nom.
    if (!peerMachineId.isEmpty()) {
        transfer.setPeerMachineId(peerMachineId);
    } else if (!peerAddress.isNull()) {
        transfer.setPeerMachineId(resolvePeerMachineId(peerAddress));
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