#include "SafePath.h"

#include <QDir>
#include <QFileInfo>
#include <QStringList>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace core::sync {

namespace {

Qt::CaseSensitivity pathCase()
{
#ifdef Q_OS_WIN
    return Qt::CaseInsensitive;
#else
    return Qt::CaseSensitive;
#endif
}

/// Vrai si `path` est `root` lui-meme ou se trouve sous `root`.
bool isUnder(const QString &root, const QString &path)
{
    if (path.compare(root, pathCase()) == 0)
        return true;
    const QString prefix = root.endsWith(QLatin1Char('/')) ? root : root + QLatin1Char('/');
    return path.startsWith(prefix, pathCase());
}

/// Chemin reel d'un element existant, liens symboliques ET jonctions resolus.
/// Sous Windows, QFileInfo::canonicalFilePath() ne suit pas les jonctions : on
/// interroge le systeme (GetFinalPathNameByHandleW), qui renvoie la cible finale.
QString realPath(const QString &existingPath)
{
#ifdef Q_OS_WIN
    const std::wstring native = QDir::toNativeSeparators(existingPath).toStdWString();
    HANDLE handle = CreateFileW(native.c_str(), 0,
                                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                                OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (handle != INVALID_HANDLE_VALUE) {
        wchar_t buffer[4096];
        const DWORD len = GetFinalPathNameByHandleW(handle, buffer, 4096, FILE_NAME_NORMALIZED);
        CloseHandle(handle);
        if (len > 0 && len < 4096) {
            QString resolved = QString::fromWCharArray(buffer, static_cast<int>(len));
            // Prefixes de chemin long : \\?\UNC\serveur\partage -> \\serveur\partage ; \\?\C:\... -> C:\...
            if (resolved.startsWith(QStringLiteral(R"(\\?\UNC\)")))
                resolved = QStringLiteral(R"(\\)") + resolved.mid(8);
            else if (resolved.startsWith(QStringLiteral(R"(\\?\)")))
                resolved = resolved.mid(4);
            return QDir::cleanPath(QDir::fromNativeSeparators(resolved));
        }
    }
    return QString(); // introuvable ou inaccessible : l'appelant refuse par prudence
#else
    return QFileInfo(existingPath).canonicalFilePath();
#endif
}

/// Chemin reel du plus proche ancetre existant de `path`.
QString canonicalOfNearestExisting(const QString &path)
{
    QString current = path;
    while (!current.isEmpty()) {
        const QFileInfo info(current);
        if (info.exists())
            return realPath(current);
        const QString parent = info.absolutePath();
        if (parent == current)
            break;
        current = parent;
    }
    return QString();
}

} // namespace

QString resolveInsideFolder(const QString &root, const QString &relativePath)
{
    if (root.trimmed().isEmpty() || relativePath.trimmed().isEmpty())
        return QString();

    QString rel = relativePath;
    rel.replace(QLatin1Char('\\'), QLatin1Char('/'));

    // Absolu, UNC ("//serveur"), lettre de lecteur ("C:..."), flux NTFS ("a.txt:flux").
    if (rel.startsWith(QLatin1Char('/')) || QDir::isAbsolutePath(rel) || rel.contains(QLatin1Char(':')))
        return QString();

    const QStringList segments = rel.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    QStringList kept;
    for (const QString &segment : segments) {
        if (segment == QLatin1String(".."))
            return QString();
        if (segment == QLatin1String("."))
            continue;
#ifdef Q_OS_WIN
        // Noms reserves de Windows (CON, NUL, COM1...) et noms finissant par
        // un point ou un espace : impossibles a creer correctement ici (un
        // poste Linux peut les partager). Refuses plutot que mal ecrits.
        static const QStringList reserved = {
            QStringLiteral("CON"), QStringLiteral("PRN"), QStringLiteral("AUX"), QStringLiteral("NUL"),
            QStringLiteral("COM1"), QStringLiteral("COM2"), QStringLiteral("COM3"), QStringLiteral("COM4"),
            QStringLiteral("COM5"), QStringLiteral("COM6"), QStringLiteral("COM7"), QStringLiteral("COM8"),
            QStringLiteral("COM9"), QStringLiteral("LPT1"), QStringLiteral("LPT2"), QStringLiteral("LPT3"),
            QStringLiteral("LPT4"), QStringLiteral("LPT5"), QStringLiteral("LPT6"), QStringLiteral("LPT7"),
            QStringLiteral("LPT8"), QStringLiteral("LPT9")};
        if (segment.endsWith(QLatin1Char('.')) || segment.endsWith(QLatin1Char(' '))
            || reserved.contains(segment.section(QLatin1Char('.'), 0, 0).trimmed(), Qt::CaseInsensitive))
            return QString();
#endif
        kept << segment;
    }
    if (kept.isEmpty())
        return QString(); // le dossier lui-meme n'est jamais une cible valide

    const QString cleanRoot = QDir::cleanPath(QFileInfo(root).absoluteFilePath());
    const QString target = QDir::cleanPath(cleanRoot + QLatin1Char('/') + kept.join(QLatin1Char('/')));
    if (!isUnder(cleanRoot, target) || target.compare(cleanRoot, pathCase()) == 0)
        return QString();

    // Liens symboliques / jonctions : la cible reelle doit rester dans le dossier reel.
    if (QFileInfo::exists(cleanRoot)) {
        const QString canonicalRoot = realPath(cleanRoot);
        const QString canonicalTarget = canonicalOfNearestExisting(target);
        if (canonicalRoot.isEmpty() || canonicalTarget.isEmpty() || !isUnder(canonicalRoot, canonicalTarget))
            return QString();
    }

    return target;
}

} // namespace core::sync
