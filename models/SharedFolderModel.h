#ifndef MODELS_SHAREDFOLDERMODEL_H
#define MODELS_SHAREDFOLDERMODEL_H

#include <QAbstractListModel>
#include <QVector>
#include "SharedFolder.h"

namespace models {

/**
 * @brief Modele QML pour exposer les dossiers partages a l'interface
 * (ui/SharedFolder/SharedFolderView.qml), sur le meme principe que
 * models::GroupModel.
 */
class SharedFolderModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum SharedFolderRoles {
        FolderIdRole = Qt::UserRole + 1,
        UuidRole,
        NameRole,
        LocalPathRole,
        OwnerIdRole,
        FileCountRole,
        IsActiveRole
    };

    explicit SharedFolderModel(QObject *parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

    void setFolders(const QVector<SharedFolder> &folders);
    void addFolder(const SharedFolder &folder);
    void removeFolder(qint64 folderId);
    void clear();

    /// Nombre de fichiers (non supprimes) connus pour chaque dossier,
    /// indexe par SharedFolder::id(). Alimente par
    /// core::SharedFolderContext a partir de SharedFileRepository::count().
    void setFileCounts(const QHash<qint64, int> &counts);

private:
    QVector<SharedFolder> m_folders;
    QHash<qint64, int> m_fileCounts;
};

} // namespace models

#endif // MODELS_SHAREDFOLDERMODEL_H
