#ifndef SERVICES_NOTIFICATIONSERVICE_H
#define SERVICES_NOTIFICATIONSERVICE_H

#include <QObject>
#include <QString>

namespace services {

/**
 * @brief Emission des notifications systeme (son, popup).
 *
 * Expose les evenements de notification pour l'UI.
 */
class NotificationService : public QObject
{
    Q_OBJECT

public:
    explicit NotificationService(QObject *parent = nullptr);
    ~NotificationService() override;

public slots:
    /// Affiche une notification systeme.
    void showNotification(const QString &title, const QString &message);

signals:
    /// Emis lorsqu'une notification doit être affichée par l'UI.
    void notificationAvailable(const QString &title, const QString &message);
};

} // namespace services

#endif // SERVICES_NOTIFICATIONSERVICE_H
