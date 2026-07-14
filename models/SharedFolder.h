#ifndef MODELS_SHAREDFOLDER_H
#define MODELS_SHAREDFOLDER_H

#include <QString>
#include <QDateTime>

namespace models {

/**
 * @brief Represente un dossier partage (module "Shared Folder").
 *
 * localPath est le chemin sur le disque de CE poste : deux postes peuvent
 * avoir un chemin local different pour le "meme" dossier partage logique,
 * d'ou l'uuid stable (independant de l'id local AUTOINCREMENT) utilise
 * comme identifiant inter-postes, a la maniere de models::Group.
 */
class SharedFolder {
public:
    SharedFolder();
    SharedFolder(qint64 id, QString name, QString localPath);

    qint64 id() const { return m_id; }
    void setId(qint64 id) { m_id = id; }

    QString uuid() const { return m_uuid; }
    void setUuid(const QString &uuid) { m_uuid = uuid; }

    QString name() const { return m_name; }
    void setName(const QString &name) { m_name = name; }

    /// Chemin absolu local (specifique a ce poste).
    QString localPath() const { return m_localPath; }
    void setLocalPath(const QString &localPath) { m_localPath = localPath; }

    qint64 ownerId() const { return m_ownerId; }
    void setOwnerId(qint64 ownerId) { m_ownerId = ownerId; }

    QDateTime createdAt() const { return m_createdAt; }
    void setCreatedAt(const QDateTime &createdAt) { m_createdAt = createdAt; }

    bool isActive() const { return m_isActive; }
    void setIsActive(bool isActive) { m_isActive = isActive; }

    /// UUID DiscoveryService::localId() de la machine qui possede
    /// reellement les fichiers de ce dossier (migration 020). Vide pour
    /// un dossier cree sur CE poste (ce poste EST l'origine) ; non vide
    /// pour un dossier dont on n'a recu que les metadonnees (uuid, nom...)
    /// via SyncLog/diffusion temps reel (issues A1/A2) -- son local_path
    /// n'a alors aucun sens sur ce poste, et toute recuperation de
    /// contenu doit passer par une demande de transfert a cette machine
    /// (issue A3).
    QString originMachineId() const { return m_originMachineId; }
    void setOriginMachineId(const QString &originMachineId) { m_originMachineId = originMachineId; }

    /// true si ce poste possede reellement le contenu de ce dossier
    /// (createur local), false si ce n'est qu'une replique de metadonnees
    /// recue d'un autre poste.
    bool isLocalOrigin() const { return m_originMachineId.isEmpty(); }

    /// Motifs glob (separes par des virgules) exclus de l'indexation/sync
    /// pour CE dossier partage, en plus des exclusions codees en dur
    /// (migration #022, debrief point #4 -- sync selective). Local a ce
    /// poste : non synchronise entre pairs, cf. commentaire migration.
    QString excludePatterns() const { return m_excludePatterns; }
    void setExcludePatterns(const QString &excludePatterns) { m_excludePatterns = excludePatterns; }

private:
    qint64 m_id = 0;
    QString m_uuid;
    QString m_name;
    QString m_localPath;
    qint64 m_ownerId = 0;
    QDateTime m_createdAt;
    bool m_isActive = true;
    QString m_originMachineId;
    QString m_excludePatterns = QStringLiteral("");
};

} // namespace models

#endif // MODELS_SHAREDFOLDER_H
