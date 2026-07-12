#ifndef CORE_SHAREDFOLDERCONTEXT_H
#define CORE_SHAREDFOLDERCONTEXT_H

#include <QObject>
#include <QString>
#include <QVariantList>

#include "SharedFolderManager.h"
#include "UserManager.h"
#include "models/SharedFolderModel.h"

namespace core {

/**
 * @brief Wrapper pour exposer le module "Shared Folder" a QML
 * (ui/SharedFolder/SharedFolderView.qml), sur le meme principe que
 * core::TransferContext pour le transfert de fichiers.
 */
class SharedFolderContext : public QObject
{
    Q_OBJECT
    Q_PROPERTY(models::SharedFolderModel* folderModel READ folderModel CONSTANT)
    Q_PROPERTY(QString lastErrorString READ lastErrorString NOTIFY errorOccurred)

public:
    explicit SharedFolderContext(QObject *parent = nullptr);
    ~SharedFolderContext() override;

    void setSharedFolderManager(SharedFolderManager *manager);
    void setUserManager(UserManager *manager);

    models::SharedFolderModel* folderModel() const { return m_folderModel; }
    QString lastErrorString() const { return m_lastErrorString; }

    /// Recharge la liste des dossiers partages (et le nombre de fichiers
    /// de chacun) depuis la base. Appele automatiquement apres chaque
    /// creation/suppression/partage.
    Q_INVOKABLE void refresh();

    /// Cree un dossier partage a partir de localPath (chemin choisi via
    /// FolderDialog cote QML) puis l'indexe immediatement (shareFolder()) :
    /// depuis l'UI, "creer" et "partager" ne font qu'un, la distinction
    /// createFolder()/shareFolder() servant surtout a SharedFolderManager
    /// (ex: reindexer un dossier deja partage sans le recreer).
    /// @return true si la creation a reussi (voir lastErrorString() sinon).
    Q_INVOKABLE bool createFolder(const QString &name, const QString &localPath);

    Q_INVOKABLE bool removeFolder(qint64 folderId);

    /// Reindexe le contenu local d'un dossier deja partage (ex: apres
    /// modification manuelle des fichiers hors CollabLAN).
    Q_INVOKABLE bool shareFolder(qint64 folderId);

    /// Contenu (fichiers non supprimes) d'un dossier partage, pret a
    /// servir de modele QML : chaque element est une QVariantMap
    /// relativePath/size/hash/version/lastModified.
    Q_INVOKABLE QVariantList filesForFolder(qint64 folderId) const;

signals:
    void errorOccurred(const QString &message);

private:
    SharedFolderManager *m_manager = nullptr;
    UserManager *m_userManager = nullptr;
    models::SharedFolderModel *m_folderModel = nullptr;
    QString m_lastErrorString;
};

} // namespace core

#endif // CORE_SHAREDFOLDERCONTEXT_H
