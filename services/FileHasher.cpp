#include "FileHasher.h"

#include <QCryptographicHash>
#include <QFile>

namespace services {
namespace FileHasher {

QString hashFile(const QString &absoluteFilePath)
{
    QFile file(absoluteFilePath);
    if (!file.open(QIODevice::ReadOnly)) {
        return QString();
    }

    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&file)) {
        return QString();
    }
    return QString::fromLatin1(hash.result().toHex());
}

} // namespace FileHasher
} // namespace services
