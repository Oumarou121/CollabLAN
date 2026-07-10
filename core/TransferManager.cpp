#include "TransferManager.h"

#include <QDebug>

#include "database/DatabaseManager.h"
#include "network/Transfer/TransferService.h"

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
    // se connecter, par ex. fichier local introuvable).
    return m_transferService->sendFile(host, port, filePath, senderId, recipientId);
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
                                                int senderId, int recipientId)
{
    Q_UNUSED(incoming);

    if (senderId <= 0 || recipientId <= 0) {
        // Pas d'identite exploitable (ex. senderId/recipientId non
        // fournis) : rien a persister pour ce transfert.
        qWarning() << "TransferManager: transfert" << transferKey
                   << "sans expediteur/destinataire valide, non enregistre";
        return;
    }

    models::Transfer transfer;
    transfer.setSenderId(senderId);
    transfer.setRecipientId(recipientId);
    transfer.setFileName(fileName);
    transfer.setFileSize(fileSize);
    // Une reprise (resumeOffset > 0) redemarre un transfert deja en
    // cours : son statut reste "in_progress" comme un demarrage normal.
    Q_UNUSED(resumeOffset);
    transfer.setStatus(models::TransferStatus::InProgress);

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
    Q_UNUSED(filePath);

    const int id = m_activeTransfers.take(transferKey);
    if (id <= 0) {
        return;
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
