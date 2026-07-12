#ifndef MODELS_SETTINGS_H
#define MODELS_SETTINGS_H

#include <QString>
#include <QVariant>

namespace models {

/**
 * @brief Represente les parametres de l'application pour un poste.
 */
class Settings
{
public:
    Settings();
    explicit Settings(const QString &key, const QVariant &value);

    QString key() const;
    void setKey(const QString &key);

    QVariant value() const;
    void setValue(const QVariant &value);

    QString valueType() const;

private:
    QString m_key;
    QVariant m_value;
};

} // namespace models

#endif // MODELS_SETTINGS_H
