#ifndef NETWORK_PEERSMODEL_H
#define NETWORK_PEERSMODEL_H

#include <QAbstractListModel>
#include <QList>

#include "DiscoveryService.h"

namespace network {

/**
 * @brief Modele Qt exposant les postes dont un utilisateur est authentifie.
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
        UserUuidRole,
        StatusRole,
        AddressRole,
        PortRole,
        TransferPortRole,
        SignalingPortRole,
        LastSeenMsRole,
    };
    Q_ENUM(Roles)

    explicit PeersModel(DiscoveryService *discoveryService, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;

    /// Nom du poste correspondant a l'adresse IP donnee, tel que decouvert
    /// sur le reseau local, ou chaine vide si aucun poste connu ne
    /// correspond (ex. le correspondant a ete perdu depuis, ou l'appel a
    /// ete recu d'une adresse jamais annoncee). Utilise par CallView.qml
    /// pour afficher un nom plutot que l'adresse IP brute exposee par
    /// core::CallContext::remoteAddress.
    Q_INVOKABLE QString nameForAddress(const QString &address) const;

    /// UUID du compte utilisateur connecte sur le poste identifie par
    /// machineId, ou chaine vide si ce poste est inconnu ou n'a annonce
    /// aucun compte connecte (cf. DiscoveryService::localUserUuid()).
    /// Utilise par core::TransferContext::sendFile() pour resoudre
    /// recipientUuid (bug #2 : recipient_uuid toujours vide).
    Q_INVOKABLE QString userUuidForMachineId(const QString &machineId) const;

signals:
    void countChanged();

private slots:
    void onPeerDiscovered(const network::DiscoveredPeer &peer);
    void onPeerUpdated(const network::DiscoveredPeer &peer);
    void onPeerLost(const network::DiscoveredPeer &peer);

private:
    int indexOfPeer(const QString &id) const;
    static bool isAuthenticatedPeer(const DiscoveredPeer &peer);

    DiscoveryService *m_discoveryService = nullptr;
    QList<DiscoveredPeer> m_peers;
};

} // namespace network

#endif // NETWORK_PEERSMODEL_H
