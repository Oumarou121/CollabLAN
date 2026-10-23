#ifndef CORE_AUDITLOGMODEL_H
#define CORE_AUDITLOGMODEL_H

#include <QAbstractListModel>
#include <QVector>
#include <QString>
#include <QVariantMap>

#include "models/AuditLog.h"

namespace database { struct AuditLogFilter; }

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
    Q_PROPERTY(int count READ count NOTIFY countChanged)

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

    int count() const { return m_logs.size(); }

    /// Retourne l'entree a l'index donne sous forme de QVariantMap (cles :
    /// id, timestamp, eventType, description, userId, actorLabel - voir
    /// roleNames()), utilisable directement depuis QML sans passer par les
    /// roles numeriques (voir HomeView.qml, refreshActivities()).
    Q_INVOKABLE QVariantMap get(int row) const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setEventTypeFilter(const QString &eventType);
    Q_INVOKABLE void setUserIdFilter(qint64 userId);
    Q_INVOKABLE void setDateRange(const QString &from, const QString &to);
    Q_INVOKABLE void clearFilters();
    Q_INVOKABLE QString exportToCsv(const QString &filePath);
    /// Nombre d'entrees que exportToCsv ecrirait (filtre courant, sans le
    /// plafond d'affichage de 200).
    Q_INVOKABLE int exportCount() const;

signals:
    void auditManagerChanged();
    void countChanged();
    void error(const QString &message);

private:
    database::AuditLogFilter currentFilter() const;
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