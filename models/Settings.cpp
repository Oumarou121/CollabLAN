#include "Settings.h"

namespace models {

Settings::Settings()
{
}

Settings::Settings(const QString &key, const QVariant &value)
    : m_key(key)
    , m_value(value)
{
}

QString Settings::key() const
{
    return m_key;
}

void Settings::setKey(const QString &key)
{
    m_key = key;
}

QVariant Settings::value() const
{
    return m_value;
}

void Settings::setValue(const QVariant &value)
{
    m_value = value;
}

QString Settings::valueType() const
{
    switch (m_value.typeId()) {
    case QMetaType::Bool:
        return QStringLiteral("bool");
    case QMetaType::Int:
        return QStringLiteral("int");
    case QMetaType::Double:
        return QStringLiteral("double");
    case QMetaType::QString:
        return QStringLiteral("string");
    default:
        return QStringLiteral("unknown");
    }
}

} // namespace models
