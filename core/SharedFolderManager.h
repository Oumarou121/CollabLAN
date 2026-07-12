#ifndef CORE_SHAREDFOLDERMANAGER_H
#define CORE_SHAREDFOLDERMANAGER_H

#include <QObject>
#include <QString>
#include <optional>
#include <vector>

#include "database/Repositories/SharedFolderRepository.h"
#include "models/SharedFolder.h"

namespace database {
class DatabaseManager;
}

namespace core {

/**
 * @brief Gestion des dossiers partages : creation, suppression,
 * chargement, activation du partage (Phase 2 de la fonctionnalite
 * "Shared Folder").
 *
 * Volontairement sans aucune logique reseau (ni surveillance disque, ni
 * synchronisation) : il s'agit d'une simple couche CRUD au-dessus de
 * SharedFolderRepository, exposee a la QML pour l'ecran de gestion des
 * dossiers partages. La surveillance (core::SyncEngine /
 * services::FolderWatcher) et le reseau (network::SyncNetworkService)
 * sont brooches separement par Application, qui reagit aux signaux
 * folderCreated/folderRemoved pour demarrer/arreter le suivi.
 */
class SharedFolderManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(int folderCount READ folderCount NOTIFY foldersChanged)

public:
    // databaseManager doit rester valide pendant toute la duree de vie
    // de SharedFolderManager (Application en est proprietaire).
    explicit SharedFolderManager(database::DatabaseManager *databaseManager, QObject *parent = nullptr);
    ~SharedFolderManager() override;

    // --- API QML -----------------------------------------------------

    // Cree un dossier partage a partir d'un chemin local existant.
    // Emet folderCreated() sur succes, folderOperationFailed(reason) sinon.
    Q_INVOKABLE bool createFolder(const QString &name, const QString &localPath, int ownerId);

    // Desactive le partage (le dossier reste dans l'historique mais
    // n'est plus surveille ni synchronise). Voir SharedFolder::isActive.
    Q_INVOKABLE bool removeFolder(int folderId);

    // (Re)active le partage d'un dossier deja enregistre.
    Q_INVOKABLE bool shareFolder(int folderId);

    int folderCount() const;

    // --- API C++ -------------------------------------------------------

    std::vector<models::SharedFolder> getFolders() const;
    std::vector<models::SharedFolder> activeFolders() const;
    std::optional<models::SharedFolder> findById(int folderId) const;

    QString lastError() const;

signals:
    void foldersChanged();
    void folderCreated(const models::SharedFolder &folder);
    void folderRemoved(int folderId);
    void folderShared(const models::SharedFolder &folder);
    void folderOperationFailed(const QString &reason);

private:
    database::DatabaseManager *m_databaseManager;
    database::SharedFolderRepository m_repository;
    QString m_lastError;
};

} // namespace core

#endif // CORE_SHAREDFOLDERMANAGER_H
