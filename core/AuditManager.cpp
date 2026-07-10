#include "AuditManager.h"

#include "DatabaseManager.h"
#include "AuditLogRepository.h"

#include <QDebug>

namespace core {

QString auditEventTypeToString(AuditEventType type)
{
    switch (type) {
    case AuditEventType::Connection:   return QStringLiteral("connection");
    case AuditEventType::Message:      return QStringLiteral("message");
    case AuditEventType::Transfer:     return QStringLiteral("transfer");
    case AuditEventType::Call:         return QStringLiteral("call");
    case AuditEventType::AccessDenied: return QStringLiteral("access_denied");
    }
    return QStringLiteral("unknown");
}

AuditManager::AuditManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
    , m_repository(std::make_unique<database::AuditLogRepository>(dbManager))
{
}

AuditManager::~AuditManager() = default;

void AuditManager::recordEvent(AuditEventType type, const QString &description,
                                std::optional<qint64> userId, const QString &actorLabel)
{
    if (!m_dbManager) {
        qWarning() << "AuditManager: DatabaseManager absent, evenement non journalise -" << description;
        return;
    }

    models::AuditLog entry(auditEventTypeToString(type), description, userId, actorLabel);
    const std::optional<models::AuditLog> inserted = m_repository->insert(entry);
    if (!inserted.has_value()) {
        qWarning() << "AuditManager: echec de l'enregistrement de l'evenement -" << description;
        return;
    }

    emit eventRecorded(*inserted);
}

void AuditManager::logConnection(std::optional<qint64> userId, const QHostAddress &peerAddress,
                                  bool established, const QString &detail)
{
    QString description = established
        ? QStringLiteral("Connexion etablie avec %1").arg(peerAddress.toString())
        : QStringLiteral("Connexion perdue avec %1").arg(peerAddress.toString());
    if (!detail.isEmpty()) {
        description += QStringLiteral(" (%1)").arg(detail);
    }

    recordEvent(AuditEventType::Connection, description, userId, peerAddress.toString());
}

void AuditManager::logMessage(qint64 senderId, qint64 conversationId, bool outgoing)
{
    // Metadonnees uniquement (issue #62) : ni le contenu du message, ni
    // meme sa longueur, ne sont journalises.
    const QString description = outgoing
        ? QStringLiteral("Message envoye dans la conversation #%1").arg(conversationId)
        : QStringLiteral("Message recu dans la conversation #%1").arg(conversationId);

    recordEvent(AuditEventType::Message, description, senderId);
}

void AuditManager::logTransfer(qint64 userId, const QString &fileName, qint64 fileSizeBytes,
                                const QString &status, const QString &detail)
{
    QString description = QStringLiteral("Transfert '%1' (%2 octets) : %3")
                               .arg(fileName).arg(fileSizeBytes).arg(status);
    if (!detail.isEmpty()) {
        description += QStringLiteral(" (%1)").arg(detail);
    }

    recordEvent(AuditEventType::Transfer, description, userId);
}

void AuditManager::logCall(std::optional<qint64> userId, const QHostAddress &peerAddress,
                            const QString &status, const QString &detail)
{
    QString description = QStringLiteral("Appel avec %1 : %2").arg(peerAddress.toString(), status);
    if (!detail.isEmpty()) {
        description += QStringLiteral(" (%1)").arg(detail);
    }

    recordEvent(AuditEventType::Call, description, userId, peerAddress.toString());
}

void AuditManager::logRefusedAttempt(const QString &reason, const QHostAddress &peerAddress,
                                      std::optional<qint64> userId)
{
    QString description = QStringLiteral("Tentative refusee : %1").arg(reason);
    if (!peerAddress.isNull()) {
        description += QStringLiteral(" (depuis %1)").arg(peerAddress.toString());
    }

    recordEvent(AuditEventType::AccessDenied, description, userId,
                peerAddress.isNull() ? QString() : peerAddress.toString());
}

QVector<models::AuditLog> AuditManager::queryEvents(const database::AuditLogFilter &filter)
{
    return m_repository->find(filter);
}

} // namespace core
