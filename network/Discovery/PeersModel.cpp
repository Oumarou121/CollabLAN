#include "PeersModel.h"

namespace network {

PeersModel::PeersModel(DiscoveryService *discoveryService, QObject *parent)
    : QAbstractListModel(parent)
    , m_discoveryService(discoveryService)
{
    // Pre-remplit avec les postes deja connus (utile si le modele est cree
    // apres que DiscoveryService ait deja recu des annonces).
    if (m_discoveryService)
        m_peers = m_discoveryService->peers();

    connect(m_discoveryService, &DiscoveryService::peerDiscovered,
            this, &PeersModel::onPeerDiscovered);
    connect(m_discoveryService, &DiscoveryService::peerUpdated,
            this, &PeersModel::onPeerUpdated);
    connect(m_discoveryService, &DiscoveryService::peerLost,
            this, &PeersModel::onPeerLost);
}

int PeersModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_peers.size();
}

QVariant PeersModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_peers.size())
        return QVariant();

    const DiscoveredPeer &peer = m_peers.at(index.row());

    switch (role) {
    case IdRole:
        return peer.id;
    case NameRole:
        return peer.name;
    case StatusRole:
        return peer.status;
    case AddressRole:
        return peer.address.toString();
    case PortRole:
        return peer.port;
    case TransferPortRole:
        return peer.transferPort;
    case SignalingPortRole:
        return peer.signalingPort;
    case LastSeenMsRole:
        return peer.lastSeenMs;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> PeersModel::roleNames() const
{
    return {
        { IdRole, "peerId" },
        { NameRole, "name" },
        { StatusRole, "status" },
        { AddressRole, "address" },
        { PortRole, "port" },
        { TransferPortRole, "transferPort" },
        { SignalingPortRole, "signalingPort" },
        { LastSeenMsRole, "lastSeenMs" },
    };
}

int PeersModel::count() const
{
    return m_peers.size();
}

int PeersModel::indexOfPeer(const QString &id) const
{
    for (int i = 0; i < m_peers.size(); ++i) {
        if (m_peers.at(i).id == id)
            return i;
    }
    return -1;
}

void PeersModel::onPeerDiscovered(const network::DiscoveredPeer &peer)
{
    const int existing = indexOfPeer(peer.id);
    if (existing >= 0) {
        // Deja present (ex. signal recu deux fois) : traite comme une mise a jour.
        onPeerUpdated(peer);
        return;
    }

    const int row = m_peers.size();
    beginInsertRows(QModelIndex(), row, row);
    m_peers.append(peer);
    endInsertRows();

    emit countChanged();
}

void PeersModel::onPeerUpdated(const network::DiscoveredPeer &peer)
{
    const int row = indexOfPeer(peer.id);
    if (row < 0) {
        // Pas encore connu localement : traite comme une decouverte.
        onPeerDiscovered(peer);
        return;
    }

    m_peers[row] = peer;
    const QModelIndex idx = index(row);
    emit dataChanged(idx, idx);
}

void PeersModel::onPeerLost(const network::DiscoveredPeer &peer)
{
    const int row = indexOfPeer(peer.id);
    if (row < 0)
        return;

    beginRemoveRows(QModelIndex(), row, row);
    m_peers.removeAt(row);
    endRemoveRows();

    emit countChanged();
}

} // namespace network
