#include "AuditLogModel.h"
#include "AuditManager.h"
#include "database/Repositories/AuditLogRepository.h"

#include <QDateTime>
#include <QFile>
#include <QTextStream>
#include <QStandardPaths>

namespace core {

AuditLogModel::AuditLogModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

AuditLogModel::~AuditLogModel() = default;

int AuditLogModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_logs.size();
}

QVariant AuditLogModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_logs.size())
        return QVariant();

    const models::AuditLog &log = m_logs.at(index.row());

    switch (role) {
    case IdRole:
        return log.id();
    case TimestampRole:
        return log.timestamp().toString(Qt::ISODate);
    case EventTypeRole:
        return log.eventType();
    case DescriptionRole:
        return log.description();
    case UserIdRole:
        return log.userId().value_or(0);
    case ActorLabelRole:
        return log.actorLabel();
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> AuditLogModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[TimestampRole] = "timestamp";
    roles[EventTypeRole] = "eventType";
    roles[DescriptionRole] = "description";
    roles[UserIdRole] = "userId";
    roles[ActorLabelRole] = "actorLabel";
    return roles;
}

QObject* AuditLogModel::auditManager() const
{
    return m_auditManager;
}

void AuditLogModel::setAuditManager(QObject *manager)
{
    if (m_auditManager == manager)
        return;

    if (m_auditManager)
        disconnect(m_auditManager, &core::AuditManager::eventRecorded,
                   this, &AuditLogModel::refresh);
    if (m_auditManager)
        disconnect(m_auditManager, &core::AuditManager::remoteEventRecorded,
                   this, &AuditLogModel::refresh);

    m_auditManager = qobject_cast<core::AuditManager*>(manager);

    if (m_auditManager)
        connect(m_auditManager, &core::AuditManager::eventRecorded,
                this, &AuditLogModel::refresh, Qt::UniqueConnection);

    if (m_auditManager)
        connect(m_auditManager, &core::AuditManager::remoteEventRecorded,
                this, &AuditLogModel::refresh, Qt::UniqueConnection);

    emit auditManagerChanged();
    refresh();
}

void AuditLogModel::refresh()
{
    if (!m_auditManager)
        return;

    beginResetModel();
    m_logs.clear();

    database::AuditLogFilter filter;
    if (!m_eventTypeFilter.isEmpty())
        filter.eventType = m_eventTypeFilter;
    if (m_userIdFilter > 0)
        filter.userId = m_userIdFilter;
    if (!m_dateFromFilter.isEmpty())
        filter.from = QDateTime::fromString(m_dateFromFilter, Qt::ISODate);
    if (!m_dateToFilter.isEmpty())
        filter.to = QDateTime::fromString(m_dateToFilter, Qt::ISODate);

    m_logs = m_auditManager->queryEvents(filter);
    endResetModel();
}

void AuditLogModel::setEventTypeFilter(const QString &eventType)
{
    if (m_eventTypeFilter == eventType)
        return;
    m_eventTypeFilter = eventType;
    refresh();
}

void AuditLogModel::setUserIdFilter(qint64 userId)
{
    if (m_userIdFilter == userId)
        return;
    m_userIdFilter = userId;
    refresh();
}

void AuditLogModel::setDateRange(const QString &from, const QString &to)
{
    if (m_dateFromFilter == from && m_dateToFilter == to)
        return;
    m_dateFromFilter = from;
    m_dateToFilter = to;
    refresh();
}

void AuditLogModel::clearFilters()
{
    m_eventTypeFilter.clear();
    m_userIdFilter = 0;
    m_dateFromFilter.clear();
    m_dateToFilter.clear();
    refresh();
}

QString AuditLogModel::exportToCsv(const QString &filePath)
{
    if (m_logs.isEmpty()) {
        emit error("Aucune entrée à exporter");
        return QString();
    }

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit error(QString("Impossible d'ouvrir le fichier : %1").arg(filePath));
        return QString();
    }

    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);

    // En-tête CSV
    out << "ID,Timestamp,Type d'événement,Description,Utilisateur,Acteur\n";

    // Données
    for (const models::AuditLog &log : m_logs) {
        out << log.id() << ","
            << log.timestamp().toString(Qt::ISODate) << ","
            << log.eventType() << ","
            << log.description() << ","
            << log.userId().value_or(0) << ","
            << log.actorLabel() << "\n";
    }

    file.close();
    return filePath;
}

void AuditLogModel::loadLogs()
{
    refresh();
}

} // namespace core
