#ifndef MODELS_SHAREDFOLDERFILTERPROXY_H
#define MODELS_SHAREDFOLDERFILTERPROXY_H

#include <QSortFilterProxyModel>
#include "SharedFolderModel.h"

namespace models {

/**
 * @brief Proxy de filtrage pour SharedFolderModel, utilisé par
 * ui/SharedFolder/SharedFolderView.qml (grille et liste des dossiers
 * partagés) afin que les lignes filtrées disparaissent réellement du
 * modèle exposé à GridView/ListView, plutôt que d'être seulement
 * masquées via `visible` dans le delegate (ce qui laisse un trou dans
 * une GridView, dont le placement en cellules dépend de l'index dans
 * le modèle source).
 */
class SharedFolderFilterProxy : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(QString filterMode READ filterMode WRITE setFilterMode NOTIFY filterModeChanged)
    Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY searchTextChanged)

public:
    explicit SharedFolderFilterProxy(QObject *parent = nullptr);

    QString filterMode() const { return m_filterMode; }
    void setFilterMode(const QString &mode);

    QString searchText() const { return m_searchText; }
    void setSearchText(const QString &text);

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

signals:
    void filterModeChanged();
    void searchTextChanged();

private:
    QString m_filterMode = QStringLiteral("all");   // "all" | "mine" | "received"
    QString m_searchText;
};

} // namespace models

#endif // MODELS_SHAREDFOLDERFILTERPROXY_H