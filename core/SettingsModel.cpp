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

QString SettingsModel::organizationName() const
{
    return m_organizationName;
}

void SettingsModel::setOrganizationName(const QString &name)
{
    if (m_organizationName != name) {
        m_organizationName = name;
        emit organizationNameChanged();
    }
}

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

bool SettingsModel::enableSounds() const
{
    return m_enableSounds;
}

void SettingsModel::setEnableSounds(bool enabled)
{
    if (m_enableSounds != enabled) {
        m_enableSounds = enabled;
        emit enableSoundsChanged();
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
    settings.setValue("organizationName", m_organizationName);
    settings.setValue("defaultDownloadPath", m_defaultDownloadPath);
    settings.setValue("enableNotifications", m_enableNotifications);
    settings.setValue("enableSounds", m_enableSounds);
    settings.setValue("messagingPort", m_messagingPort);
    settings.setValue("discoveryPort", m_discoveryPort);
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
    m_organizationName = settings.value("organizationName", "CollabLAN").toString();
    m_defaultDownloadPath = settings.value("defaultDownloadPath", "").toString();
    m_enableNotifications = settings.value("enableNotifications", true).toBool();
    m_enableSounds = settings.value("enableSounds", true).toBool();
    m_messagingPort = settings.value("messagingPort", 12345).toInt();
    m_discoveryPort = settings.value("discoveryPort", 45454).toInt();
    m_rememberedUsername = settings.value("rememberedUsername", "").toString();
    m_rememberedSessionToken = settings.value("rememberedSessionToken", "").toString();
    qDebug().noquote() << "[SettingsModel::load] fichier=" << settings.fileName()
                        << "rememberedUsername=" << m_rememberedUsername
                        << "tokenPresent=" << !m_rememberedSessionToken.isEmpty()
                        << "status=" << settings.status();
}

} // namespace core
