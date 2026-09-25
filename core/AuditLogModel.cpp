#include "AuditLogModel.h"
#include "AuditManager.h"
#include "database/Repositories/AuditLogRepository.h"

#include <QDateTime>
#include <QFile>
#include <QTextStream>
#include <QStandardPaths>
#include <QVariantMap>

namespace core {

namespace {

QString localizedAuditText(QString value)
{
    const QList<QPair<QString, QString>> labels = {
        {QStringLiteral("in_progress"), QStringLiteral("En cours")},
        {QStringLiteral("pending"), QStringLiteral("En attente")},
        {QStringLiteral("completed"), QStringLiteral("Termine")},
        {QStringLiteral("missed"), QStringLiteral("Manque")},
        {QStringLiteral("rejected"), QStringLiteral("Refuse")},
        {QStringLiteral("cancelled"), QStringLiteral("Annule")},
        {QStringLiteral("failed"), QStringLiteral("Echoue")},
        {QStringLiteral("outgoing"), QStringLiteral("Sortant")},
        {QStringLiteral("incoming"), QStringLiteral("Entrant")}
    };
    for (const auto &label : labels)
        value.replace(label.first, label.second);
    return value;
}

QString localizedAuditEventType(const QString &eventType)
{
    if (eventType == QStringLiteral("connection")) return QStringLiteral("Connexion");
    if (eventType == QStringLiteral("message")) return QStringLiteral("Message");
    if (eventType == QStringLiteral("transfer")) return QStringLiteral("Transfert");
    if (eventType == QStringLiteral("call")) return QStringLiteral("Appel");
    if (eventType == QStringLiteral("access_denied")) return QStringLiteral("Acces refuse");
    return eventType;
}

}

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
    emit countChanged();
}

QVariantMap AuditLogModel::get(int row) const
{
    QVariantMap result;
    if (row < 0 || row >= m_logs.size())
        return result;

    const QModelIndex idx = index(row, 0);
    const QHash<int, QByteArray> roles = roleNames();
    for (auto it = roles.constBegin(); it != roles.constEnd(); ++it)
        result.insert(QString::fromUtf8(it.value()), data(idx, it.key()));
    return result;
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
            << localizedAuditEventType(log.eventType()) << ","
            << localizedAuditText(log.description()) << ","
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