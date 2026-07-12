#ifndef MODELS_SHAREDFILE_H
#define MODELS_SHAREDFILE_H

#include <QDateTime>
#include <QString>

namespace models {

/**
 * @brief Represente un fichier suivi a l'interieur d'un SharedFolder.
 *
 * Correspond a une ligne de la table `SharedFiles`. Le chemin est
 * toujours stocke sous forme relative au dossier partage (relativePath),
 * jamais en absolu, afin de pouvoir etre compare entre plusieurs postes
 * dont l'arborescence locale peut differer.
 *
 * Exemple : pour un dossier partage "Projet" contenant
 * Projet/Docs/cahier.pdf, relativePath vaut "Docs/cahier.pdf".
 */
class SharedFile {
public:
    SharedFile();
    SharedFile(int id,
               int folderId,
               QString relativePath,
               QString hash,
               qint64 size,
               QDateTime lastModified,
               int version = 1,
               bool deleted = false);

    int id() const;
    void setId(int id);

    int folderId() const;
    void setFolderId(int folderId);

    QString relativePath() const;
    void setRelativePath(const QString &relativePath);

    // Empreinte du contenu (SHA-256), utilisee pour detecter les
    // modifications et les conflits sans comparer les fichiers octet a octet.
    QString hash() const;
    void setHash(const QString &hash);

    qint64 size() const;
    void setSize(qint64 size);

    QDateTime lastModified() const;
    void setLastModified(const QDateTime &lastModified);

    // Incremente a chaque modification locale ou distante appliquee ;
    // sert de base a la detection de conflits (core::ConflictResolver)
    // et au rattrapage des postes qui reviennent en ligne.
    int version() const;
    void setVersion(int version);

    // Suppression logique : la ligne est conservee (historique, reprise
    // de synchronisation) mais le fichier n'existe plus sur le disque.
    bool deleted() const;
    void setDeleted(bool deleted);

    bool isValid() const;

private:
    int m_id = -1;
    int m_folderId = -1;
    QString m_relativePath;
    QString m_hash;
    qint64 m_size = 0;
    QDateTime m_lastModified;
    int m_version = 1;
    bool m_deleted = false;
};

} // namespace models

#endif // MODELS_SHAREDFILE_H
