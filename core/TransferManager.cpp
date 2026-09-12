#include "TransferManager.h"

#include <QDebug>
#include <QFileInfo>

#include "database/DatabaseManager.h"
#include "models/Settings.h"
#include "network/Transfer/TransferService.h"
#include "Discovery/DiscoveryService.h"

namespace {

// CORRECTIF (bug #3 : peer_address incoherent) : une connexion entrante sur
// un socket double-pile (IPv4+IPv6) rapporte QHostAddress::peerAddress()
// sous forme mappee IPv4-in-IPv6 (ex. "::ffff:192.168.42.1"), alors qu'un
// envoi sortant vers une adresse saisie/choisie directement reste en forme
// IPv4 pure ("192.168.42.1") : meme poste, deux representations textuelles
// differentes stockees en base selon le sens du transfert (cf. TransferManager.cpp
// deja documente pour resolvePeerName()/resolvePeerMachineId() ci-dessus, qui
// comparent deja les deux formes via QHostAddress::TolerantConversion --
// seul le texte finalement persiste ne l'etait pas). On normalise ici vers
// la forme IPv4 pure des que possible, pour que l'affichage et tout
// regroupement par peer_address restent coherents quel que soit le sens.
QHostAddress normalizedPeerAddress(const QHostAddress &address)
{
    bool isIPv4 = false;
    const quint32 ipv4 = address.toIPv4Address(&isIPv4);
    return isIPv4 ? QHostAddress(ipv4) : address;
}

} // namespace

namespace core {

TransferManager::TransferManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_repository(dbManager ? dbManager->database() : QSqlDatabase())
    , m_settingsRepository(dbManager ? dbManager->database() : QSqlDatabase())
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
    // CORRECTIF : nom stable par peerMachineId (voir doc dans le .h). On
    // ne consulte le cache Settings que si on a un peerMachineId : sans
    // lui, on n'a aucune cle stable a utiliser et on retombe directement
    // sur la resolution "live" par adresse IP ci-dessous (comportement
    // inchange pour ce cas).
    const QString cacheKey = peerMachineId.isEmpty()
        ? QString()
        : QStringLiteral("peer_folder_name:%1").arg(peerMachineId);
    if (!cacheKey.isEmpty()) {
        const auto cached = m_settingsRepository.findByKey(cacheKey);
        if (cached.has_value() && !cached->value().toString().isEmpty()) {
            return cached->value().toString();
        }
    }

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
                if (!peer.name.isEmpty()) {
                    m_settingsRepository.save(models::Settings(cacheKey, peer.name));
                }
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
    // (QHostAddress::Any). Non mis en cache : sans peerMachineId, on n'a
    // pas de cle stable a associer a ce nom.
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
                                const QString &senderUuid, const QString &recipientUuid,
                                const QString &knownPeerMachineId, const QString &relativeDirPath)
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
    // Toujours ajoutee en parallele strict de m_pendingSendFilePaths (meme
    // si vide) pour que les deux listes restent alignees index a index en
    // cas d'envois concurrents d'un fichier de meme nom vers des pairs
    // differents (voir onNetworkTransferStarted()).
    m_pendingPeerMachineIds[fileName].append(knownPeerMachineId);

    const bool started = m_transferService->sendFile(host, port, filePath, senderUuid, recipientUuid,
                                                       QString(), false, relativeDirPath);
    if (!started) {
        // La connexion n'a jamais demarre : retirer le chemin (et le
        // peerMachineId associe) mis en attente pour ne pas polluer un
        // transfert futur du meme nom.
        QStringList &pending = m_pendingSendFilePaths[fileName];
        pending.removeOne(filePath);
        if (pending.isEmpty()) {
            m_pendingSendFilePaths.remove(fileName);
        }

        QStringList &pendingIds = m_pendingPeerMachineIds[fileName];
        if (!pendingIds.isEmpty()) {
            pendingIds.removeLast();
        }
        if (pendingIds.isEmpty()) {
            m_pendingPeerMachineIds.remove(fileName);
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

    // CORRECTIF (peer_name incoherent malgre peer_machine_id stable,
    // symptome observe : deux transferts vers le meme peerMachineId
    // affichent "admin" puis "Demo" a 25s d'intervalle dans le meme
    // Transfers_instance2.csv) : peerMachineId arrive VIDE sur l'envoi
    // (cf. TransferService::startSendOnSocket(), qui documente deja ce
    // choix), et resolvePeerName() etait jusqu'ici appele avec ce
    // parametre brut. Faute de cle stable, resolvePeerName() retombait sur
    // son repli par adresse IP -- fragile en temps normal (cf. son propre
    // commentaire sur les machines multi-interfaces), et carrement
    // incorrect ici puisque plusieurs instances tournent sur le MEME poste
    // pour les tests : elles partagent alors la meme adresse IP cote
    // transfert, et le repli choisissait arbitrairement l'un des pairs qui
    // la partagent. peer_machine_id, lui, etait deja resolu correctement
    // juste apres via m_pendingPeerMachineIds (alimente par le choix
    // explicite du destinataire, cf. TransferContext::sendFile()) : les
    // deux colonnes finissaient desynchronisees pour un seul et meme
    // transfert. Fix : resoudre peerMachineId UNE SEULE FOIS ici, avec
    // exactement la meme logique de repli qu'auparavant, et reutiliser
    // cette valeur unique pour peer_name ET peer_machine_id.
    QString resolvedPeerMachineId = peerMachineId;
    if (resolvedPeerMachineId.isEmpty()) {
        if (!incoming) {
            QStringList &pendingIds = m_pendingPeerMachineIds[fileName];
            if (!pendingIds.isEmpty()) {
                resolvedPeerMachineId = pendingIds.takeFirst();
                if (pendingIds.isEmpty()) {
                    m_pendingPeerMachineIds.remove(fileName);
                }
            }
            if (resolvedPeerMachineId.isEmpty()) {
                resolvedPeerMachineId = resolvePeerMachineId(peerAddress);
            }
        } else if (!peerAddress.isNull()) {
            resolvedPeerMachineId = resolvePeerMachineId(peerAddress);
        }
    }

    models::Transfer transfer;
    transfer.setSenderUuid(senderUuid);
    transfer.setRecipientUuid(recipientUuid);
    transfer.setFileName(fileName);
    transfer.setFileSize(fileSize);
    // peer_address/peer_name (migration #015) : permettent de regrouper
    // l'historique par correspondant, independamment de tout compte
    // utilisateur local (voir la meme logique dans core::CallHistoryManager).
    if (!peerAddress.isNull()) {
        transfer.setPeerAddress(normalizedPeerAddress(peerAddress).toString());
        transfer.setPeerName(resolvePeerName(peerAddress, resolvedPeerMachineId));
    }
    // peer_machine_id (migration #016) : UUID stable du pair, renseigne
    // independamment de sender_uuid/recipient_uuid qui restent vides en
    // P2P LAN sans compte utilisateur (voir migration #017). Contrairement a
    // peerAddress(), c'est fiable meme sur une machine multi-interfaces.
    if (!resolvedPeerMachineId.isEmpty()) {
        transfer.setPeerMachineId(resolvedPeerMachineId);
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