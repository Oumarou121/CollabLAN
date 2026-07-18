#ifndef MODELS_USERSESSION_H
#define MODELS_USERSESSION_H

#include <QString>
#include <QDateTime>

namespace models {

/**
 * @brief Represente une session persistante "Se souvenir de moi" (migration #026).
 *
 * Correspond a une ligne de la table `UserSessions`. Seul le hash SHA-256
 * du jeton d'authentification est transporte ici (jamais le jeton en
 * clair) : voir database::SessionRepository et core::UserManager pour la
 * generation/validation du jeton brut, qui ne quitte jamais la memoire du
 * processus cote client (stocke localement via core::SettingsModel/QSettings,
 * jamais en base).
 */
class UserSession
{
public:
    UserSession();
    UserSession(int id,
                int userId,
                QString tokenHash,
                QString deviceLabel,
                QDateTime createdAt,
                QDateTime expiresAt);

    int id() const { return m_id; }
    void setId(int id) { m_id = id; }

    int userId() const { return m_userId; }
    void setUserId(int userId) { m_userId = userId; }

    QString tokenHash() const { return m_tokenHash; }
    void setTokenHash(const QString &tokenHash) { m_tokenHash = tokenHash; }

    QString deviceLabel() const { return m_deviceLabel; }
    void setDeviceLabel(const QString &deviceLabel) { m_deviceLabel = deviceLabel; }

    QDateTime createdAt() const { return m_createdAt; }
    void setCreatedAt(const QDateTime &createdAt) { m_createdAt = createdAt; }

    QDateTime expiresAt() const { return m_expiresAt; }
    void setExpiresAt(const QDateTime &expiresAt) { m_expiresAt = expiresAt; }

    /// true si expiresAt() est dans le passe par rapport a l'heure UTC actuelle.
    bool isExpired() const;

    bool isValid() const;

private:
    int m_id = -1;
    int m_userId = -1;
    QString m_tokenHash;
    QString m_deviceLabel;
    QDateTime m_createdAt;
    QDateTime m_expiresAt;
};

} // namespace models

#endif // MODELS_USERSESSION_H
