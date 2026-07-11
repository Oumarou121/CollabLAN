#include "TransferContext.h"

#include <QDebug>
#include <QFileInfo>
#include <QHostAddress>
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

    // senderId identifie l'utilisateur courant dans l'historique persiste
    // (issue #55) ; recipientId n'est pas resolvable a partir d'un poste
    // reseau (aucun compte utilisateur associe a un pair decouvert), donc
    // laisse a -1 (inconnu) plutot que de deviner un identifiant errone.
    const int senderId = m_userManager && m_userManager->currentUserId().has_value()
                              ? m_userManager->currentUserId().value()
                              : -1;
    const int recipientId = -1;

    const bool started = m_transferManager->sendFile(host, port, localPath, senderId, recipientId);
    if (!started) {
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
                                         bool incoming, qint64 resumeOffset, int senderId, int recipientId)
{
    Q_UNUSED(senderId)
    Q_UNUSED(recipientId)

    QVariantMap entry;
    entry[QStringLiteral("transferKey")] = transferKey;
    entry[QStringLiteral("fileName")] = fileName;
    entry[QStringLiteral("direction")] = incoming ? tr("Reception") : tr("Envoi");
    entry[QStringLiteral("statusText")] = tr("En cours");
    entry[QStringLiteral("bytesTransferred")] = resumeOffset;
    entry[QStringLiteral("totalBytes")] = fileSize;
    entry[QStringLiteral("percent")] = percentOf(resumeOffset, fileSize);
    entry[QStringLiteral("errorString")] = QString();

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
    Q_UNUSED(filePath)

    const int index = indexOfTransfer(transferKey);
    if (index < 0) {
        return;
    }

    QVariantMap entry = m_activeTransfers.at(index).toMap();
    entry[QStringLiteral("statusText")] = tr("Termine");
    entry[QStringLiteral("percent")] = 100;
    entry[QStringLiteral("bytesTransferred")] = entry.value(QStringLiteral("totalBytes"));
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

} // namespace core