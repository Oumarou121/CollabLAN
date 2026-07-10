#ifndef MODELS_AUDITLOG_H
#define MODELS_AUDITLOG_H

#include <QString>
#include <QDateTime>
#include <optional>

namespace models {

/**
 * @brief Represente une entree du journal d'audit (issue #62/#63).
 *
 * Format normalise : horodatage, type d'evenement, acteur, detail.
 * L'acteur est soit un utilisateur authentifie (userId renseigne), soit
 * un acteur non authentifie identifie par une etiquette libre
 * (actorLabel : adresse IP, nom de poste...), utile notamment pour les
 * tentatives de connexion refusees.
 */
class AuditLog
{
public:
    AuditLog();
    AuditLog(const QString &eventType, const QString &description,
             std::optional<qint64> userId, const QString &actorLabel);

    qint64 id() const { return m_id; }
    void setId(qint64 id) { m_id = id; }

    /// Type d'evenement normalise, ex: "connection", "message",
    /// "transfer", "call", "access_denied". Voir core::AuditManager pour
    /// les constantes utilisees par l'application.
    QString eventType() const { return m_eventType; }
    void setEventType(const QString &eventType) { m_eventType = eventType; }

    /// Detail lisible de l'evenement (ex: "Connexion etablie depuis 192.168.1.12").
    QString description() const { return m_description; }
    void setDescription(const QString &description) { m_description = description; }

    /// Identifiant de l'utilisateur authentifie a l'origine de l'evenement,
    /// absent si l'acteur n'est pas (ou pas encore) authentifie.
    std::optional<qint64> userId() const { return m_userId; }
    void setUserId(std::optional<qint64> userId) { m_userId = userId; }

    /// Etiquette lisible de l'acteur quand userId() est absent (adresse IP,
    /// nom de poste distant...). Peut aussi completer userId() a titre
    /// informatif.
    QString actorLabel() const { return m_actorLabel; }
    void setActorLabel(const QString &actorLabel) { m_actorLabel = actorLabel; }

    QDateTime timestamp() const { return m_timestamp; }
    void setTimestamp(const QDateTime &timestamp) { m_timestamp = timestamp; }

private:
    qint64 m_id = 0;
    QString m_eventType;
    QString m_description;
    std::optional<qint64> m_userId;
    QString m_actorLabel;
    QDateTime m_timestamp;
};

} // namespace models

#endif // MODELS_AUDITLOG_H
