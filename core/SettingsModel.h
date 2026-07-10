#ifndef CORE_SETTINGSMODEL_H
#define CORE_SETTINGSMODEL_H

#include <QObject>
#include <QString>

namespace core {

/**
 * @brief Modèle QML pour les paramètres globaux de l'application (issue #69).
 */
class SettingsModel : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString organizationName READ organizationName WRITE setOrganizationName NOTIFY organizationNameChanged)
    Q_PROPERTY(QString defaultDownloadPath READ defaultDownloadPath WRITE setDefaultDownloadPath NOTIFY defaultDownloadPathChanged)
    Q_PROPERTY(bool enableNotifications READ enableNotifications WRITE setEnableNotifications NOTIFY enableNotificationsChanged)
    Q_PROPERTY(bool enableSounds READ enableSounds WRITE setEnableSounds NOTIFY enableSoundsChanged)
    Q_PROPERTY(int messagingPort READ messagingPort WRITE setMessagingPort NOTIFY messagingPortChanged)
    Q_PROPERTY(int discoveryPort READ discoveryPort WRITE setDiscoveryPort NOTIFY discoveryPortChanged)

public:
    explicit SettingsModel(QObject *parent = nullptr);
    ~SettingsModel() override;

    QString organizationName() const;
    void setOrganizationName(const QString &name);

    QString defaultDownloadPath() const;
    void setDefaultDownloadPath(const QString &path);

    bool enableNotifications() const;
    void setEnableNotifications(bool enabled);

    bool enableSounds() const;
    void setEnableSounds(bool enabled);

    int messagingPort() const;
    void setMessagingPort(int port);

    int discoveryPort() const;
    void setDiscoveryPort(int port);

    Q_INVOKABLE void save();
    Q_INVOKABLE void load();

signals:
    void organizationNameChanged();
    void defaultDownloadPathChanged();
    void enableNotificationsChanged();
    void enableSoundsChanged();
    void messagingPortChanged();
    void discoveryPortChanged();

private:
    QString m_organizationName = "CollabLAN";
    QString m_defaultDownloadPath = "";
    bool m_enableNotifications = true;
    bool m_enableSounds = true;
    int m_messagingPort = 12345;
    int m_discoveryPort = 45454;
};

} // namespace core

#endif // CORE_SETTINGSMODEL_H
