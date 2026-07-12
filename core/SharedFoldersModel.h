#ifndef CORE_SHAREDFOLDERSMODEL_H
#define CORE_SHAREDFOLDERSMODEL_H

#include <QAbstractListModel>
#include <QList>

#include "database/Repositories/SharedFileRepository.h"
#include "models/SharedFolder.h"

namespace database {
class DatabaseManager;
}

namespace core {

class SharedFolderManager;

/**
 * @brief Modele Qt exposant a QML la liste des dossiers partages actifs,
 * pour l'ecran SharedFolder (Phase 11), sur le meme principe que
 * network::PeersModel : reagit aux signaux de SharedFolderManager pour
 * rester a jour sans rafraichissement manuel.
 */
class SharedFoldersModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        LocalPathRole,
        FileCountRole,
        IsActiveRole,
    };
    Q_ENUM(Roles)

    explicit SharedFoldersModel(SharedFolderManager *manager, database::DatabaseManager *databaseManager, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;

signals:
    void countChanged();

private slots:
    void reload();

private:
    SharedFolderManager *m_manager = nullptr;
    database::SharedFileRepository m_fileRepository;
    QList<models::SharedFolder> m_folders;
};

} // namespace core

#endif // CORE_SHAREDFOLDERSMODEL_H
