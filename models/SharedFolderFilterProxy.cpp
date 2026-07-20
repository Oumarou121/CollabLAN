#include "SharedFolderFilterProxy.h"

namespace models {

SharedFolderFilterProxy::SharedFolderFilterProxy(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setDynamicSortFilter(true);
    setFilterCaseSensitivity(Qt::CaseInsensitive);
}

void SharedFolderFilterProxy::setFilterMode(const QString &mode)
{
    if (m_filterMode == mode) {
        return;
    }
    m_filterMode = mode;
    emit filterModeChanged();
    invalidateFilter();
}

void SharedFolderFilterProxy::setSearchText(const QString &text)
{
    if (m_searchText == text) {
        return;
    }
    m_searchText = text;
    emit searchTextChanged();
    invalidateFilter();
}

bool SharedFolderFilterProxy::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    const QModelIndex idx = sourceModel()->index(sourceRow, 0, sourceParent);
    if (!idx.isValid()) {
        return false;
    }

    const bool isLocalOrigin = idx.data(SharedFolderModel::IsLocalOriginRole).toBool();
    if (m_filterMode == QStringLiteral("mine") && !isLocalOrigin) {
        return false;
    }
    if (m_filterMode == QStringLiteral("received") && isLocalOrigin) {
        return false;
    }

    if (!m_searchText.isEmpty()) {
        const QString name = idx.data(SharedFolderModel::NameRole).toString();
        if (!name.contains(m_searchText, Qt::CaseInsensitive)) {
            return false;
        }
    }

    return true;
}

} // namespace models