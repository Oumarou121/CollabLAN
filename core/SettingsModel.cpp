#include "SettingsModel.h"
#include <QSettings>
#include <QDebug>

namespace core {

SettingsModel::SettingsModel(QObject *parent)
    : QObject(parent)
{
    load();
}

SettingsModel::~SettingsModel() = default;

QString SettingsModel::defaultDownloadPath() const
{
    return m_defaultDownloadPath;
}

void SettingsModel::setDefaultDownloadPath(const QString &path)
{
    if (m_defaultDownloadPath != path) {
        m_defaultDownloadPath = path;
        emit defaultDownloadPathChanged();
    }
}

QString SettingsModel::defaultSharedFolderPath() const
{
    return m_defaultSharedFolderPath;
}

void SettingsModel::setDefaultSharedFolderPath(const QString &path)
{
    if (m_defaultSharedFolderPath != path) {
        m_defaultSharedFolderPath = path;
        emit defaultSharedFolderPathChanged();
    }
}

bool SettingsModel::enableNotifications() const
{
    return m_enableNotifications;
}

void SettingsModel::setEnableNotifications(bool enabled)
{
    if (m_enableNotifications != enabled) {
        m_enableNotifications = enabled;
        emit enableNotificationsChanged();
    }
}

int SettingsModel::messagingPort() const
{
    return m_messagingPort;
}

void SettingsModel::setMessagingPort(int port)
{
    if (m_messagingPort != port) {
        m_messagingPort = port;
        emit messagingPortChanged();
    }
}

int SettingsModel::discoveryPort() const
{
    return m_discoveryPort;
}

void SettingsModel::setDiscoveryPort(int port)
{
    if (m_discoveryPort != port) {
        m_discoveryPort = port;
        emit discoveryPortChanged();
    }
}

QString SettingsModel::machineName() const
{
    return m_machineName;
}

void SettingsModel::setMachineName(const QString &name)
{
    const QString trimmed = name.trimmed();
    if (m_machineName != trimmed) {
        m_machineName = trimmed;
        emit machineNameChanged();
    }
}

QString SettingsModel::rememberedUsername() const
{
    return m_rememberedUsername;
}

void SettingsModel::setRememberedUsername(const QString &username)
{
    if (m_rememberedUsername != username) {
        m_rememberedUsername = username;
        emit rememberedUsernameChanged();
    }
}

QString SettingsModel::rememberedSessionToken() const
{
    return m_rememberedSessionToken;
}

void SettingsModel::setRememberedSessionToken(const QString &token)
{
    if (m_rememberedSessionToken != token) {
        m_rememberedSessionToken = token;
        emit rememberedSessionTokenChanged();
    }
}

void SettingsModel::save()
{
    QSettings settings;
    settings.setValue("defaultDownloadPath", m_defaultDownloadPath);
    settings.setValue("defaultSharedFolderPath", m_defaultSharedFolderPath);
    settings.setValue("enableNotifications", m_enableNotifications);
    settings.setValue("messagingPort", m_messagingPort);
    settings.setValue("discoveryPort", m_discoveryPort);
    settings.setValue("machineName", m_machineName);
    settings.setValue("rememberedUsername", m_rememberedUsername);
    settings.setValue("rememberedSessionToken", m_rememberedSessionToken);
    settings.sync();
    qDebug().noquote() << "[SettingsModel::save] fichier=" << settings.fileName()
                        << "rememberedUsername=" << m_rememberedUsername
                        << "tokenPresent=" << !m_rememberedSessionToken.isEmpty()
                        << "status=" << settings.status();
}

void SettingsModel::load()
{
    QSettings settings;
    // Important : on passe par les setters (et non une affectation directe
    // aux membres) pour que les signaux *Changed soient emis - sans quoi
    // les bindings QML (TextField.text, etc.) ne se rafraichissent pas
    // quand load() est appele apres la construction (ex. bouton "Annuler").
    setDefaultDownloadPath(settings.value("defaultDownloadPath", "").toString());
    setDefaultSharedFolderPath(settings.value("defaultSharedFolderPath", "").toString());
    setEnableNotifications(settings.value("enableNotifications", true).toBool());
    setMessagingPort(settings.value("messagingPort", 12345).toInt());
    setDiscoveryPort(settings.value("discoveryPort", 45454).toInt());
    setMachineName(settings.value("machineName", "").toString());
    setRememberedUsername(settings.value("rememberedUsername", "").toString());
    setRememberedSessionToken(settings.value("rememberedSessionToken", "").toString());
    qDebug().noquote() << "[SettingsModel::load] fichier=" << settings.fileName()
                        << "rememberedUsername=" << m_rememberedUsername
                        << "tokenPresent=" << !m_rememberedSessionToken.isEmpty()
                        << "status=" << settings.status();
}

} // namespace core
