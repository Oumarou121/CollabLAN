#ifndef CORE_AUDITMANAGER_H
#define CORE_AUDITMANAGER_H

#include <QObject>
#include <QString>
#include <QHostAddress>
#include <QVector>
#include <optional>
#include <memory>

#include "models/AuditLog.h"

namespace database {
class DatabaseManager;
class AuditLogRepository;
struct AuditLogFilter;
}

namespace core {

/// Types d'evenements normalises geres par AuditManager (issue #62).
/// Les valeurs textuelles (eventTypeToString) sont celles persistees en
/// base et utilisables comme critere de filtrage (issue #63).
enum class AuditEventType {
    Connection,     ///< Connexion etablie/perdue avec un autre poste.
    Message,        ///< Message envoye/recu (metadonnees uniquement, jamais le contenu).
    Transfer,       ///< Transfert de fichier demarre/termine/echoue.
    Call,           ///< Appel vocal demarre/termine.
    AccessDenied,   ///< Tentative refusee (auth, permission, appel/connexion non autorise).
};

QString auditEventTypeToString(AuditEventType type);

/**
 * @brief Centralise l'enregistrement des evenements auditables (issue #62).
 *
 * Fournit une methode dediee par categorie d'evenement (connexions,
 * messages, transferts, appels, tentatives refusees) qui construit une
 * entree models::AuditLog au format normalise (horodatage, type, acteur,
 * detail) et la persiste via database::AuditLogRepository (issue #63).
 *
 * Pour les messages, seules les metadonnees sont journalisees (expediteur,
 * destinataire/conversation) : le contenu du message n'est jamais transmis
 * a AuditManager, conformement au critere de confidentialite de l'issue #62.
 *
 * L'acteur d'un evenement est soit un utilisateur authentifie (userId),
 * soit identifie par une etiquette libre (adresse IP, nom de poste) quand
 * aucune authentification n'a eu lieu, ce qui est notamment le cas pour
 * les tentatives refusees.
 */
class AuditManager : public QObject
{
    Q_OBJECT

public:
    explicit AuditManager(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~AuditManager() override;

    /// Enregistre une connexion etablie ou perdue avec un poste distant.
    void logConnection(std::optional<qint64> userId, const QHostAddress &peerAddress,
                        bool established, const QString &detail = QString());

    /// Enregistre l'envoi/la reception d'un message. Ne prend en parametre
    /// que des metadonnees (jamais le contenu du message).
    void logMessage(qint64 senderId, qint64 conversationId, bool outgoing);

    /// Enregistre le demarrage, la fin ou l'echec d'un transfert de fichier.
    void logTransfer(qint64 userId, const QString &fileName, qint64 fileSizeBytes,
                      const QString &status, const QString &detail = QString());

    /// Enregistre le demarrage ou la fin d'un appel vocal.
    void logCall(std::optional<qint64> userId, const QHostAddress &peerAddress,
                 const QString &status, const QString &detail = QString());

    /// Enregistre une tentative refusee (authentification, permission,
    /// connexion ou appel non autorise...). peerAddress permet d'auditer
    /// un acteur non authentifie.
    void logRefusedAttempt(const QString &reason, const QHostAddress &peerAddress = QHostAddress(),
                            std::optional<qint64> userId = std::nullopt);

    /// Enregistrement generique, utilise en interne par les methodes
    /// specialisees ci-dessus mais egalement disponible pour des
    /// evenements non prevus par les categories existantes.
    void recordEvent(AuditEventType type, const QString &description,
                      std::optional<qint64> userId = std::nullopt,
                      const QString &actorLabel = QString());

    /// Insere un evenement provenant d'une autre base sans le rediffuser.
    bool recordRemoteEvent(const models::AuditLog &entry);

    /// Consultation filtree du journal (delegue a AuditLogRepository,
    /// voir issue #63 pour les criteres disponibles).
    QVector<models::AuditLog> queryEvents(const database::AuditLogFilter &filter);

signals:
    /// Emis apres chaque enregistrement reussi, utile pour un affichage
    /// temps reel du journal d'audit dans l'UI.
    void eventRecorded(const models::AuditLog &entry);
    void remoteEventRecorded(const models::AuditLog &entry);

private:
    database::DatabaseManager *m_dbManager = nullptr;
    std::unique_ptr<database::AuditLogRepository> m_repository;
};

} // namespace core

#endif // CORE_AUDITMANAGER_H
