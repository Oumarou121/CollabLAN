#ifndef CORE_AUDITLOGMODEL_H
#define CORE_AUDITLOGMODEL_H

#include <QAbstractListModel>
#include <QVector>
#include <QString>

#include "models/AuditLog.h"

namespace core {

class AuditManager;

/**
 * @brief Modele QML pour afficher le journal d'audit dans AdminView.qml (issue #65).
 *
 * Expose les entrees d'audit comme une liste QML avec support du filtrage
 * (par type d'evenement, par utilisateur, par plage de dates) et de la
 * pagination.
 */
class AuditLogModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QObject* auditManager READ auditManager WRITE setAuditManager NOTIFY auditManagerChanged)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        TimestampRole,
        EventTypeRole,
        DescriptionRole,
        UserIdRole,
        ActorLabelRole
    };

    explicit AuditLogModel(QObject *parent = nullptr);
    ~AuditLogModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QObject* auditManager() const;
    void setAuditManager(QObject *manager);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setEventTypeFilter(const QString &eventType);
    Q_INVOKABLE void setUserIdFilter(qint64 userId);
    Q_INVOKABLE void setDateRange(const QString &from, const QString &to);
    Q_INVOKABLE void clearFilters();
    Q_INVOKABLE QString exportToCsv(const QString &filePath);

signals:
    void auditManagerChanged();
    void error(const QString &message);

private:
    void loadLogs();

    core::AuditManager *m_auditManager = nullptr;
    QVector<models::AuditLog> m_logs;
    QString m_eventTypeFilter;
    qint64 m_userIdFilter = 0;
    QString m_dateFromFilter;
    QString m_dateToFilter;
};

} // namespace core

#endif // CORE_AUDITLOGMODEL_H
