#ifndef NETWORK_PEERSMODEL_H
#define NETWORK_PEERSMODEL_H

#include <QAbstractListModel>
#include <QList>

#include "DiscoveryService.h"

namespace network {

/**
 * @brief Modele Qt (QAbstractListModel) exposant a QML la liste des postes
 * detectes par DiscoveryService, mise a jour en temps reel.
 *
 * Ecoute peerDiscovered / peerUpdated / peerLost et repercute chaque
 * evenement sur le modele (insertion, mise a jour de ligne, suppression),
 * ce qui permet a une ListView QML de refleter les changements sans
 * rafraichissement manuel (issue #17).
 */
class PeersModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        StatusRole,
        AddressRole,
        PortRole,
        LastSeenMsRole,
    };
    Q_ENUM(Roles)

    explicit PeersModel(DiscoveryService *discoveryService, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;

signals:
    void countChanged();

private slots:
    void onPeerDiscovered(const network::DiscoveredPeer &peer);
    void onPeerUpdated(const network::DiscoveredPeer &peer);
    void onPeerLost(const network::DiscoveredPeer &peer);

private:
    int indexOfPeer(const QString &id) const;

    DiscoveryService *m_discoveryService = nullptr;
    QList<DiscoveredPeer> m_peers;
};

} // namespace network

#endif // NETWORK_PEERSMODEL_H
