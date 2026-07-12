#ifndef MODELS_SHAREDFOLDER_H
#define MODELS_SHAREDFOLDER_H

#include <QDateTime>
#include <QString>

namespace models {

/**
 * @brief Represente un dossier partage sur le reseau local (fonctionnalite
 * "Shared Folder", inspiree du partage de dossiers Windows / Dropbox).
 *
 * Correspond a une ligne de la table `SharedFolders`. Ne contient aucune
 * logique de synchronisation : c'est un simple conteneur de donnees,
 * manipule par core::SharedFolderManager (CRUD) et core::SyncEngine
 * (surveillance + synchronisation).
 */
class SharedFolder {
public:
    SharedFolder();
    SharedFolder(int id,
                 QString name,
                 QString localPath,
                 int ownerId,
                 bool isActive = true,
                 QDateTime createdAt = QDateTime::currentDateTimeUtc());

    int id() const;
    void setId(int id);

    QString name() const;
    void setName(const QString &name);

    // Chemin absolu, sur cette machine, du dossier partage sur le disque.
    QString localPath() const;
    void setLocalPath(const QString &localPath);

    int ownerId() const;
    void setOwnerId(int ownerId);

    QDateTime createdAt() const;
    void setCreatedAt(const QDateTime &createdAt);

    // Un dossier inactif reste enregistre (historique) mais n'est plus
    // surveille ni synchronise (cf. SharedFolderManager::removeFolder,
    // qui desactive plutot que de supprimer definitivement).
    bool isActive() const;
    void setIsActive(bool isActive);

    bool isValid() const;

private:
    int m_id = -1;
    QString m_name;
    QString m_localPath;
    int m_ownerId = -1;
    bool m_isActive = true;
    QDateTime m_createdAt;
};

} // namespace models

#endif // MODELS_SHAREDFOLDER_H
