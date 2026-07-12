#include "SharedFolderPermission.h"

namespace models {

QString sharedFolderPermissionToString(SharedFolderPermission permission)
{
    switch (permission) {
    case SharedFolderPermission::Read:
        return QStringLiteral("read");
    case SharedFolderPermission::Write:
        return QStringLiteral("write");
    case SharedFolderPermission::None:
    default:
        return QStringLiteral("none");
    }
}

std::optional<SharedFolderPermission> stringToSharedFolderPermission(const QString &value)
{
    const QString normalized = value.trimmed().toLower();
    if (normalized == QStringLiteral("read")) {
        return SharedFolderPermission::Read;
    }
    if (normalized == QStringLiteral("write")) {
        return SharedFolderPermission::Write;
    }
    if (normalized == QStringLiteral("none")) {
        return SharedFolderPermission::None;
    }
    return std::nullopt;
}

} // namespace models
